import SwiftUI
import SwiftData

@main
struct LaBerceuseApp: App {
    let container: ModelContainer
    @StateObject private var loc = LocManager.shared

    init() {
        do {
            container = try ModelContainer(
                for: SavedMix.self, RitualSession.self, Settings.self
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        DemoSeed.seedIfNeeded(container.mainContext)
        SoundEngine.shared.prepare()
        MusicEngine.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(loc)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
        }
        .modelContainer(container)
    }
}
