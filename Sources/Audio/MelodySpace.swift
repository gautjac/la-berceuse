import Foundation

/// Procedural **stereo** space for the generative melody — still no audio files,
/// just classic feedback DSP. A ping-pong delay bounces the plucks across the
/// field, a stereo, gently-modulated Freeverb-style reverb wraps them in a wide
/// tail (the modulation keeps the tail from ringing metallic), and an optional
/// octave-up *shimmer* feeds a sheen back into the reverb — the Eno/ambient glow.
///
/// Everything pre-allocates on `init`, so the audio render thread never
/// allocates. All types are `internal` so the tests can drive the DSP directly.

/// A fixed-size delay line (circular buffer), with fractional read for the
/// modulated/pitched taps.
final class DelayLine {
    private var buf: [Double]
    private var idx = 0
    let size: Int

    init(maxSamples: Int) {
        size = max(1, maxSamples)
        buf = [Double](repeating: 0, count: size)
    }

    /// The sample written `delay` frames ago (integer).
    @inline(__always) func tap(_ delay: Int) -> Double {
        var i = idx - min(size - 1, max(0, delay))
        if i < 0 { i += size }
        return buf[i]
    }

    /// Linear-interpolated fractional tap — for modulated / pitch-shifted reads.
    @inline(__always) func tapInterpolated(_ delay: Double) -> Double {
        let d = min(Double(size - 1), max(0, delay))
        let i0 = Int(d)
        let frac = d - Double(i0)
        let a = tap(i0)
        let b = tap(i0 + 1)
        return a + (b - a) * frac
    }

    @inline(__always) func push(_ x: Double) {
        buf[idx] = x
        idx += 1
        if idx >= size { idx = 0 }
    }
}

/// A stereo ping-pong echo: each channel's output feeds the *other* channel's
/// input, so repeats bounce L → R → L and spread wide.
final class PingPong {
    private let lineL: DelayLine
    private let lineR: DelayLine
    let delay: Int
    var feedback: Double

    init(delaySamples: Int, feedback: Double) {
        delay = max(1, delaySamples)
        self.feedback = feedback
        lineL = DelayLine(maxSamples: delay + 1)
        lineR = DelayLine(maxSamples: delay + 1)
    }

    /// Returns the wet (echoing) L/R signals for a mono input.
    @inline(__always) func process(_ x: Double) -> (Double, Double) {
        let l = lineL.tap(delay)
        let r = lineR.tap(delay)
        lineL.push(x * 0.5 + r * feedback)   // R bounces into L
        lineR.push(x * 0.5 + l * feedback)   // L bounces into R
        return (l, r)
    }
}

/// A damped feedback comb whose delay is slowly *modulated* (fractional read),
/// so the reverb tail shimmers instead of ringing metallic.
final class ModComb {
    private let line: DelayLine
    let baseDelay: Double
    let modDepth: Double
    var feedback: Double
    var damp: Double
    private var store = 0.0

    init(delay: Int, feedback: Double, damp: Double, modDepth: Double) {
        baseDelay = Double(max(1, delay))
        self.modDepth = modDepth
        self.feedback = feedback
        self.damp = damp
        line = DelayLine(maxSamples: delay + Int(modDepth) + 4)
    }

    @inline(__always) func process(_ x: Double, mod: Double) -> Double {
        let y = line.tapInterpolated(baseDelay + mod * modDepth)
        store = y * (1 - damp) + store * damp
        line.push(x + store * feedback)
        return y
    }
}

/// An all-pass filter — thickens the tail without colouring pitch.
final class Allpass {
    private let line: DelayLine
    let delay: Int
    let g: Double

    init(delay: Int, g: Double = 0.5) {
        self.delay = max(1, delay)
        self.g = g
        line = DelayLine(maxSamples: self.delay + 1)
    }

    @inline(__always) func process(_ x: Double) -> Double {
        let buffered = line.tap(delay)
        let y = -x + buffered
        line.push(x + buffered * g)
        return y
    }
}

/// A stereo reverb: four modulated combs → two all-passes per channel. The two
/// channels use slightly different delay tunings and opposite modulation so the
/// tail decorrelates and wraps around the listener.
final class StereoReverb {
    private let combsL: [ModComb]
    private let combsR: [ModComb]
    private let apL: [Allpass]
    private let apR: [Allpass]

    init(sampleRate: Double, feedback: Double = 0.82, damp: Double = 0.4) {
        let scale = sampleRate / 44_100.0
        func s(_ n: Int, _ k: Double = 1) -> Int { max(1, Int(Double(n) * scale * k)) }
        let md = max(2.0, 6.0 * scale)     // ±6-sample delay modulation
        combsL = [1116, 1188, 1277, 1356].map { ModComb(delay: s($0), feedback: feedback, damp: damp, modDepth: md) }
        combsR = [1116, 1188, 1277, 1356].map { ModComb(delay: s($0, 1.017), feedback: feedback, damp: damp, modDepth: md) }
        apL = [556, 441].map { Allpass(delay: s($0)) }
        apR = [556, 441].map { Allpass(delay: s($0, 1.017)) }
    }

