import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    @Binding var tab: BerceuseTab

    @State private var sleep: SleepSummary?
    @State private var healthAsked = false
    @State private var showTimer = false
    @State private var showSettings = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return loc.t("Bon matin", "Good morning")
        case 12..<18: return loc.t("Bonjour", "Good afternoon")
        case 18..<22: return loc.t("Bonsoir", "Good evening")
        default:      return loc.t("Bonne nuit", "Good night")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header

                if let sleep {
                    sleepStat(sleep)
                }

                timerCard

                ritualGrid

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .task { await loadHealth() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoSleep") {
                sleep = SleepSummary(asleepHours: 7.35, inBedHours: 7.8, date: Date())
            }
            if ProcessInfo.processInfo.arguments.contains("-demoTimer") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showTimer = true }
            }
        }
        .sheet(isPresented: $showTimer) {
            TimerSheet().presentationDetents([.medium])
                .presentationBackground(Theme.indigoDeep)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().presentationBackground(Theme.indigoDeep)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.quietSerif(34, .regular))
                    .foregroundStyle(Theme.moonlight)
                Text(loc.t("Laisse la journée se déposer.",
                           "Let the day settle."))
                    .font(.quietRounded(15))
                    .foregroundStyle(Theme.mist)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.mutedFar)
            }
            .accessibilityLabel(loc.t("Réglages", "Settings"))
        }
    }

    private func sleepStat(_ s: SleepSummary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.amberDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("La nuit dernière", "Last night"))
                    .font(.quietRounded(12))
                    .foregroundStyle(Theme.mist)
                Text(loc.t("\(s.asleepHM) de sommeil", "\(s.asleepHM) asleep"))
                    .font(.quietRounded(18, .semibold))
                    .foregroundStyle(Theme.moonlight)
            }
            Spacer()
        }
        .padding(16)
        .background(card)
    }

    private var timerCard: some View {
        Button { showTimer = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "timer")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("Minuterie de sommeil", "Sleep timer"))
                        .font(.quietRounded(15, .medium))
                        .foregroundStyle(Theme.moonlight)
                    Text(sleepTimer.isActive
                         ? loc.t("Fond en \(sleepTimer.clockString)", "Fading in \(sleepTimer.clockString)")
                         : loc.t("Désactivée", "Off"))
                        .font(.quietRounded(13))
                        .foregroundStyle(sleepTimer.isActive ? Theme.amberDeep : Theme.mist)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedFar)
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    private var ritualGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t("Rituels", "Rituals"))
                .font(.quietRounded(13, .semibold))
                .foregroundStyle(Theme.mist)
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)], spacing: 14) {
                tile(.breath, "lungs.fill",
                     loc.t("Souffle", "Breathe"),
                     loc.t("Cadence le souffle", "Pace your breath"))
                tile(.sound, "waveform",
                     loc.t("Sons", "Soundscapes"),
                     loc.t("Mixe ta nuit", "Mix your night"))
                tile(.shuffle, "shuffle",
                     loc.t("Brouillage", "Shuffle"),
                     loc.t("Apaise le mental", "Quiet the mind"))
                tile(.nidra, "figure.mind.and.body",
                     loc.t("Repos profond", "Deep rest"),
                     loc.t("Yoga-nidra guidé", "Guided yoga-nidra"))
            }
        }
    }

    private func tile(_ dest: BerceuseTab, _ symbol: String, _ title: String, _ subtitle: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { tab = dest } } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.amberDeep)
                Spacer(minLength: 18)
                Text(title)
                    .font(.quietRounded(17, .semibold))
                    .foregroundStyle(Theme.moonlight)
                Text(subtitle)
                    .font(.quietRounded(12))
                    .foregroundStyle(Theme.mist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 132)
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.panel.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.line.opacity(0.6), lineWidth: 1)
            )
    }

    private func loadHealth() async {
        guard !healthAsked else { return }
        healthAsked = true
        // Skip the system permission prompt during screenshot/demo runs so the
        // captures aren't blocked by the modal (HealthKit itself is verified
        // separately).
        if ProcessInfo.processInfo.arguments.contains("-demoNoHealth") { return }
        _ = await SleepHealth.shared.requestAuthorization()
        sleep = await SleepHealth.shared.lastNight()
    }
}
