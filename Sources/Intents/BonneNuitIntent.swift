import Foundation
import AppIntents

extension Notification.Name {
    /// Posted by the « Bonne nuit » intent; HomeView answers by starting the
    /// Dors ritual flow.
    public static let berceuseDors = Notification.Name("berceuse.dors")
}

/// « Dis Siri, bonne nuit » — opens the app straight into the Dors flow: the
/// settle-in breath, then sounds + music with the sleep timer armed. Also shows
/// up in Shortcuts/Spotlight, so a bedtime Focus automation can trigger it.
struct BonneNuitIntent: AppIntent {
    static let title: LocalizedStringResource = "Bonne nuit"
    static let description = IntentDescription("Lance la nuit : souffle, sons et minuterie. / Starts the night: breath, sounds and sleep timer.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .berceuseDors, object: nil)
        return .result()
    }
}

struct BerceuseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BonneNuitIntent(),
            phrases: [
                "Bonne nuit avec \(.applicationName)",
                "Good night with \(.applicationName)",
                "Lance la nuit avec \(.applicationName)",
                "Start the night with \(.applicationName)",
            ],
            shortTitle: "Bonne nuit",
            systemImageName: "moon.zzz.fill"
        )
    }
}
