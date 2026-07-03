import Foundation

/// La Berceuse's generative-music model — pure value types with NO AVFoundation,
/// so every musical and signal-shaping decision is deterministic and unit
/// testable (the same discipline as `FadeMath` / `SleepTimer`).
///
/// The audio thread (`GenerativeMusicNode`) reads a `MusicParams` snapshot and a
/// `MusicProgram`'s scale/progression rules from here; it never calls back into
/// the main actor. Nothing in this file is actor-isolated, so the realtime
/// render thread can call these functions safely.
///
/// Design, grounded in the two reference apps:
///   • brain.fm  → a gentle *amplitude modulation* applied to the music bus
///                 (`AModMath`). For La Berceuse the pulse is deliberately slow
///                 and **breath-synced**, so it reads as a swell, not a throb.
///   • Endel     → *adaptive, endless generative* composition. `MusicDirector`
///                 maps fully-offline context (time of night, the active breath
///                 pattern, the sleep-timer arc, optional heart rate) onto the
///                 engine's parameters, and the music **de-energizes** across a
///                 session — fewer notes, lower register, darker, slower.

// MARK: - Pitch helpers

public enum Pitch {
    /// Equal-temperament MIDI note → frequency in Hz (A4 = 69 = 440 Hz).
    public static func frequency(midi: Double) -> Double {
        440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }
}

// MARK: - Scales

/// A consonant scale, chosen so generated notes never collide — pentatonics have
/// no semitone clashes at all; Lydian/Dorian add gentle colour without a
/// tension-laden leading tone.
public enum MusicScale: String, Sendable, CaseIterable {
    case pentatonicMajor
    case pentatonicMinor
    case lydian
    case dorian

    /// Semitone offsets of each degree from the root, within one octave.
    public var degrees: [Int] {
        switch self {
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .lydian:          return [0, 2, 4, 6, 7, 9, 11]
        case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
        }
    }

    public var count: Int { degrees.count }

    /// MIDI note for a scale *index* that may run past one octave (it wraps up
    /// in octaves), measured from `rootMidi`.
    public func midi(rootMidi: Int, index: Int) -> Int {
        let n = count
        // Floor-division so negative indices descend cleanly.
        let octave = Int(floor(Double(index) / Double(n)))
        let within = index - octave * n
        return rootMidi + degrees[within] + 12 * octave
    }
}

// MARK: - Chords

/// A pad chord expressed as scale *indices* relative to the key, so it can never
/// leave the scale. A simple stacked-thirds-within-the-scale voicing.
public struct PadChord: Equatable, Sendable {
    /// Root as a scale index (0 = tonic). May be negative / >count (wraps).
    public let rootIndex: Int
    /// Which scale steps above the root to stack (e.g. [0, 2, 4] ≈ a triad).
    public let stack: [Int]

    public init(rootIndex: Int, stack: [Int] = [0, 2, 4]) {
        self.rootIndex = rootIndex
        self.stack = stack
    }

    /// The chord's MIDI notes in a given key/scale.
    public func midiNotes(rootMidi: Int, scale: MusicScale) -> [Int] {
        stack.map { scale.midi(rootMidi: rootMidi, index: rootIndex + $0) }
    }
}

/// A gentle harmonic walk. Rather than a fixed loop, it steps between a small
/// pool of allowed chord roots with a strong bias toward *small* movement and an
/// occasional pull home to the tonic — endless but always resolved, never jarring.
public struct ChordProgression: Sendable {
    /// Allowed chord roots, as scale indices (tonic, plus a few diatonic colours).
    public let allowedRoots: [Int]
    /// Largest step (in scale indices) a single chord change may move — caps any
    /// jarring leap and is what the voice-leading test asserts.
    public let maxStep: Int

    public init(allowedRoots: [Int] = [0, 3, 4, 1, 5], maxStep: Int = 2) {
        self.allowedRoots = allowedRoots
        self.maxStep = maxStep
    }

