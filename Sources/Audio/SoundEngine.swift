import Foundation
import AVFoundation
import Combine

/// Procedural, generative soundscape mixer built entirely on AVAudioEngine —
/// NO audio files. Each `SoundLayer` is an `AVAudioSourceNode` that fills its
/// buffer with synthesized samples (filtered noise for rain/wind/noise, summed
/// detuned sines for the warm drone, an LFO-shaped surf for waves, a sparse
/// pentatonic celesta for the music box). All layers are audible in the
/// simulator. Plays under lock thanks to the `.playback` session category +
/// the `audio` UIBackgroundMode.
@MainActor
public final class SoundEngine: ObservableObject {
    public static let shared = SoundEngine()

    // Per-layer target volume (0…1), the user's mixer setting.
    @Published public private(set) var volumes: [SoundLayer: Double] = [:]
    @Published public private(set) var isRunning = false
    /// A global multiplier (0…1) the sleep-timer fade drives.
    @Published public var masterMultiplier: Double = 1.0 {
        didSet { applyGains() }
    }

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44_100

    // One source node + a generator per layer.
    private var nodes: [SoundLayer: AVAudioSourceNode] = [:]
    private var generators: [SoundLayer: LayerGenerator] = [:]
    // Smoothed gain per layer (target volume × master), updated on the audio
    // thread via a lock-light atomic-ish store.
    private let gainStore = GainStore()
    private var prepared = false

    private init() {
        for layer in SoundLayer.allCases { volumes[layer] = 0 }
    }

    // MARK: - Lifecycle

    public func prepare() {
        guard !prepared else { return }
        prepared = true
        configureSession()
        buildGraph()
    }

    private func configureSession() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback keeps audio going with the screen locked and ignores the
            // ring/silent switch — essential for a bedtime app.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal; the UI still works.
        }
        #endif
    }

    private func buildGraph() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let mixer = engine.mainMixerNode

        for layer in SoundLayer.allCases {
            let gen = LayerGenerator(layer: layer, sampleRate: sampleRate)
            generators[layer] = gen
            let store = gainStore
            let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let gain = Float(store.gain(for: layer))
                gen.render(frames: Int(frameCount), gain: gain, into: abl)
                return noErr
            }
            nodes[layer] = node
            engine.attach(node)
            engine.connect(node, to: mixer, format: format)
        }
        engine.prepare()
    }

    // MARK: - Controls

    /// Set a layer's volume (0…1). Starts the engine on first non-zero layer.
    public func setVolume(_ v: Double, for layer: SoundLayer) {
        prepare()
        let clamped = min(1, max(0, v))
        volumes[layer] = clamped
        applyGains()
        if clamped > 0 { start() }
        else if volumes.values.allSatisfy({ $0 <= 0 }) { stop() }
    }

    /// Apply a whole saved mix at once.
    public func apply(mix: [SoundLayer: Double]) {
        prepare()
        for layer in SoundLayer.allCases {
            volumes[layer] = min(1, max(0, mix[layer] ?? 0))
        }
        applyGains()
        if volumes.values.contains(where: { $0 > 0 }) { start() } else { stop() }
    }

    public func stopAll() {
        for layer in SoundLayer.allCases { volumes[layer] = 0 }
        applyGains()
        stop()
    }

    public var anyActive: Bool { volumes.values.contains { $0 > 0 } }

    private func applyGains() {
        for layer in SoundLayer.allCases {
            gainStore.set((volumes[layer] ?? 0) * masterMultiplier, for: layer)
        }
    }

    private func start() {
        guard prepared, !engine.isRunning else { isRunning = engine.isRunning; return }
        do {
            #if canImport(UIKit)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func stop() {
        guard engine.isRunning else { return }
        engine.pause()
        isRunning = false
    }
}

/// Thread-safe per-layer smoothed gain store shared between the main actor
/// (writes target) and the audio render thread (reads). Uses an os_unfair_lock.
final class GainStore: @unchecked Sendable {
    private var targets: [SoundLayer: Double] = [:]
    private var current: [SoundLayer: Double] = [:]
    private var lock = os_unfair_lock_s()

    func set(_ v: Double, for layer: SoundLayer) {
        os_unfair_lock_lock(&lock)
        targets[layer] = v
        os_unfair_lock_unlock(&lock)
    }

    /// Read on the audio thread; one-pole smooths toward the target to avoid
    /// zipper noise when sliders move.
    func gain(for layer: SoundLayer) -> Double {
        os_unfair_lock_lock(&lock)
        let target = targets[layer] ?? 0
        let cur = current[layer] ?? 0
        let smoothed = cur + (target - cur) * 0.0015
        current[layer] = abs(smoothed - target) < 0.0001 ? target : smoothed
        let out = current[layer] ?? 0
        os_unfair_lock_unlock(&lock)
        return out
    }
}

/// Synthesizes one layer's stereo samples. Lives on the audio render thread.
final class LayerGenerator: @unchecked Sendable {
    let layer: SoundLayer
    let sampleRate: Double
    private var rng = SystemRandomNumberGenerator()