    func setFeedback(_ fb: Double) {
        let f = min(0.9, max(0, fb))
        for c in combsL { c.feedback = f }
        for c in combsR { c.feedback = f }
    }

    /// `mod` is a slow −1…1 LFO; the two channels get opposite modulation.
    @inline(__always) func process(_ l: Double, _ r: Double, mod: Double) -> (Double, Double) {
        let il = l * 0.25, ir = r * 0.25
        var yl = 0.0; for c in combsL { yl += c.process(il, mod: mod) };  yl /= 4
        var yr = 0.0; for c in combsR { yr += c.process(ir, mod: -mod) }; yr /= 4
        for a in apL { yl = a.process(yl) }
        for a in apR { yr = a.process(yr) }
        return (yl, yr)
    }
}

/// A compact delay-line pitch shifter tuned to **+1 octave**, for the reverb
/// shimmer. Two windowed read taps (offset by half a window) crossfade so there
/// is no click when the faster-moving read pointer laps the write pointer.
final class OctaveUp {
    private let line: DelayLine
    private let window: Double
    private var phase = 0.0

    init(sampleRate: Double) {
        window = max(256, sampleRate * 0.045)      // ~45 ms grain
        line = DelayLine(maxSamples: Int(window * 2) + 8)
    }

    @inline(__always) func process(_ x: Double) -> Double {
        line.push(x)
        phase += 1.0 / window
        if phase >= 1 { phase -= 1 }
        let p2 = phase >= 0.5 ? phase - 0.5 : phase + 0.5
        // Delay ramps window→0 so the read pointer advances at 2× → up an octave.
        let d1 = (1 - phase) * window
        let d2 = (1 - p2) * window
        let g1 = sin(.pi * phase)                  // Hann-ish crossfade windows
        let g2 = sin(.pi * p2)
        return line.tapInterpolated(d1) * g1 + line.tapInterpolated(d2) * g2
    }
}

/// The melody's stereo space: ping-pong echo + modulated stereo reverb + shimmer.
final class StereoSpace {
    private let sampleRate: Double
    private let pingpong: PingPong
    private let reverb: StereoReverb
    private let shimmer: OctaveUp
    private var lfoPhase = 0.0
    private var shimFeedback = 0.0

    // Mix levels — the melody keeps a steady dry presence; echo/reverb/shimmer
    // wet amounts are driven live by the Écho / Réverbération controls.
    var dryLevel = 0.6
    var echoLevel = 0.30
    var reverbLevel = 0.45
    var shimmerAmount = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        pingpong = PingPong(delaySamples: Int(sampleRate * 0.33), feedback: 0.42)
        reverb = StereoReverb(sampleRate: sampleRate)
        shimmer = OctaveUp(sampleRate: sampleRate)
    }

    /// Apply the user's Écho / Réverbération settings (per audio block, no race).
    @inline(__always) func apply(echoWet: Double, echoFeedback: Double,
                                 reverbWet: Double, reverbFeedback: Double) {
        echoLevel = echoWet
        pingpong.feedback = min(0.6, max(0, echoFeedback))
        reverbLevel = reverbWet
        reverb.setFeedback(reverbFeedback)
        shimmerAmount = reverbWet * 0.45          // more reverb → more sheen
    }

    /// Back a mono dry melody sample up into a wide stereo space.
    @inline(__always) func process(_ dry: Double) -> (Double, Double) {
        let (eL, eR) = pingpong.process(dry)
        lfoPhase += 0.35 / sampleRate             // ~0.35 Hz tail modulation
        if lfoPhase >= 1 { lfoPhase -= 1 }
        let m = sin(2 * .pi * lfoPhase)
        let inL = dry * 0.7 + eL * 0.8 + shimFeedback
        let inR = dry * 0.7 + eR * 0.8 + shimFeedback
        var (rL, rR) = reverb.process(inL, inR, mod: m)
        // Shimmer: octave-up of the reverb sum, fed back a touch for the glow.
        let shim = shimmer.process((rL + rR) * 0.5)
        shimFeedback = shimmerAmount > 0 ? shim * 0.28 : 0
        rL += shim * shimmerAmount
        rR += shim * shimmerAmount
        let outL = dry * dryLevel + eL * echoLevel + rL * reverbLevel
        let outR = dry * dryLevel + eR * echoLevel + rR * reverbLevel
        return (outL, outR)
    }
}