    /// The next chord root given the current one. Pure: the same `current` and
    /// RNG draw always yields the same result. Guarantees `|next − current|`
    /// (compared by the roots' *values*) is ≤ `maxStep` and stays in the pool.
    public func nextRoot<R: RandomNumberGenerator>(current: Int, using rng: inout R) -> Int {
        // Candidate roots within reach of the current one.
        let near = allowedRoots.filter { abs($0 - current) <= maxStep }
        let pool = near.isEmpty ? allowedRoots : near
        // Bias: ~35% pull toward the tonic (0) when it is reachable; otherwise a
        // soft random step among the near candidates.
        if pool.contains(0), Double.random(in: 0...1, using: &rng) < 0.35 {
            return 0
        }
        return pool.randomElement(using: &rng) ?? 0
    }
}

// MARK: - Programs

/// The three generative programs the listener can pick. Each is a *starting
/// point*; `MusicDirector` then bends it with live context.
public enum MusicProgram: String, Sendable, CaseIterable, Identifiable {
    case sommeil   // sleep — lowest, sparsest, slowest pulse
    case detente   // relax — warmer, a little more present
    case souffle   // breath-synced — pulse and pads ride the active breath pattern

    public var id: String { rawValue }

    public var nameFR: String {
        switch self {
        case .sommeil: return "Sommeil"
        case .detente: return "Détente"
        case .souffle: return "Souffle"
        }
    }
    public var nameEN: String {
        switch self {
        case .sommeil: return "Sleep"
        case .detente: return "Relax"
        case .souffle: return "Breath"
        }
    }
    public var descFR: String {
        switch self {
        case .sommeil: return "Le plus bas, le plus rare. S'éteint avec la minuterie."
        case .detente: return "Chaud et présent, pour relâcher avant le sommeil."
        case .souffle: return "Les nappes ondulent au rythme de ton souffle."
        }
    }
    public var descEN: String {
        switch self {
        case .sommeil: return "Lowest, sparsest. Winds down with the sleep timer."
        case .detente: return "Warm and present, to unwind before sleep."
        case .souffle: return "The pads swell in time with your breathing."
        }
    }
    public var symbol: String {
        switch self {
        case .sommeil: return "moon.zzz"
        case .detente: return "leaf"
        case .souffle: return "wind"
        }
    }

    /// The musical "soil" each program grows from.
    public var scale: MusicScale {
        switch self {
        case .sommeil: return .pentatonicMinor
        case .detente: return .pentatonicMajor
        case .souffle: return .lydian
        }
    }

    /// Tonic MIDI note. Sleep sits a third lower than relax for a darker, more
    /// felt-than-heard bed. (C3 = 48.)
    public var rootMidi: Int {
        switch self {
        case .sommeil: return 48
        case .detente: return 51
        case .souffle: return 50
        }
    }

    /// Full-energy melody note density (notes per minute) and harmonic rhythm
    /// (seconds per chord) before the director scales them down. These are the
    /// *top* of the Complexité range — at full complexity the melody flows almost
    /// continuously; the director thins it dramatically toward zero.
    public var baseDensity: Double {
        switch self {
        case .sommeil: return 14
        case .detente: return 26
        case .souffle: return 20
        }
    }
    public var baseChordSeconds: Double {
        switch self {
        case .sommeil: return 22
        case .detente: return 14
        case .souffle: return 16
        }
    }
    /// Base amplitude-modulation depth (0…1) before the user's Pulsation slider.
    public var baseModDepth: Double {
        switch self {
        case .sommeil: return 0.22
        case .detente: return 0.16
        case .souffle: return 0.26
        }
    }
}

// MARK: - Parameters the audio thread consumes

/// A flat, realtime-safe snapshot of everything the synth needs. Produced by
/// `MusicDirector`, copied into the node's parameter store, read per block.
public struct MusicParams: Equatable, Sendable {
    public var scale: MusicScale
    public var rootMidi: Int            // already includes any register shift
    public var padGain: Double          // 0…1
    public var bassGain: Double         // 0…1
    public var melodyGain: Double       // 0…1
    public var chordSeconds: Double     // harmonic rhythm
    public var noteDensity: Double      // melody notes per minute
    public var brightness: Double       // 0…1 → low-pass cutoff
    public var modRateHz: Double        // amplitude-modulation rate
    public var modDepth: Double         // 0…~0.35 (kept subtle)
    // Complexity-driven shape (set by the Complexité control via the director):
    public var chordStack: [Int]        // pad voicing as scale-step offsets
    public var progressionRoots: [Int]  // the chord-root pool the walk may visit
    public var progressionMaxStep: Int  // how far a single chord change may move
    public var melodyRange: Double      // 0…1 → how far the melody leaps / spreads
    // Melody "space" (the Écho / Réverbération controls):
    public var echoWet: Double          // 0…~0.55 echo mix level
    public var echoFeedback: Double     // 0.15…0.6 number/length of repeats
    public var reverbWet: Double        // 0…~0.8 reverb mix level
    public var reverbFeedback: Double   // 0.6…0.9 tail length / room size