    // Filter / oscillator state.
    private var lp1: Double = 0      // low-pass state 1
    private var lp2: Double = 0      // low-pass state 2 (rain/waves)
    private var brown: Double = 0    // brown-noise integrator
    private var pinkB: [Double] = Array(repeating: 0, count: 7)
    private var phase: [Double] = []        // drone partials
    private var wavePhase: Double = 0       // surf LFO
    private var dropPhase: Double = 0       // rain shimmer
    // Motion state for the living weather layers (rain/wind/waves): two LFOs at
    // different rates plus a slow random-walk so they sweep and drift instead of
    // sitting static the moment they're turned on.
    private var lfoA: Double = 0
    private var lfoB: Double = 0
    private var drift: Double = 0.5         // random-walk value (use varies by layer)
    private var driftTarget: Double = 0.5
    private var driftTimer: Double = 0
    private var swellPeriod: Double = 12    // current wave swell length (s)
    private var swellHeight: Double = 1     // current wave swell height
    // Music-box scheduler.
    private var mbTimer: Double = 0
    private var mbVoices: [(freq: Double, phase: Double, env: Double, decay: Double)] = []

    init(layer: SoundLayer, sampleRate: Double) {
        self.layer = layer
        self.sampleRate = sampleRate
        // Warm drone: a low root plus a fifth and an octave, slightly detuned.
        if layer == .drone {
            phase = [0, 0, 0, 0]
        }
    }

    /// The broadband weather/noise layers are widened into stereo; the tonal
    /// layers (drone, music box) stay mono-centred for a solid image.
    private var isWide: Bool {
        switch layer {
        case .rain, .wind, .waves, .brownNoise, .pinkNoise: return true
        case .drone, .musicBox: return false
        }
    }
    // First-order all-pass decorrelation state for the right channel.
    private var apX1 = 0.0, apY1 = 0.0, apX2 = 0.0, apY2 = 0.0

    /// Phase-decorrelate a mono sample for the right channel — same spectrum,
    /// different phase, so the layer images wide without changing its tone. Two
    /// cascaded first-order all-passes with distinct coefficients.
    @inline(__always) private func decorrelate(_ x: Double) -> Double {
        let c1 = 0.72
        let y1 = c1 * x + apX1 - c1 * apY1
        apX1 = x; apY1 = y1
        let c2 = -0.55
        let y2 = c2 * y1 + apX2 - c2 * apY2
        apX2 = y1; apY2 = y2
        return y2
    }

