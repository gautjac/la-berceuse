import Foundation
import SwiftData

/// A saved soundscape mix the user can recall with one tap. Volumes are stored
/// as a `[layerRawValue: volume]` dictionary encoded to JSON (SwiftData stores
/// it as Data) so the schema stays simple.
@Model
public final class SavedMix {
    public var name: String
    public var createdAt: Date
    /// JSON-encoded `[String: Double]` of layer → volume (0…1).
    public var volumesData: Data

    // Generative-music recall. These are optional / defaulted so adding them is a
    // safe SwiftData lightweight migration for stores created before the engine
    // existed. `musicProgram == nil` means "no generative music in this mix".
    public var musicProgram: String?
    public var musicIntensity: Double = 0.55
    public var musicPulse: Double = 0.5
    public var musicComplexity: Double = 0.5
    public var musicEcho: Double = 0.5
    public var musicReverb: Double = 0.6

    public init(name: String, volumes: [String: Double],
                musicProgram: String? = nil,
                musicIntensity: Double = 0.55,
                musicPulse: Double = 0.5,
                musicComplexity: Double = 0.5,
                musicEcho: Double = 0.5,
                musicReverb: Double = 0.6) {
        self.name = name
        self.createdAt = Date()
        self.volumesData = (try? JSONEncoder().encode(volumes)) ?? Data()
        self.musicProgram = musicProgram
        self.musicIntensity = musicIntensity
        self.musicPulse = musicPulse
        self.musicComplexity = musicComplexity
        self.musicEcho = musicEcho
        self.musicReverb = musicReverb
    }

    public var volumes: [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: volumesData)) ?? [:]
    }
}

/// One completed wind-down ritual, kept for the gentle history list and (when
/// authorized) mirrored to HealthKit as mindful time.
@Model
public final class RitualSession {
    public var kind: String        // "breath" | "shuffle" | "nidra" | "soundscape"
    public var detail: String      // e.g. pattern id / script id
    public var startedAt: Date
    public var duration: Double     // seconds

    public init(kind: String, detail: String, startedAt: Date, duration: Double) {
        self.kind = kind
        self.detail = detail
        self.startedAt = startedAt
        self.duration = duration
    }
}

/// App settings persisted via SwiftData (a single row). Most UI prefs also live
/// in `@AppStorage`, but the default ritual + timer + dim level are kept here so
/// they survive and can be seeded.
@Model
public final class Settings {
    public var defaultBreathPatternID: String
    public var defaultTimerMinutes: Int
    public var dimLevel: Double       // 0 (full true-black, dimmest) … 1 (normal)
    public var autoDim: Bool
    public var hapticsEnabled: Bool
    public var speechEnabled: Bool

    public init(defaultBreathPatternID: String = "478",
                defaultTimerMinutes: Int = 30,
                dimLevel: Double = 0.6,
                autoDim: Bool = true,
                hapticsEnabled: Bool = true,
                speechEnabled: Bool = true) {
        self.defaultBreathPatternID = defaultBreathPatternID
        self.defaultTimerMinutes = defaultTimerMinutes
        self.dimLevel = dimLevel
        self.autoDim = autoDim
        self.hapticsEnabled = hapticsEnabled
        self.speechEnabled = speechEnabled
    }
}