    public init(scale: MusicScale, rootMidi: Int, padGain: Double, bassGain: Double,
                melodyGain: Double, chordSeconds: Double, noteDensity: Double,
                brightness: Double, modRateHz: Double, modDepth: Double,
                chordStack: [Int] = [0, 2, 4], progressionRoots: [Int] = [0, 3, 4, 1, 5],
                progressionMaxStep: Int = 2, melodyRange: Double = 0.5,
                echoWet: Double = 0.3, echoFeedback: Double = 0.42,
                reverbWet: Double = 0.45, reverbFeedback: Double = 0.82) {
        self.scale = scale
        self.rootMidi = rootMidi
        self.padGain = padGain
        self.bassGain = bassGain
        self.melodyGain = melodyGain
        self.chordSeconds = chordSeconds
        self.noteDensity = noteDensity
        self.brightness = brightness
        self.modRateHz = modRateHz
        self.modDepth = modDepth
        self.chordStack = chordStack
        self.progressionRoots = progressionRoots
        self.progressionMaxStep = progressionMaxStep
        self.melodyRange = melodyRange
        self.echoWet = echoWet
        self.echoFeedback = echoFeedback
        self.reverbWet = reverbWet
        self.reverbFeedback = reverbFeedback
    }

    /// A silent-but-valid default so the node always has something to read.
    public static let silent = MusicParams(
        scale: .pentatonicMinor, rootMidi: 48, padGain: 0, bassGain: 0,
        melodyGain: 0, chordSeconds: 20, noteDensity: 8, brightness: 0.3,
        modRateHz: 0.1, modDepth: 0, chordStack: [0, 2], progressionRoots: [0],
        progressionMaxStep: 1, melodyRange: 0)
}

// MARK: - Context → the director's inputs

/// Everything the director needs to shape the music — all of it available
/// **offline** on the device.
public struct MusicContext: Sendable {
    public var program: MusicProgram
    /// The Intensité slider (0…1): the listener's baseline energy.
    public var userIntensity: Double
    /// The Pulsation slider (0…1): scales the amplitude-modulation depth.
    public var userPulse: Double
    /// The Complexité slider (0…1): how much is going on musically — note
    /// density, how often the harmony moves, voicing richness, melodic range.
    /// Independent of `userIntensity` (which is presence/loudness), so you can
    /// ask for "quiet but rich" or "present but sparse".
    public var userComplexity: Double
    /// How far through the sleep timer we are (0 = just started … 1 = silence).
    /// 0 when no timer is armed. Drives the de-energizing arc.
    public var sessionProgress: Double
    /// Hour of the night, 0…24 (e.g. 23.5). Later → calmer (circadian).
    public var hourOfDay: Double
    /// The active breath pattern's full-cycle period, seconds. The Souffle pulse
    /// and pad swell lock to this.
    public var breathCyclePeriod: Double
    /// Latest heart rate (bpm) from HealthKit, if granted/available.
    public var heartRate: Double?
    /// The Écho slider (0…1): how present and repeating the melody's delay is.
    public var userEcho: Double
    /// The Réverbération slider (0…1): how large and long the melody's tail is.
    public var userReverb: Double

    public init(program: MusicProgram, userIntensity: Double, userPulse: Double,
                userComplexity: Double = 0.5, sessionProgress: Double, hourOfDay: Double,
                breathCyclePeriod: Double, heartRate: Double? = nil,
                userEcho: Double = 0.5, userReverb: Double = 0.6) {
        self.program = program
        self.userIntensity = userIntensity
        self.userPulse = userPulse
        self.userComplexity = userComplexity
        self.userEcho = userEcho
        self.userReverb = userReverb
        self.sessionProgress = sessionProgress
        self.hourOfDay = hourOfDay
        self.breathCyclePeriod = breathCyclePeriod
        self.heartRate = heartRate
    }
}

