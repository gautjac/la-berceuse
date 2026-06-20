import Foundation

/// The procedural sound layers La Berceuse can mix. Each is synthesized live by
/// `SoundEngine` (no audio files), so all are audible in the simulator.
public enum SoundLayer: String, CaseIterable, Identifiable, Sendable {
    case rain
    case wind
    case brownNoise
    case pinkNoise
    case drone
    case waves
    case musicBox

    public var id: String { rawValue }

    public var nameFR: String {
        switch self {
        case .rain:       return "Pluie"
        case .wind:       return "Vent"
        case .brownNoise: return "Bruit brun"
        case .pinkNoise:  return "Bruit rose"
        case .drone:      return "Bourdon chaud"
        case .waves:      return "Vagues lointaines"
        case .musicBox:   return "Boîte à musique"
        }
    }
    public var nameEN: String {
        switch self {
        case .rain:       return "Rain"
        case .wind:       return "Wind"
        case .brownNoise: return "Brown noise"
        case .pinkNoise:  return "Pink noise"
        case .drone:      return "Warm drone"
        case .waves:      return "Distant waves"
        case .musicBox:   return "Music box"
        }
    }

    public var symbol: String {
        switch self {
        case .rain:       return "cloud.rain"
        case .wind:       return "wind"
        case .brownNoise: return "waveform.path"
        case .pinkNoise:  return "waveform"
        case .drone:      return "dot.radiowaves.left.and.right"
        case .waves:      return "water.waves"
        case .musicBox:   return "music.note"
        }
    }
}

/// Pure value math for the sleep timer's fade-to-silence. Kept free of any
/// AVFoundation so it is fully unit-testable.
public enum FadeMath {
    /// Multiplier (0…1) applied to every layer's volume during the final fade.
    ///
    /// While `remaining > fadeDuration`, the multiplier is 1 (full volume).
    /// Within the last `fadeDuration` seconds it eases smoothly to 0 using an
    /// equal-power (cosine) curve, which sounds linear to the ear and avoids an
    /// abrupt drop that would jolt a sleeper.
    public static func multiplier(remaining: Double, fadeDuration: Double) -> Double {
        guard fadeDuration > 0 else { return remaining > 0 ? 1 : 0 }
        if remaining <= 0 { return 0 }
        if remaining >= fadeDuration { return 1 }
        let x = remaining / fadeDuration            // 1 → 0 across the fade
        // Equal-power: cos(π/2 · (1−x)) → starts at 1, ends at 0, smooth.
        return cos((.pi / 2) * (1 - x))
    }

    /// Whether the engine should be fully stopped (silence reached).
    public static func isSilent(remaining: Double) -> Bool { remaining <= 0 }
}

/// The sleep-timer state machine in pure values, so the countdown + fade
/// transitions can be tested deterministically.
public struct SleepTimer: Equatable, Sendable {
    /// Total duration in seconds (0 = off / no timer).
    public var total: Double
    /// How long the closing fade lasts (capped to the total).
    public var fade: Double
    /// Seconds elapsed since the timer started.
    public var elapsed: Double

    public init(total: Double, fade: Double = 60, elapsed: Double = 0) {
        self.total = total
        self.fade = min(fade, total)
        self.elapsed = elapsed
    }

    public var isActive: Bool { total > 0 }
    public var remaining: Double { max(0, total - elapsed) }
    public var isFinished: Bool { isActive && remaining <= 0 }
    public var isFading: Bool { isActive && remaining > 0 && remaining <= fade }

    /// Current volume multiplier for the whole mix.
    public var volumeMultiplier: Double {
        guard isActive else { return 1 }
        return FadeMath.multiplier(remaining: remaining, fadeDuration: fade)
    }

    /// Advance the timer by `dt` seconds (returns a new value).
    public func advanced(by dt: Double) -> SleepTimer {
        var copy = self
        copy.elapsed = min(total, elapsed + max(0, dt))
        return copy
    }

    /// Human-readable remaining time, mm:ss.
    public var clockString: String {
        let r = Int(remaining.rounded())
        return String(format: "%d:%02d", r / 60, r % 60)
    }

    /// The standard timer presets, in minutes (plus "off").
    public static let presetMinutes: [Int] = [15, 30, 45, 60, 90]
}