    func render(frames: Int, gain: Float, into abl: UnsafeMutableAudioBufferListPointer) {
        // Fast path: silent layer writes zeros (still must clear the buffer).
        if gain <= 0.00005 {
            for buf in abl {
                if let p = buf.mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<frames { p[i] = 0 }
                }
            }
            return
        }
        let g = Double(gain)
        let dt = 1.0 / sampleRate
        let wide = isWide
        let n = abl.count
        for frame in 0..<frames {
            let s = sample(dt: dt) * g
            let l = s
            let r = wide ? decorrelate(s) : s
            if n >= 2 {
                abl[0].mData?.assumingMemoryBound(to: Float.self)[frame] = Float(l)
                abl[1].mData?.assumingMemoryBound(to: Float.self)[frame] = Float(r)
            } else if n == 1 {
                abl[0].mData?.assumingMemoryBound(to: Float.self)[frame] = Float(l)
            }
        }
    }

    private func white() -> Double { Double.random(in: -1...1, using: &rng) }

    /// Advance the slow random-walk `drift`: every `lo…hi` seconds it picks a new
    /// target somewhere in `range` and glides toward it over a few seconds. This
    /// is what keeps the weather layers from ever settling into a static loop.
    private func updateDrift(dt: Double, every lo: Double, _ hi: Double, range: ClosedRange<Double>) {
        driftTimer -= dt
        if driftTimer <= 0 {
            driftTimer = Double.random(in: lo...hi, using: &rng)
            driftTarget = Double.random(in: range, using: &rng)
        }
        drift += (driftTarget - drift) * (dt / 2.5)   // ~2.5 s glide
    }

    private func sample(dt: Double) -> Double {
        switch layer {
        case .brownNoise:
            // Integrated white noise (Brownian), leaked to stay bounded.
            brown += white() * 0.02
            brown *= 0.998
            return tanh(brown * 3.0) * 0.5

        case .pinkNoise:
            // Paul Kellet's pink-noise filter.
            let w = white()
            pinkB[0] = 0.99886 * pinkB[0] + w * 0.0555179
            pinkB[1] = 0.99332 * pinkB[1] + w * 0.0750759
            pinkB[2] = 0.96900 * pinkB[2] + w * 0.1538520
            pinkB[3] = 0.86650 * pinkB[3] + w * 0.3104856
            pinkB[4] = 0.55000 * pinkB[4] + w * 0.5329522
            pinkB[5] = -0.7616 * pinkB[5] - w * 0.0168980
            let pink = pinkB[0] + pinkB[1] + pinkB[2] + pinkB[3] + pinkB[4] + pinkB[5] + pinkB[6] + w * 0.5362
            pinkB[6] = w * 0.115926
            return pink * 0.11

        case .rain:
            // Filtered noise hiss + sparse droplets, now alive: a slow ebb
            // between a gentle patter and a heavier shower (two LFOs), plus a
            // drifting low-pass cutoff so the rain "opens and closes".
            lfoA += dt * 0.045                              // ~22 s breathing
            lfoB += dt * 0.013                              // ~77 s heavier passes
            let swell = 0.55 + 0.30 * sin(2 * .pi * lfoA) + 0.15 * sin(2 * .pi * lfoB)
            updateDrift(dt: dt, every: 8, 18, range: 0.32...0.6)   // cutoff drift
            let n = white()
            lp1 += (n - lp1) * drift
            lp2 += (lp1 - lp2) * drift
            var s = lp2 * (0.6 + 0.5 * swell)
            // Droplet density rides the swell, so heavier passes patter more.
            if Double.random(in: 0...1, using: &rng) < 0.0004 + 0.0010 * swell {
                dropPhase = 1
            }
            if dropPhase > 0 {
                s += (white() * dropPhase) * 0.5
                dropPhase *= 0.92
                if dropPhase < 0.01 { dropPhase = 0 }
            }
            return s * 0.6 * (0.7 + 0.4 * swell)

        case .wind:
            // Two gust LFOs at different rates, scaled by a slow random-walk in
            // gust strength → gusts that vary in force and spacing rather than a
            // fixed, repeating pulse.
            lfoA += dt * 0.07
            lfoB += dt * 0.017
            updateDrift(dt: dt, every: 6, 14, range: 0.35...1.0)   // gust strength
            let gust = max(0, 0.45 + 0.40 * sin(2 * .pi * lfoA) + 0.25 * sin(2 * .pi * lfoB)) * drift
            let n = white()
            lp1 += (n - lp1) * (0.03 + 0.12 * gust)
            return lp1 * (0.35 + 0.75 * gust) * 0.7

        case .waves:
            // Brown-ish surf, but every swell draws a fresh period and height, so
            // the surf never repeats on a metronome; a slow tide drift sits under
            // it for a longer ebb and flow.
            wavePhase += dt / swellPeriod
            if wavePhase >= 1 {
                wavePhase -= 1
                swellPeriod = Double.random(in: 9...16, using: &rng)
                swellHeight = Double.random(in: 0.7...1.0, using: &rng)
            }
            updateDrift(dt: dt, every: 15, 30, range: 0.7...1.0)   // tide level
            let swell = pow(0.5 + 0.5 * sin(2 * .pi * wavePhase), 2.0) * swellHeight * drift
            brown += white() * 0.02
            brown *= 0.997
            let surf = tanh(brown * 3.0)
            return surf * swell * 0.8

        case .drone:
            // Warm low chord: root ~110 Hz (A2), fifth, octave, slightly detuned,
            // through a gentle low-pass for a felt-not-heard pad.
            let freqs = [55.0, 82.5, 110.0, 110.5]   // A1, E2, A2, A2 detuned
            let amps  = [0.5, 0.28, 0.34, 0.30]
            var s = 0.0
            for i in 0..<freqs.count {
                phase[i] += 2 * .pi * freqs[i] * dt
                if phase[i] > 2 * .pi { phase[i] -= 2 * .pi }
                s += sin(phase[i]) * amps[i]
            }
            lp1 += (s - lp1) * 0.25     // soften the top
            return lp1 * 0.22

        case .musicBox:
            // A sparse, slow pentatonic celesta. Schedule a new note every few
            // seconds; each note is a fast-decaying sine with a shimmer harmonic.
            mbTimer -= dt
            if mbTimer <= 0 {
                mbTimer = Double.random(in: 2.6...4.8, using: &rng)
                // C major pentatonic across two octaves (gentle lullaby).
                let scale = [523.25, 587.33, 659.25, 783.99, 880.0,
                             1046.5, 1174.66, 1318.5]
                let f = scale.randomElement(using: &rng) ?? 523.25
                mbVoices.append((freq: f, phase: 0, env: 1, decay: Double.random(in: 1.6...2.6, using: &rng)))
                if mbVoices.count > 6 { mbVoices.removeFirst() }
            }
            var s = 0.0
            for i in mbVoices.indices {
                mbVoices[i].phase += 2 * .pi * mbVoices[i].freq * dt
                let env = mbVoices[i].env
                let fundamental = sin(mbVoices[i].phase) * env
                let shimmer = sin(mbVoices[i].phase * 2) * env * env * 0.25
                s += (fundamental + shimmer) * 0.5
                mbVoices[i].env *= pow(0.5, dt / mbVoices[i].decay)  // exp decay
            }
            mbVoices.removeAll { $0.env < 0.001 }
            return tanh(s) * 0.5
        }
    }
}
