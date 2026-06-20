import SwiftUI

/// La Berceuse's visual identity — a true-black ground with a slow drifting
/// night sky, warm amber accents bleeding into deep indigo. OLED-friendly,
/// never bright, never harsh. It should feel like exhaling.
public enum Theme {
    // True-black ground (genuine #000 for OLED pixel-off).
    public static let ground   = Color.black
    // Deep indigo used in the breathing sky gradient.
    public static let indigo   = Color(red: 0.09, green: 0.08, blue: 0.21)
    public static let indigoDeep = Color(red: 0.04, green: 0.04, blue: 0.11)
    public static let nightBlue = Color(red: 0.06, green: 0.07, blue: 0.16)

    // Warm amber — the moon, the active accent, the inhale glow.
    public static let amber    = Color(red: 0.96, green: 0.78, blue: 0.50)
    public static let amberDeep = Color(red: 0.90, green: 0.58, blue: 0.32)
    public static let ember    = Color(red: 0.85, green: 0.42, blue: 0.30)

    // Soft cool light for stars and secondary text.
    public static let moonlight = Color(red: 0.86, green: 0.86, blue: 0.92)
    public static let mist     = Color(red: 0.62, green: 0.64, blue: 0.74)
    public static let mutedFar = Color(red: 0.40, green: 0.42, blue: 0.52)

    // Panel surfaces — barely lifted from black.
    public static let panel    = Color(red: 0.07, green: 0.07, blue: 0.11)
    public static let panelHi  = Color(red: 0.11, green: 0.11, blue: 0.17)
    public static let line     = Color(red: 0.18, green: 0.18, blue: 0.26)
}

/// Quiet font helpers — a soft serif for headings, a calm rounded sans for body.
public extension Font {
    /// Elegant serif for the "good night" voice of the app.
    static func quietSerif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Calm rounded sans for controls and counters.
    static func quietRounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
