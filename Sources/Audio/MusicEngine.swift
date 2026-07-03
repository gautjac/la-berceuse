import Foundation
import AVFoundation
import Combine

/// La Berceuse's generative-music engine — a procedural, ever-evolving composer
/// built entirely on AVAudioEngine, **no audio files, no network, no AI calls**.
/// It runs alongside the ambient `SoundEngine` (the two engines mix at the OS
/// level), so a listener can lay generative pads over rain if they like.
///
/// One `GenerativeMusicNode` synthesizes the whole music mix (evolving pads, a
/// low root, and phrased pentatonic melody) and applies a gentle, breath-synced
/// amplitude modulation to the summed signal — the brain.fm "neural phase-
/// locking" idea, dialled down to a swell rather than a throb. A light main-loop
/// timer recomputes `MusicParams` from offline context via `MusicDirector` so
/// the music adapts to the hour, the active breath pattern, the sleep-timer arc,
/// and (when granted) heart rate — the Endel-style adaptivity, fully on-device.
@MainActor
public final class MusicEngine: ObservableObject {
    public static let shared = MusicEngine()

    @Published public private(set) var isPlaying = false
    @Published public var program: MusicProgram = .sommeil
    /// The Intensité slider (0…1).
    @Published public var intensity: Double = 0.55
    /// The Pulsation slider (0…1) → amplitude-modulation depth.
    @Published public var pulse: Double = 0.5
    /// The Complexité slider (0…1) → how much is going on musically.
    @Published public var complexity: Double = 0.5
    /// The Écho slider (0…1) → the melody delay's presence and repeats.
    @Published public var echo: Double = 0.5
    /// The Réverbération slider (0…1) → the melody's reverb size and tail.
    @Published public var reverb: Double = 0.6

    /// Driven by the sleep-timer fade (mirrors `SoundEngine.masterMultiplier`).
    @Published public var masterMultiplier: Double = 1.0 {
        didSet { node?.setMaster(masterMultiplier) }
    }

    /// The active breath pattern's full-cycle period (seconds). The Souffle pulse
    /// locks to this; the view keeps it in sync with the user's chosen pattern.
    public var breathCyclePeriod: Double = BreathPattern.coherent.cycleDuration

    private let engine = AVAudioEngine()
    private let sampleRate: Double = 44_100
    private var node: GenerativeMusicNode?
    private var prepared = false

    private var refresher: AnyCancellable?
    private var heartRate: Double?
    private var lastHRFetch = Date.distantPast
    private var hrAuthorized = false

    private init() {}

    // MARK: - Lifecycle