/// Maps an effective-complexity value (0…1) onto the discrete musical structures
/// the synth consumes — pulled out of the director so it can be unit-tested and
/// reasoned about on its own. Higher → richer voicings, a wider chord pool, and
/// bolder harmonic moves; near 0 → an almost static tonic drone.
public enum MusicComplexity {
    /// Pad voicing (scale-step offsets stacked above the chord root).
    public static func chordStack(_ c: Double) -> [Int] {
        switch c {
        case ..<0.20: return [0, 2]            // open, simple
        case ..<0.55: return [0, 2, 4]         // a triad-on-the-scale
        default:      return [0, 2, 4, 6]      // add a colour tone (7th / 9th)
        }
    }
    /// The chord-root pool the harmonic walk may visit.
    public static func progressionRoots(_ c: Double) -> [Int] {
        switch c {
        case ..<0.20: return [0]               // static tonic
        case ..<0.45: return [0, 3]
        case ..<0.70: return [0, 3, 4]
        default:      return [0, 3, 4, 1, 5]
        }
    }
    /// How far a single chord change may move.
    public static func maxStep(_ c: Double) -> Int { c < 0.45 ? 1 : 2 }
}

// MARK: - The adaptive director (Endel-style, fully offline)

public enum MusicDirector {
    /// Clamp helper.
    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }

    /// A 0…1 "lateness" factor: ~0 in the early evening, rising to 1 deep in the
    /// night (and through the small hours), so the music is calmest at 3 a.m.
    public static func circadianCalm(hourOfDay: Double) -> Double {
        // Map 20:00 → 0, 02:00 → 1, staying high until ~05:00, easing by day.
        let h = hourOfDay.truncatingRemainder(dividingBy: 24)
        switch h {
        case 20...24:   return clamp((h - 20) / 6, 0, 1)          // 20→0 … 24→0.67
        case 0..<5:     return clamp(0.67 + h / 12, 0, 1)         // peaks overnight
        case 5..<9:     return clamp(1 - (h - 5) / 4, 0, 1)       // ease into morning
        default:        return 0                                  // daytime: neutral
        }
    }

    /// The heart of the adaptive engine. Pure: same context → same params.
    public static func params(for ctx: MusicContext) -> MusicParams {
        let prog = ctx.program
        let calm = circadianCalm(hourOfDay: ctx.hourOfDay)

        let session = clamp(ctx.sessionProgress, 0, 1)

        // Two independent axes, both pulled down by lateness and the sleep-timer
        // arc so the music simplifies and recedes as you drift off:
        //   • energy      — presence / loudness / brightness (the Intensité knob)
        //   • complexity  — how much is going on (the Complexité knob)
        // Both are monotonically non-increasing in `sessionProgress` (tested).
        let energy = clamp(clamp(ctx.userIntensity, 0, 1) - 0.20 * calm - 0.45 * session, 0.05, 1)
        let cx = clamp(clamp(ctx.userComplexity, 0, 1) - 0.20 * calm - 0.45 * session, 0, 1)

        // Register: drop an octave when the music is at its quietest, in whole
        // octaves so the key never sounds detuned.
        let registerShift = energy < 0.30 ? -12 : 0

        // Heart-rate nudge (optional). A higher resting HR gets a slightly faster
        // pulse to "meet" the listener; everything still leads downward over the
        // session. Absent HR → no effect.
        let hrFactor: Double = {
            guard let hr = ctx.heartRate, hr > 30, hr < 140 else { return 1.0 }
            // 50 bpm → 0.92, 70 bpm → 1.0, 90 bpm → 1.08 (gentle ±8%).
            return clamp(1.0 + (hr - 70) / 250, 0.9, 1.1)
        }()

        // Amplitude modulation. The pulse is breath-synced: one cycle per breath
        // (Souffle locks hardest to it; Sommeil/Détente ride a slightly slower
        // swell). Kept subtle — depth capped at 0.35.
        let breathHz = ctx.breathCyclePeriod > 0.5 ? 1.0 / ctx.breathCyclePeriod : 0.1
        let modRate: Double = {
            switch prog {
            case .souffle: return breathHz * hrFactor
            default:       return breathHz * 0.85 * hrFactor
            }
        }()
        let modDepth = clamp(prog.baseModDepth * clamp(ctx.userPulse, 0, 1) * (0.7 + 0.3 * energy), 0, 0.35)

        // Activity is driven by COMPLEXITY (with a light energy influence and the
        // HR tempo nudge): more notes, faster harmonic motion as complexity rises.
        // A widened, super-linear curve (cx^1.3 × 2.4) opens a big gap between a
        // near-static low end and a flowing, almost-continuous melody at the top.
        let density = clamp(prog.baseDensity * (0.10 + 2.4 * pow(cx, 1.3)) * (0.6 + 0.4 * energy) * hrFactor, 0, 72)
        let chordSeconds = clamp(prog.baseChordSeconds * (2.3 - 1.5 * cx), 7, 60)

        // Voice balance. The pad/bed is governed by ENERGY (presence); the melody
        // only emerges with COMPLEXITY — so low complexity is a felt-not-heard
        // drone even at full intensity.
        let padGain = clamp(0.50 + 0.20 * energy, 0, 1)
        let bassGain = clamp(0.42 + 0.12 * (1 - energy), 0, 1)   // bass holds as the melody fades
        let melodyGain = clamp(0.78 * cx * (0.45 + 0.55 * energy), 0, 0.85)

        let brightness = clamp(0.16 + 0.50 * energy, 0.1, 0.85)

        // Melody space — the Écho / Réverbération controls map onto wet level and
        // feedback (repeats / tail length).
        let echo = clamp(ctx.userEcho, 0, 1)
        let reverb = clamp(ctx.userReverb, 0, 1)
        let echoWet = echo * 0.55
        let echoFeedback = 0.15 + echo * 0.45             // 0.15…0.60 repeats
        let reverbWet = reverb * 0.78
        let reverbFeedback = 0.66 + reverb * 0.22         // 0.66…0.88 tail length

        return MusicParams(
            scale: prog.scale,
            rootMidi: prog.rootMidi + registerShift,
            padGain: padGain,
            bassGain: bassGain,
            melodyGain: melodyGain,
            chordSeconds: chordSeconds,
            noteDensity: density,
            brightness: brightness,
            modRateHz: modRate,
            modDepth: modDepth,
            chordStack: MusicComplexity.chordStack(cx),
            progressionRoots: MusicComplexity.progressionRoots(cx),
            progressionMaxStep: MusicComplexity.maxStep(cx),
            melodyRange: cx,
            echoWet: echoWet,
            echoFeedback: echoFeedback,
            reverbWet: reverbWet,
            reverbFeedback: reverbFeedback)
    }
}

