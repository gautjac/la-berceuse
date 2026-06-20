import Foundation
import SwiftData

/// Seeds first-launch content: a couple of favourite mixes, a little ritual
/// history, and the Settings row — so the app feels lived-in (and screenshots
/// look real) without forcing the user to build everything first.
public enum DemoSeed {
    public static func seedIfNeeded(_ ctx: ModelContext) {
        // Settings singleton.
        let settingsCount = (try? ctx.fetchCount(FetchDescriptor<Settings>())) ?? 0
        if settingsCount == 0 {
            ctx.insert(Settings())
        }

        let mixCount = (try? ctx.fetchCount(FetchDescriptor<SavedMix>())) ?? 0
        if mixCount == 0 {
            ctx.insert(SavedMix(name: t("Pluie sur la tente", "Rain on the tent"),
                                volumes: [SoundLayer.rain.rawValue: 0.7,
                                          SoundLayer.drone.rawValue: 0.3,
                                          SoundLayer.brownNoise.rawValue: 0.2]))
            ctx.insert(SavedMix(name: t("Bord de mer", "By the sea"),
                                volumes: [SoundLayer.waves.rawValue: 0.65,
                                          SoundLayer.wind.rawValue: 0.3,
                                          SoundLayer.musicBox.rawValue: 0.18]))
            ctx.insert(SavedMix(name: t("Vide complet", "Quiet hush"),
                                volumes: [SoundLayer.pinkNoise.rawValue: 0.4,
                                          SoundLayer.drone.rawValue: 0.25]))
        }

        let sessionCount = (try? ctx.fetchCount(FetchDescriptor<RitualSession>())) ?? 0
        if sessionCount == 0 {
            let cal = Calendar.current
            let now = Date()
            func at(_ daysAgo: Int, _ hour: Int) -> Date {
                let base = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                return cal.date(bySettingHour: hour, minute: 12, second: 0, of: base) ?? base
            }
            ctx.insert(RitualSession(kind: "breath", detail: "478", startedAt: at(1, 22), duration: 360))
            ctx.insert(RitualSession(kind: "nidra", detail: "bodyscan10", startedAt: at(2, 23), duration: 600))
            ctx.insert(RitualSession(kind: "shuffle", detail: "", startedAt: at(3, 22), duration: 540))
        }

        try? ctx.save()
    }
}