    public func prepare() {
        guard !prepared else { return }
        prepared = true
        configureSession()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let gen = GenerativeMusicNode(sampleRate: sampleRate)
        node = gen
        let source = AVAudioSourceNode { _, _, frameCount, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            gen.render(frames: Int(frameCount), into: list)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private func configureSession() {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        // `.mixWithOthers` lets us coexist with SoundEngine's session without
        // either one tearing the other down; `.playback` keeps us alive locked.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    // MARK: - Controls

    public func play(_ program: MusicProgram? = nil) {
        prepare()
        if let program { self.program = program }
        pushParams()
        startRefresher()
        startEngine()
        requestHeartRateIfNeeded()
    }

    public func stop() {
        refresher?.cancel(); refresher = nil
        node?.setMaster(0)            // smooth duck so there's no click
        guard engine.isRunning else { isPlaying = false; return }
        engine.pause()
        isPlaying = false
        // Restore master for next time (the node smooths from 0 on restart).
        masterMultiplier = 1
    }

    public func toggle() { isPlaying ? stop() : play() }

    /// Re-derive parameters immediately (e.g. a slider moved).
    public func nudge() { pushParams() }

    private func startEngine() {
        guard prepared, !engine.isRunning else { isPlaying = engine.isRunning; return }
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        node?.setMaster(masterMultiplier)
        do { try engine.start(); isPlaying = true } catch { isPlaying = false }
    }

    // MARK: - Adaptive refresh

    private func startRefresher() {
        guard refresher == nil else { return }
        refresher = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        // Throttled heart-rate read (every ~20s) when available.
        if hrAuthorized, Date().timeIntervalSince(lastHRFetch) > 20 {
            lastHRFetch = Date()
            Task { [weak self] in
                let hr = await SleepHealth.shared.latestHeartRate()
                await MainActor.run { self?.heartRate = hr; self?.pushParams() }
            }
        }
        pushParams()
    }

    private func currentContext() -> MusicContext {
        let st = SleepTimerController.shared.timer
        let progress: Double = st.isActive && st.total > 0 ? min(1, st.elapsed / st.total) : 0
        let hour = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hourOfDay = Double(hour.hour ?? 22) + Double(hour.minute ?? 0) / 60.0
        return MusicContext(
            program: program,
            userIntensity: intensity,
            userPulse: pulse,
            userComplexity: complexity,
            sessionProgress: progress,
            hourOfDay: hourOfDay,
            breathCyclePeriod: breathCyclePeriod,
            heartRate: heartRate,
            userEcho: echo,
            userReverb: reverb)
    }

    private func pushParams() {
        node?.setParams(MusicDirector.params(for: currentContext()))
    }

    private func requestHeartRateIfNeeded() {
        guard !hrAuthorized else { return }
        // Screenshots opt out of the system HealthKit prompt.
        if ProcessInfo.processInfo.arguments.contains("-demoNoHealth") { return }
        Task { [weak self] in
            let ok = await SleepHealth.shared.requestHeartRateAuthorization()
            await MainActor.run { self?.hrAuthorized = ok }
        }
    }
}

// MARK: - The synthesizer (audio render thread)

/// Synthesizes the full generative-music mix and applies the amplitude
/// modulation. Lives on the realtime audio thread; reads a `MusicParams`
/// snapshot under a light lock and otherwise touches only its own state.
final class GenerativeMusicNode: @unchecked Sendable {
    private let sampleRate: Double

    // Parameter handoff (main → audio thread).
    private var params = MusicParams.silent
    private var paramLock = os_unfair_lock_s()
    private var masterTarget: Double = 0
    private var masterLock = os_unfair_lock_s()
    private var master: Double = 0          // smoothed, audio-thread only

    // Realtime-safe RNG (xorshift64) — no allocations, deterministic per seed.
    private var rngState: UInt64 = 0x9E3779B97F4A7C15

    // Harmony. The progression pool/step come from the params (the Complexité
    // control), rebuilt cheaply at each chord change.
    private var chordRootIndex = 0
    private var chordTimer = 0.0
    // A pad voice is an ensemble: three slightly detuned oscillators, each with
    // precomputed equal-power pan gains spread across the field for stereo width.
    private struct PadVoice {
        var freq: Double
        var phase: Double; var phase2: Double; var phase3: Double
        var gain: Double; var target: Double
        var gL0: Double; var gR0: Double     // pan gains, fundamental
        var gL1: Double; var gR1: Double     // detune −
        var gL2: Double; var gR2: Double     // detune +
    }
    private var padVoices: [PadVoice] = []

    // Bass (single gliding root) + a sub-octave under it for body.
    private var bassPhase = 0.0
    private var bassFreq = 0.0
    private var bassTargetFreq = 0.0
    private var subPhase = 0.0
    private var subFreq = 0.0
    private var subTargetFreq = 0.0

    // Melody (decaying plucks, phrased). `age` drives a fast pluck attack.
    private struct Pluck { var freq: Double; var phase: Double; var env: Double; var decay: Double; var age: Double }
    private var plucks: [Pluck] = []
    private var melodyTimer = 0.0

    // A sparse high "celesta" second voice, answering the melody.
    private var celesta: [Pluck] = []
    private var celestaTimer = 0.0

    // Filter + modulation + master-glue state (per channel where stereo).
    private var lpL = 0.0, lpR = 0.0     // brightness low-pass
    private var padLpL = 0.0, padLpR = 0.0
    private var padFilterLfo = 0.0
    private var melLp = 0.0              // rounds off the (mono) melody voice
    private var tiltL = 0.0, tiltR = 0.0 // warmth (low-shelf) state
    private var modPhase = 0.0

    // The melody's reverb + delay tail (procedural; pre-allocated).
    private let space: StereoSpace

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        space = StereoSpace(sampleRate: sampleRate)
        chordTimer = 0.01     // force an immediate first chord on first block
    }

    // MARK: handoff

    func setParams(_ p: MusicParams) {
        os_unfair_lock_lock(&paramLock); params = p; os_unfair_lock_unlock(&paramLock)
    }
    private func snapshot() -> MusicParams {
        os_unfair_lock_lock(&paramLock); let p = params; os_unfair_lock_unlock(&paramLock); return p
    }
    func setMaster(_ v: Double) {
        os_unfair_lock_lock(&masterLock); masterTarget = max(0, min(1, v)); os_unfair_lock_unlock(&masterLock)
    }
    private func masterTargetValue() -> Double {
        os_unfair_lock_lock(&masterLock); let v = masterTarget; os_unfair_lock_unlock(&masterLock); return v
    }

    private func nextRandom() -> Double {
        // xorshift64*, mapped to [0,1).
        rngState ^= rngState >> 12
        rngState ^= rngState << 25
        rngState ^= rngState >> 27
        let x = (rngState &* 0x2545F4914F6CDD1D) >> 11
        return Double(x) / Double(1 << 53)
    }
    private func rand(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * nextRandom() }

    /// A `RandomNumberGenerator` shim so we can reuse the pure `ChordProgression`.
    private struct NodeRNG: RandomNumberGenerator {
        var node: GenerativeMusicNode
        mutating func next() -> UInt64 {
            node.rngState ^= node.rngState >> 12
            node.rngState ^= node.rngState << 25
            node.rngState ^= node.rngState >> 27
            return node.rngState &* 0x2545F4914F6CDD1D
        }
    }

    // MARK: render

    func render(frames: Int, into abl: UnsafeMutableAudioBufferListPointer) {
        let p = snapshot()
        let dt = 1.0 / sampleRate
        let masterGoal = masterTargetValue()

        // Advance harmony at block rate (cheap, musically fine).
        advanceHarmony(p: p, blockSeconds: Double(frames) * dt)
        // Apply the live Écho / Réverbération settings once per block.
        space.apply(echoWet: p.echoWet, echoFeedback: p.echoFeedback,
                    reverbWet: p.reverbWet, reverbFeedback: p.reverbFeedback)

        let cutoff = 0.02 + 0.5 * p.brightness

        for frame in 0..<frames {
            // Smooth the master toward its goal (declick fades / starts / stops).
            master += (masterGoal - master) * 0.0008

            // Pads are stereo (panned ensemble); the bass + sub sit centred.
            let (padL, padR) = renderPad(p: p, dt: dt)
            let bass = renderBass(p: p, dt: dt) * p.bassGain
            // Melody + the sparse celesta second voice share the stereo space
            // (echo + reverb + shimmer), so both float wide behind the pads.
            let melDry = renderMelody(p: p, dt: dt) * p.melodyGain
                       + renderCelesta(p: p, dt: dt)
            let (melL, melR) = space.process(melDry)

            var sigL = padL * p.padGain + bass + melL
            var sigR = padR * p.padGain + bass + melR

            // Per-channel brightness low-pass.
            lpL += (sigL - lpL) * cutoff; sigL = lpL
            lpR += (sigR - lpR) * cutoff; sigR = lpR

            // Amplitude modulation (both channels), breath-synced.
            modPhase += p.modRateHz * dt
            if modPhase >= 1 { modPhase -= 1 }
            let am = AModMath.gain(phase: modPhase, depth: p.modDepth)
            sigL *= am; sigR *= am

            // Master glue: warmth (low-shelf) + soft saturation, then master gain.
            let outL = masterGlue(sigL, &tiltL) * master * 0.5
            let outR = masterGlue(sigR, &tiltR) * master * 0.5

            let n = abl.count
            if n >= 2 {
                abl[0].mData?.assumingMemoryBound(to: Float.self)[frame] = Float(outL)
                abl[1].mData?.assumingMemoryBound(to: Float.self)[frame] = Float(outR)
            } else if n == 1 {
                abl[0].mData?.assumingMemoryBound(to: Float.self)[frame] = Float((outL + outR) * 0.5)
            }
        }
    }

    /// Warmth + soft saturation for a single channel. A one-pole low-pass feeds a
    /// gentle low-shelf boost (cosy, dark), then `tanh` saturation adds harmonics
    /// and soft-limits peaks.
    @inline(__always) private func masterGlue(_ x: Double, _ tilt: inout Double) -> Double {
        tilt += (x - tilt) * 0.05                 // ~350 Hz one-pole
        let warmed = x + 0.18 * tilt              // low-shelf lift
        return AudioShaping.saturate(warmed, drive: 1.5)
    }

    private func advanceHarmony(p: MusicParams, blockSeconds: Double) {
        chordTimer -= blockSeconds
        if chordTimer <= 0 {
            chordTimer = max(4, p.chordSeconds)
            var rng = NodeRNG(node: self)
            let progression = ChordProgression(allowedRoots: p.progressionRoots,
                                               maxStep: p.progressionMaxStep)
            chordRootIndex = progression.nextRoot(current: chordRootIndex, using: &rng)
            let chord = PadChord(rootIndex: chordRootIndex, stack: p.chordStack)
            let notes = chord.midiNotes(rootMidi: p.rootMidi, scale: p.scale)

            // Fade the existing pad voices out, fade new chord tones in — each
            // panned to its own spot so the chord opens up across the field.
            for i in padVoices.indices { padVoices[i].target = 0 }
            let count = notes.count
            for (i, n) in notes.enumerated() {
                let f = Pitch.frequency(midi: Double(n))
                // Spread chord tones evenly across roughly ±0.7 of the field.
                let pan = count > 1 ? (Double(i) / Double(count - 1) - 0.5) * 1.4 : 0
                let (l0, r0) = Pan.gains(pan)
                let (l1, r1) = Pan.gains(max(-1, pan - 0.4))   // detune − leans left
                let (l2, r2) = Pan.gains(min(1, pan + 0.4))    // detune + leans right
                padVoices.append(PadVoice(
                    freq: f, phase: rand(0, 2 * .pi), phase2: rand(0, 2 * .pi), phase3: rand(0, 2 * .pi),
                    gain: 0, target: 1.0 / Double(count),
                    gL0: l0, gR0: r0, gL1: l1, gR1: r1, gL2: l2, gR2: r2))
            }
            if padVoices.count > 15 { padVoices.removeFirst(padVoices.count - 15) }

            // Glide the bass to the new chord root one octave down, and the sub
            // an octave below that for body.
            bassTargetFreq = Pitch.frequency(midi: Double((notes.first ?? p.rootMidi) - 12))
            subTargetFreq = Pitch.frequency(midi: Double((notes.first ?? p.rootMidi) - 24))
            if bassFreq == 0 { bassFreq = bassTargetFreq }
            if subFreq == 0 { subFreq = subTargetFreq }
        }
    }

    /// Stereo ensemble pad: three detuned oscillators per chord tone, each panned
    /// to its own place, through a slowly-moving per-channel low-pass so the
    /// timbre breathes.
    private func renderPad(p: MusicParams, dt: Double) -> (Double, Double) {
        // Slow cutoff LFO (~0.05 Hz) so the pad opens and closes over ~20 s.
        padFilterLfo += dt * 0.05
        if padFilterLfo > 1 { padFilterLfo -= 1 }
        let cut = 0.12 + 0.06 * (0.5 + 0.5 * sin(2 * .pi * padFilterLfo))

        let d1 = 1.004, d2 = 0.996        // ensemble detune
        var l = 0.0, r = 0.0
        for i in padVoices.indices {
            padVoices[i].gain += (padVoices[i].target - padVoices[i].gain) * 0.0006   // slow crossfade
            let g = padVoices[i].gain
            if g < 0.0002 { continue }
            let w = 2 * .pi * padVoices[i].freq * dt
            padVoices[i].phase  += w
            padVoices[i].phase2 += w * d1
            padVoices[i].phase3 += w * d2
            if padVoices[i].phase  > 2 * .pi { padVoices[i].phase  -= 2 * .pi }
            if padVoices[i].phase2 > 2 * .pi { padVoices[i].phase2 -= 2 * .pi }
            if padVoices[i].phase3 > 2 * .pi { padVoices[i].phase3 -= 2 * .pi }
            let o0 = sin(padVoices[i].phase)  * g
            let o1 = sin(padVoices[i].phase2) * g * 0.7
            let o2 = sin(padVoices[i].phase3) * g * 0.7
            l += o0 * padVoices[i].gL0 + o1 * padVoices[i].gL1 + o2 * padVoices[i].gL2
            r += o0 * padVoices[i].gR0 + o1 * padVoices[i].gR1 + o2 * padVoices[i].gR2
        }
        padVoices.removeAll { $0.target == 0 && $0.gain < 0.0003 }

        // Per-channel moving low-pass for a warm, breathing pad.
        padLpL += (l - padLpL) * cut
        padLpR += (r - padLpR) * cut
        return (padLpL * 0.42, padLpR * 0.42)
    }

    private func renderBass(p: MusicParams, dt: Double) -> Double {
        if bassTargetFreq > 0 { bassFreq += (bassTargetFreq - bassFreq) * 0.0009 }    // glide
        if subTargetFreq > 0 { subFreq += (subTargetFreq - subFreq) * 0.0009 }
        guard bassFreq > 0 else { return 0 }
        bassPhase += 2 * .pi * bassFreq * dt
        if bassPhase > 2 * .pi { bassPhase -= 2 * .pi }
        var s = (sin(bassPhase) + 0.18 * sin(bassPhase * 2)) * 0.45
        // Sub-octave sine for felt body underneath.
        if subFreq > 0 {
            subPhase += 2 * .pi * subFreq * dt
            if subPhase > 2 * .pi { subPhase -= 2 * .pi }
            s += sin(subPhase) * 0.28
        }
        return s
    }

    private func renderMelody(p: MusicParams, dt: Double) -> Double {
        // Schedule plucks from the density (notes/min → mean seconds between).
        melodyTimer -= dt
        if melodyTimer <= 0 {
            let mean = 60.0 / max(1.0, p.noteDensity)
            // Jitter and rests tighten with complexity: at the low end phrases are
            // loose and sparse; at the top they flow nearly continuously.
            let cx = p.melodyRange
            melodyTimer = mean * rand(0.6 + 0.25 * cx, 1.7 - 0.55 * cx)
            let playProb = 0.70 + 0.28 * cx                 // ~0.98 at full complexity
            if p.melodyGain > 0.03, nextRandom() < playProb {
                // Pick a scale tone near the current chord. `melodyRange` widens
                // both the interval leap and the register the higher complexity.
                let maxLeap = 2.0 + 4.0 * p.melodyRange                 // 2…6 scale steps
                let degree = chordRootIndex + Int(rand(0, maxLeap).rounded())
                let octave = (p.melodyRange > 0.5 && nextRandom() < 0.45) ? 24 : 12
                let midi = p.scale.midi(rootMidi: p.rootMidi + octave, index: degree)
                plucks.append(Pluck(freq: Pitch.frequency(midi: Double(midi)),
                                    phase: 0, env: 1, decay: rand(1.0, 2.2), age: 0))
                if plucks.count > 8 { plucks.removeFirst() }
            }
        }
        var s = 0.0
        for i in plucks.indices {
            let ph = plucks[i].phase
            let e = plucks[i].env
            // Rounder, electric-piano / pizzicato timbre: a strong fundamental and
            // a soft hollow 2nd, with almost no *sustained* upper harmonics. The
            // only brightness is a short bell/"tine" partial that decays very fast
            // (∝ e⁶) — the electric-piano bark on the attack — so the note is warm
            // and dark as it rings rather than glassy. A ~9 ms attack rounds the
            // onset.
            let e2 = e * e
            let e6 = e2 * e2 * e2
            var v  = sin(ph)            * e
            v     += sin(ph * 2) * 0.24 * e2          // hollow body
            v     += sin(ph * 3) * 0.06 * e2 * e      // a whisper of 3rd
            v     += sin(ph * 5) * 0.18 * e6          // bell/tine, attack only
            let attack = min(1.0, plucks[i].age / 0.009)
            s += v * attack
            plucks[i].phase += 2 * .pi * plucks[i].freq * dt
            plucks[i].age += dt
            plucks[i].env *= pow(0.5, dt / plucks[i].decay)
        }
        plucks.removeAll { $0.env < 0.001 }
        // A gentle low-pass takes the high frequencies off the whole melody voice
        // so it sits rounder in the mix (≈ 2 kHz one-pole). The reverb tail then
        // adds the air back without the edge.
        melLp += (tanh(s) * 0.5 - melLp) * 0.30
        return melLp
    }

    /// A sparse, high "celesta" second voice — a soft bell that answers the
    /// melody a couple of octaves up, only when there's real melodic activity. It
    /// shares the melody's stereo space (echo + reverb + shimmer), so it sparkles
    /// wide and high above the pads without cluttering the centre.
    private func renderCelesta(p: MusicParams, dt: Double) -> Double {
        celestaTimer -= dt
        if celestaTimer <= 0 {
            // Fires ~4× less often than the melody, and only with enough activity.
            let mean = 4.0 * 60.0 / max(1.0, p.noteDensity)
            celestaTimer = mean * rand(0.7, 1.6)
            if p.melodyGain > 0.10, p.melodyRange > 0.35, nextRandom() < 0.5 {
                let degree = chordRootIndex + Int(rand(0, 3).rounded())
                let midi = p.scale.midi(rootMidi: p.rootMidi + 36, index: degree)   // high
                celesta.append(Pluck(freq: Pitch.frequency(midi: Double(midi)),
                                     phase: 0, env: 1, decay: rand(1.4, 2.6), age: 0))
                if celesta.count > 4 { celesta.removeFirst() }
            }
        }
        var s = 0.0
        for i in celesta.indices {
            let ph = celesta[i].phase
            let e = celesta[i].env
            let e3 = e * e * e
            // Bell-ish: fundamental + a soft 3rd harmonic that decays faster.
            let v = (sin(ph) * e + sin(ph * 3) * 0.14 * e3)
            let attack = min(1.0, celesta[i].age / 0.006)
            s += v * attack
            celesta[i].phase += 2 * .pi * celesta[i].freq * dt
            celesta[i].age += dt
            celesta[i].env *= pow(0.5, dt / celesta[i].decay)
        }
        celesta.removeAll { $0.env < 0.001 }
        return tanh(s) * 0.22    // sits quiet, a sparkle not a lead
    }
}
