import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Gentle breath-paced haptics. Device-only — guarded so the simulator (and the
/// `Haptics.enabled = false` setting) is a silent no-op.
@MainActor
public enum Haptics {
    public static var enabled = true

    /// A soft tap to mark the start of an inhale.
    public static func inhale() { tap(.soft, intensity: 0.5) }
    /// A barely-there tick at the top of a hold.
    public static func hold() { tap(.rigid, intensity: 0.3) }
    /// A long, soft release for the exhale.
    public static func exhale() { tap(.soft, intensity: 0.7) }

    #if canImport(UIKit)
    private static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard enabled else { return }
        #if !targetEnvironment(simulator)
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred(intensity: intensity)
        #endif
    }
    #else
    private static func tap(_ style: Int, intensity: Double) {}
    #endif
}