// MARK: - Amplitude-modulation math (the brain.fm layer)

public enum AModMath {
    /// The instantaneous gain (0…1) applied to the *music* signal in **both
    /// channels** for a given modulation phase (0…1) and depth (0…1).
    ///
    /// A raised cosine that swings between `1 − depth` and `1` — it only ever
    /// *ducks* the music, never boosts it past unity, so the modulation can't
    /// clip. At depth 0 it is a flat 1.0 (no audible effect).
    public static func gain(phase: Double, depth: Double) -> Double {
        let d = min(0.35, max(0, depth))
        // raised cosine: 0.5·(1+cos) ∈ [0,1]; map onto [1−d, 1].
        let raised = 0.5 + 0.5 * cos(2 * .pi * phase)
        return (1 - d) + d * raised
    }
}

// MARK: - Stereo & tone shaping (the "richness" pass)

/// Equal-power stereo panning. `pan` runs −1 (hard left) … 0 (centre) … +1
/// (hard right); the two gains always satisfy l² + r² = 1, so panning a source
/// across the field keeps its perceived loudness constant.
public enum Pan {
    public static func gains(_ pan: Double) -> (l: Double, r: Double) {
        let p = min(1, max(-1, pan))
        let a = (p + 1) * (.pi / 4)          // 0 … π/2
        return (cos(a), sin(a))
    }
}

/// Master-bus tone shaping — pure, so it's unit-testable.
public enum AudioShaping {
    /// Soft saturation (a normalised `tanh`) — adds gentle even/odd harmonics for
    /// analog-style warmth and glue, and soft-clips peaks. Monotonic, passes
    /// through 0, and bounded by `1/tanh(drive)`.
    public static func saturate(_ x: Double, drive: Double) -> Double {
        let d = max(0.0001, drive)
        return tanh(x * d) / tanh(d)
    }
}
