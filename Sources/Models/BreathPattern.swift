import Foundation

/// A single phase within a breathing cycle.
public enum BreathPhase: String, Sendable, CaseIterable {
    case inhale
    case holdIn   // hold after inhaling (lungs full)
    case exhale
    case holdOut  // hold after exhaling (lungs empty)

    public var fr: String {
        switch self {
        case .inhale:  return "Inspire"
        case .holdIn:  return "Retiens"
        case .exhale:  return "Expire"
        case .holdOut: return "Pause"
        }
    }
    public var en: String {
        switch self {
        case .inhale:  return "Breathe in"
        case .holdIn:  return "Hold"
        case .exhale:  return "Breathe out"
        case .holdOut: return "Pause"
        }
    }

    /// Target scale of the breathing orb at the END of this phase.
    /// Inhale grows to 1.0, exhale shrinks to the floor; holds keep their level.
    public var targetScale: Double {
        switch self {
        case .inhale:  return 1.0
        case .holdIn:  return 1.0
        case .exhale:  return Self.exhaleFloor
        case .holdOut: return Self.exhaleFloor
        }
    }
    static let exhaleFloor = 0.45
}

/// A wind-down breathing pattern: an ordered list of (phase, seconds).
/// Built so the pacing math is fully testable without any UI/animation.
public struct BreathPattern: Identifiable, Sendable, Equatable {
    public let id: String
    public let nameFR: String
    public let nameEN: String
    public let descFR: String
    public let descEN: String
    /// Ordered phases with their durations in seconds.
    public let steps: [(phase: BreathPhase, seconds: Double)]

    public init(id: String, nameFR: String, nameEN: String,
                descFR: String, descEN: String,
                steps: [(BreathPhase, Double)]) {
        self.id = id
        self.nameFR = nameFR
        self.nameEN = nameEN
        self.descFR = descFR
        self.descEN = descEN
        self.steps = steps.map { (phase: $0.0, seconds: $0.1) }
    }

    public static func == (lhs: BreathPattern, rhs: BreathPattern) -> Bool {
        lhs.id == rhs.id
    }

    /// Total duration of one full cycle, in seconds.
    public var cycleDuration: Double { steps.reduce(0) { $0 + $1.seconds } }

    /// Phases that have a non-zero duration (drop empty holds for display).
    public var activeSteps: [(phase: BreathPhase, seconds: Double)] {
        steps.filter { $0.seconds > 0.0001 }
    }

    /// Resolve a position within the cycle (seconds since cycle start, wrapped)
    /// into the current phase, the elapsed time *within* that phase, and the
    /// interpolation progress 0…1 through that phase.
    public func resolve(at secondsIntoCycle: Double) -> (phase: BreathPhase, phaseElapsed: Double, phaseProgress: Double, phaseDuration: Double) {
        let cycle = cycleDuration
        guard cycle > 0 else {
            return (.inhale, 0, 0, 0)
        }
        // Wrap into [0, cycle).
        var pos = secondsIntoCycle.truncatingRemainder(dividingBy: cycle)
        if pos < 0 { pos += cycle }

        var acc = 0.0
        for step in steps where step.seconds > 0 {
            if pos < acc + step.seconds {
                let elapsed = pos - acc
                let progress = step.seconds > 0 ? min(1, max(0, elapsed / step.seconds)) : 1
                return (step.phase, elapsed, progress, step.seconds)
            }
            acc += step.seconds
        }
        // Floating-point edge: land on the last active step.
        if let last = steps.last(where: { $0.seconds > 0 }) {
            return (last.phase, last.seconds, 1, last.seconds)
        }
        return (.inhale, 0, 0, 0)
    }

    /// The orb scale (0.45…1.0) at a position in the cycle, smoothly
    /// interpolated across the active phase with an ease-in-out curve so the
    /// motion feels like breath, not a metronome.
    public func orbScale(at secondsIntoCycle: Double) -> Double {
        let r = resolve(at: secondsIntoCycle)
        let from = startScale(of: r.phase)
        let to = r.phase.targetScale
        let eased = Self.easeInOut(r.phaseProgress)
        return from + (to - from) * eased
    }

    /// The scale the orb is at when a given phase BEGINS — i.e. the target of
    /// the previous active phase.
    func startScale(of phase: BreathPhase) -> Double {
        let active = steps.filter { $0.seconds > 0 }
        guard let idx = active.firstIndex(where: { $0.phase == phase }) else {
            return BreathPhase.exhaleFloor
        }
        let prevIdx = (idx - 1 + active.count) % active.count
        return active[prevIdx].phase.targetScale
    }

    /// Cosine ease-in-out on [0,1].
    public static func easeInOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 0.5 - 0.5 * cos(.pi * c)
    }

    // MARK: - Built-in patterns

    public static let fourSevenEight = BreathPattern(
        id: "478",
        nameFR: "4-7-8", nameEN: "4-7-8",
        descFR: "Le souffle du Dr Weil : inspire 4, retiens 7, expire 8. Le plus efficace pour s'endormir.",
        descEN: "Dr Weil's breath: in for 4, hold 7, out for 8. The most effective for falling asleep.",
        steps: [(.inhale, 4), (.holdIn, 7), (.exhale, 8), (.holdOut, 0)]
    )

    public static let box = BreathPattern(
        id: "box",
        nameFR: "Carré", nameEN: "Box",
        descFR: "Respiration carrée : 4 temps égaux. Calme et régulier comme la marée.",
        descEN: "Box breathing: four equal counts. Calm and even, like the tide.",
        steps: [(.inhale, 4), (.holdIn, 4), (.exhale, 4), (.holdOut, 4)]
    )

    public static let coherent = BreathPattern(
        id: "coherent",
        nameFR: "Cohérence 5,5", nameEN: "Coherent 5.5",
        descFR: "Cohérence cardiaque : inspire 5,5, expire 5,5. Cinq respirations par minute.",
        descEN: "Heart coherence: in 5.5, out 5.5. Five and a half breaths a minute.",
        steps: [(.inhale, 5.5), (.holdIn, 0), (.exhale, 5.5), (.holdOut, 0)]
    )

    public static let physiologicalSigh = BreathPattern(
        id: "sigh",
        nameFR: "Soupir physiologique", nameEN: "Physiological sigh",
        descFR: "Deux inspirations courtes, une longue expiration. Vide le stress d'un coup.",
        descEN: "A double inhale, then a long slow exhale. Sheds stress fast.",
        // Approximated as: inhale, a brief top-up hold, then a long exhale.
        steps: [(.inhale, 2), (.holdIn, 1), (.exhale, 6), (.holdOut, 1)]
    )

    public static let all: [BreathPattern] = [
        fourSevenEight, box, coherent, physiologicalSigh,
    ]

    public static func by(id: String) -> BreathPattern {
        all.first { $0.id == id } ?? fourSevenEight
    }
}
