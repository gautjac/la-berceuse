import SwiftUI

/// The signature ambient backdrop: a true-black ground with a deep-indigo glow
/// that slowly breathes, a low warm moon, and a faint drift of stars.
/// Reduced-motion safe — when Reduce Motion is on, everything holds still.
struct NightSky: View {
    /// 0 (dimmest, near pure black) … 1 (normal). Driven by the dim setting.
    var dim: Double = 0.7
    /// Extra emphasis (e.g. on the breathing screen) for the central glow.
    var glow: Double = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, time: reduceMotion ? 0 : t)
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, time: Double) {
        let w = size.width, h = size.height
        let d = max(0, min(1, dim))

        // Breathing vertical gradient: indigo at top → black at bottom, with the
        // indigo intensity slowly oscillating (a ~12 s breath).
        let pulse = 0.5 + 0.5 * sin(time / 12.0 * 2 * .pi)
        let indigoStrength = (0.35 + 0.25 * pulse) * d
        let top = Color(red: 0.10 * indigoStrength * 2.4,
                        green: 0.09 * indigoStrength * 2.4,
                        blue: 0.24 * indigoStrength * 2.6)
        let mid = Color(red: 0.04 * d, green: 0.04 * d, blue: 0.11 * d)
        let grad = Gradient(stops: [
            .init(color: top, location: 0),
            .init(color: mid, location: 0.55),
            .init(color: .black, location: 1.0),
        ])
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(grad,
                                       startPoint: CGPoint(x: w / 2, y: 0),
                                       endPoint: CGPoint(x: w / 2, y: h)))

        // Warm central glow that breathes (stronger on the breathing screen).
        let glowR = min(w, h) * (0.55 + 0.06 * pulse) * glow
        let glowCenter = CGPoint(x: w * 0.5, y: h * 0.40)
        let glowGrad = Gradient(stops: [
            .init(color: Color(red: 0.96, green: 0.62, blue: 0.34)
                .opacity(0.10 * d * glow * (0.6 + 0.4 * pulse)), location: 0),
            .init(color: .clear, location: 1),
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: glowCenter.x - glowR, y: glowCenter.y - glowR,
                                        width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(glowGrad, center: glowCenter,
                                       startRadius: 0, endRadius: glowR))

        // A low warm crescent moon, drifting almost imperceptibly.
        let moonDrift = sin(time / 40.0) * w * 0.012
        let moonC = CGPoint(x: w * 0.74 + moonDrift, y: h * 0.18)
        let moonR = min(w, h) * 0.055
        drawMoon(ctx: &ctx, center: moonC, radius: moonR, dim: d)

        // Faint drifting stars.
        drawStars(ctx: &ctx, size: size, time: time, dim: d)
    }

    private func drawMoon(ctx: inout GraphicsContext, center: CGPoint, radius r: CGFloat, dim d: Double) {
        // Soft halo.
        let halo = Gradient(stops: [
            .init(color: Color(red: 0.96, green: 0.70, blue: 0.40).opacity(0.18 * d), location: 0),
            .init(color: .clear, location: 1),
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r * 3, y: center.y - r * 3,
                                        width: r * 6, height: r * 6)),
                 with: .radialGradient(halo, center: center, startRadius: 0, endRadius: r * 3))

        // Crescent: full disc minus an offset disc, via even-odd blend mode.
        var disc = Path()
        disc.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ctx.drawLayer { layer in
            layer.fill(disc, with: .color(Color(red: 0.97, green: 0.84, blue: 0.59).opacity(0.95 * d)))
            // Carve the shadow disc out.
            let off = r * 0.5
            var shadow = Path()
            shadow.addEllipse(in: CGRect(x: center.x - r + off, y: center.y - r - r * 0.12,
                                         width: r * 2, height: r * 2))
            layer.blendMode = .destinationOut
            layer.fill(shadow, with: .color(.black))
        }
    }

    private func drawStars(ctx: inout GraphicsContext, size: CGSize, time: Double, dim d: Double) {
        // Deterministic scatter; gentle twinkle.
        let count = 46
        var rng = SplitMix(seed: 0xB00C)
        for i in 0..<count {
            let x = CGFloat(rng.unit()) * size.width
            let y = CGFloat(rng.unit()) * size.height * 0.7   // upper sky
            let baseR = CGFloat(0.6 + rng.unit() * 1.6)
            let tw = 0.5 + 0.5 * sin(time * 0.6 + Double(i) * 1.7)
            let alpha = (0.12 + 0.5 * tw) * d
            let r = baseR * (0.8 + 0.4 * tw)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.88, green: 0.88, blue: 0.95).opacity(alpha)))
        }
    }
}

/// Tiny deterministic PRNG for the star scatter (kept local to the view).
private struct SplitMix {
    private var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}
