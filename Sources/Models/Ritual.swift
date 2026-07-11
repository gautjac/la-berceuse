import Foundation
import SwiftData

/// Les rituels — chained wind-down sequences ("5 min de souffle → 20 min de
/// repos profond → sons avec minuterie"). The step math is pure value types so
/// sequencing and durations are unit-testable; `SavedRitual` persists a ritual
/// as JSON the same way `SavedMix` stores its volumes.

// MARK: - Steps

public enum RitualStepKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case breath     // detail = BreathPattern id, minutes = duration
    case shuffle    // minutes = duration
    case nidra      // detail = NidraScript id (its own length governs)
    case sounds     // minutes = sleep-timer length (0 = no timer), runs last

    public var id: String { rawValue }

    public var nameFR: String {
        switch self {
        case .breath:  return "Souffle"
        case .shuffle: return "Brouillage"
        case .nidra:   return "Repos profond"
        case .sounds:  return "Sons & musique"
        }
    }
    public var nameEN: String {
        switch self {
        case .breath:  return "Breath"
        case .shuffle: return "Shuffle"
        case .nidra:   return "Deep rest"
        case .sounds:  return "Sounds & music"
        }
    }
    public var symbol: String {
        switch self {
        case .breath:  return "lungs"
        case .shuffle: return "shuffle"
        case .nidra:   return "figure.mind.and.body"
        case .sounds:  return "slider.horizontal.3"
        }
    }
}

public struct RitualStep: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RitualStepKind
    /// breath → BreathPattern id · nidra → NidraScript id · others → "".
    public var detail: String
    /// breath/shuffle → step duration · sounds → sleep-timer minutes (0 = none).
    /// Ignored for nidra (the script's own length governs).
    public var minutes: Double

    public init(id: UUID = UUID(), kind: RitualStepKind, detail: String = "", minutes: Double = 0) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.minutes = minutes
    }

    /// The step's effective duration in seconds (nidra resolves its script).
    public var seconds: Double {
        switch kind {
        case .breath, .shuffle:
            return max(30, minutes * 60)
        case .nidra:
            let script = NidraScript.all.first { $0.id == detail } ?? NidraScript.all[0]
            return Double(script.minutes) * 60
        case .sounds:
            return 0    // hands off to the sleep timer / chevet; not a timed stage
        }
    }
}

// MARK: - Plan

/// An ordered, validated sequence of steps plus naming — everything the player
/// needs, decoupled from persistence.
public struct RitualPlan: Equatable, Sendable {
    public var name: String
    public var steps: [RitualStep]

    public init(name: String, steps: [RitualStep]) {
        self.name = name
        // A `sounds` step always runs last — it hands over to the sleep timer.
        self.steps = steps.sorted { a, b in
            (a.kind == .sounds ? 1 : 0) < (b.kind == .sounds ? 1 : 0)
        }
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Total *guided* duration (excludes the open-ended sounds stage), seconds.
    public var guidedSeconds: Double { steps.reduce(0) { $0 + $1.seconds } }

    /// Human summary, e.g. "Souffle 3 min · Repos 10 min · Sons 45 min".
    public func summary(_ lang: Lang) -> String {
        steps.map { s in
            let name = lang == .fr ? s.kind.nameFR : s.kind.nameEN
            switch s.kind {
            case .nidra:
                let m = Int((s.seconds / 60).rounded())
                return "\(name) \(m) min"
            case .sounds:
                return s.minutes > 0 ? "\(name) \(Int(s.minutes)) min" : name
            default:
                return "\(name) \(Int(s.minutes)) min"
            }
        }.joined(separator: " · ")
    }

    // MARK: Built-in plans

    /// The « Dors » master plan: a short settle-in breath, then sounds + music
    /// with the sleep timer armed — zero decisions, straight to the night.
    public static func dors(breathPatternID: String, timerMinutes: Int) -> RitualPlan {
        RitualPlan(name: "Dors", steps: [
            RitualStep(kind: .breath, detail: breathPatternID, minutes: 3),
            RitualStep(kind: .sounds, minutes: Double(max(0, timerMinutes))),
        ])
    }

    /// The 3 a.m. rescue: two minutes of physiological sighs, then the cognitive
    /// shuffle until sleep takes over. No sounds stage — silence is the goal.
    public static let rescue = RitualPlan(name: "Retour au sommeil", steps: [
        RitualStep(kind: .breath, detail: "sigh", minutes: 2),
        RitualStep(kind: .shuffle, minutes: 10),
    ])

    /// True between 01:00 and 05:00 — the hours when an awake mind needs the
    /// rescue flow, not a menu. Pure so it's testable.
    public static func isRescueHour(_ hour: Int) -> Bool { hour >= 1 && hour < 5 }
}

// MARK: - Persistence

/// A saved ritual the user recalls with one tap (steps stored as JSON, exactly
/// like `SavedMix.volumesData`).
@Model
public final class SavedRitual {
    public var name: String
    public var createdAt: Date
    public var stepsData: Data
    /// The ritual the « Dors » button runs instead of the built-in default.
    public var isDefault: Bool = false

    public init(name: String, steps: [RitualStep], isDefault: Bool = false) {
        self.name = name
        self.createdAt = Date()
        self.stepsData = (try? JSONEncoder().encode(steps)) ?? Data()
        self.isDefault = isDefault
    }

    public var steps: [RitualStep] {
        (try? JSONDecoder().decode([RitualStep].self, from: stepsData)) ?? []
    }

    public var plan: RitualPlan { RitualPlan(name: name, steps: steps) }
}
