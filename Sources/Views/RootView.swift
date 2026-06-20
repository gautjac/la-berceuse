import SwiftUI
import SwiftData

enum BerceuseTab: String, CaseIterable, Identifiable {
    case home, breath, sound, shuffle, nidra
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home:    return "moon.stars"
        case .breath:  return "lungs"
        case .sound:   return "slider.horizontal.3"
        case .shuffle: return "shuffle"
        case .nidra:   return "figure.mind.and.body"
        }
    }
    @MainActor func title(_ loc: LocManager) -> String {
        switch self {
        case .home:    return loc.t("Accueil", "Home")
        case .breath:  return loc.t("Souffle", "Breath")
        case .sound:   return loc.t("Sons", "Sounds")
        case .shuffle: return loc.t("Brouillage", "Shuffle")
        case .nidra:   return loc.t("Repos", "Rest")
        }
    }
}

struct RootView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    @State private var tab: BerceuseTab = .home
    @StateObject private var sleepTimer = SleepTimerController.shared

    private var settings: Settings {
        settingsRows.first ?? Settings()
    }

    /// Honour `-demoTab <home|breath|sound|shuffle|nidra>` and `-demoLang fr|en`
    /// launch arguments so screenshots can jump straight to a screen.
    private func applyDemoFlags() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demoLang"), i + 1 < args.count,
           let l = Lang(rawValue: args[i + 1]) {
            loc.lang = l
        }
        if let i = args.firstIndex(of: "-demoTab"), i + 1 < args.count,
           let dest = BerceuseTab(rawValue: args[i + 1]) {
            tab = dest
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NightSky(dim: settings.dimLevel, glow: tab == .breath ? 1.4 : 1.0)

            Group {
                switch tab {
                case .home:    HomeView(tab: $tab)
                case .breath:  BreathView()
                case .sound:   SoundscapeView()
                case .shuffle: ShuffleView()
                case .nidra:   NidraListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 78)

            SoftTabBar(tab: $tab)
        }
        .environmentObject(sleepTimer)
        .onAppear {
            Haptics.enabled = settings.hapticsEnabled
            applyDemoFlags()
        }
    }
}

/// A quiet, dark custom tab bar — no harsh chrome, just soft amber for the
/// active item.
struct SoftTabBar: View {
    @EnvironmentObject var loc: LocManager
    @Binding var tab: BerceuseTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BerceuseTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { tab = item }
                    #if canImport(UIKit) && !targetEnvironment(simulator)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 19, weight: .regular))
                        Text(item.title(loc))
                            .font(.quietRounded(10, .medium))
                    }
                    .foregroundStyle(tab == item ? Theme.amber : Theme.mutedFar)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title(loc))
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}
