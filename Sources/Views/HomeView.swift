import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    @Query(sort: \SavedRitual.createdAt, order: .reverse) private var rituals: [SavedRitual]
    @Binding var tab: BerceuseTab

    @State private var sleep: SleepSummary?
    @State private var healthAsked = false
    @State private var showTimer = false
    @State private var showSettings = false
    @State private var activePlan: ActivePlan?
    @State private var showChevet = false
    @State private var showCarnet = false
    @State private var showRitualEditor = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    /// What the « Dors » button runs: the user's default ritual if one is
    /// marked, else the built-in settle-in plan from their settings.
    private var dorsPlan: RitualPlan {
        rituals.first(where: { $0.isDefault })?.plan
            ?? RitualPlan.dors(breathPatternID: settings.defaultBreathPatternID,
                               timerMinutes: settings.defaultTimerMinutes)
    }

    private var isRescueHour: Bool {
        RitualPlan.isRescueHour(Calendar.current.component(.hour, from: Date()))
    }

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

                if isRescueHour {
                    rescueCard
                }

                dorsCard

                if let sleep {
                    sleepStat(sleep)
                }

                timerCard
                chevetCard

                savedRituals

                ritualGrid

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $activePlan) { box in
            RitualPlayerView(plan: box.plan)
        }
        .fullScreenCover(isPresented: $showChevet) {
            ChevetView()
        }
        .sheet(isPresented: $showCarnet) {
            CarnetView().presentationBackground(Theme.indigoDeep)
        }
        .sheet(isPresented: $showRitualEditor) {
            RitualEditorView().presentationBackground(Theme.indigoDeep)
        }
        .onReceive(NotificationCenter.default.publisher(for: .berceuseDors)) { _ in
            // « Bonne nuit » Siri intent — go straight into the Dors flow.
            activePlan = ActivePlan(plan: dorsPlan)
        }
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

    /// The one-tap night: a short settle-in breath, then sounds + music with
    /// the timer armed — the whole app distilled into a single button.
    private var dorsCard: some View {
        Button { activePlan = ActivePlan(plan: dorsPlan) } label: {
            HStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.ground)
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.t("Dors", "Sleep"))
                        .font(.quietSerif(24)).foregroundStyle(Theme.ground)
                    Text(dorsPlan.summary(loc.lang))
                        .font(.quietRounded(12, .medium))
                        .foregroundStyle(Theme.ground.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ground.opacity(0.7))
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.amber, Theme.amberDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loc.t("Dors — lancer la nuit", "Sleep — start the night"))
    }

    /// 1–5 a.m.: an awake mind needs one giant button, not a menu.
    private var rescueCard: some View {
        Button { activePlan = ActivePlan(plan: RitualPlan.rescue) } label: {
            VStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.system(size: 26)).foregroundStyle(Theme.amber)
                Text(loc.t("Réveillé en pleine nuit ?", "Awake in the middle of the night?"))
                    .font(.quietSerif(21)).foregroundStyle(Theme.moonlight)
                Text(loc.t("Deux minutes de soupirs, puis le brouillage. Rien à décider.",
                           "Two minutes of sighs, then the shuffle. Nothing to decide."))
                    .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22).padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.panel.opacity(0.85))
                    .overlay(RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Theme.amberDeep.opacity(0.5), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var chevetCard: some View {
        Button { showChevet = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "moon.haze")
                    .font(.system(size: 22)).foregroundStyle(Theme.amberDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("Mode chevet", "Nightstand mode"))
                        .font(.quietRounded(15, .medium)).foregroundStyle(Theme.moonlight)
                    Text(loc.t("Une horloge, le ciel, rien d'autre.", "A clock, the sky, nothing else."))
                        .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedFar)
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
    }

    private var savedRituals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("Mes rituels", "My rituals"))
                .font(.quietRounded(13, .semibold)).foregroundStyle(Theme.mist)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rituals) { ritual in
                        Button { activePlan = ActivePlan(plan: ritual.plan) } label: {
                            HStack(spacing: 6) {
                                if ritual.isDefault {
                                    Image(systemName: "moon.zzz.fill").font(.system(size: 11))
                                }
                                Text(ritual.name).font(.quietRounded(13, .medium))
                            }
                            .foregroundStyle(Theme.moonlight)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Theme.panelHi))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                for r in rituals { r.isDefault = (r === ritual) }
                                try? ctx.save()
                            } label: {
                                Label(loc.t("Utiliser pour « Dors »", "Use for Sleep button"),
                                      systemImage: "moon.zzz")
                            }
                            Button(role: .destructive) {
                                ctx.delete(ritual); try? ctx.save()
                            } label: {
                                Label(loc.t("Supprimer", "Delete"), systemImage: "trash")
                            }
                        }
                    }
                    Button { showRitualEditor = true } label: {
                        Label(loc.t("Nouveau", "New"), systemImage: "plus")
                            .font(.quietRounded(13, .medium))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().strokeBorder(Theme.amberDeep.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func sleepStat(_ s: SleepSummary) -> some View {
        Button { showCarnet = true } label: {
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
                // The stat opens the carnet — where nights and rituals meet.
                Text(loc.t("Carnet", "Journal"))
                    .font(.quietRounded(12, .medium)).foregroundStyle(Theme.amberDeep)
                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedFar)
            }
            .padding(16)
            .background(card)
        }
        .buttonStyle(.plain)
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
