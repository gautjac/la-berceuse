import SwiftUI
import SwiftData

// MARK: - Mode chevet (nightstand)

/// The bedside resting state: true-black sky, a faint clock, the timer if one
/// is armed — and nothing else. Keeps the screen awake (dimmed by the user's
/// Pénombre setting); a tap reveals the exit.
struct ChevetView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [Settings]
    @State private var showControls = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    var body: some View {
        ZStack {
            NightSky(dim: min(settings.dimLevel, 0.35), glow: 0.6)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                TimelineView(.periodic(from: .now, by: 10)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.quietSerif(72, .regular))
                        .foregroundStyle(Theme.moonlight.opacity(0.82))
                        .monospacedDigit()
                }
                if sleepTimer.isActive {
                    HStack(spacing: 7) {
                        Image(systemName: "timer").font(.system(size: 13))
                        Text(sleepTimer.clockString).monospacedDigit()
                    }
                    .font(.quietRounded(14))
                    .foregroundStyle(Theme.mutedFar)
                }
                Spacer()
                if showControls {
                    Button {
                        dismiss()
                    } label: {
                        Text(loc.t("Quitter le mode chevet", "Leave nightstand mode"))
                            .font(.quietRounded(14, .medium))
                            .foregroundStyle(Theme.mist)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.panel.opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 34)
                    .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) { showControls.toggle() }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }
}

// MARK: - Ritual player

/// An `Identifiable` box so a plan can drive `fullScreenCover(item:)`.
struct ActivePlan: Identifiable {
    let id = UUID()
    let plan: RitualPlan
}

/// Runs a ritual's steps in sequence — a compact breath orb, the word stream,
/// a paced nidra script — then, if the plan ends in a sounds stage, starts the
/// night (mix + generative music + sleep timer) and settles into Mode chevet.
struct RitualPlayerView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsRows: [Settings]

    let plan: RitualPlan

    @State private var stepIndex = 0
    @State private var stepStart = Date()
    @State private var stepElapsed: Double = 0
    @State private var ticker: Timer?
    @State private var sessionStart = Date()
    @State private var resting = false          // chevet resting state reached
    // Shuffle state.
    @State private var shuffle: CognitiveShuffle?
    @State private var currentWord = ""
    @State private var lastWordAt: Double = -10
    // Nidra state.
    @State private var nidraLine = 0

    private var settings: Settings { settingsRows.first ?? Settings() }
    private var step: RitualStep? {
        stepIndex < plan.steps.count ? plan.steps[stepIndex] : nil
    }

    var body: some View {
        ZStack {
            if resting {
                ChevetView()
            } else {
                NightSky(dim: settings.dimLevel, glow: 1.1).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if let step { stage(for: step) }
                    Spacer()
                    progressDots
                    skipButton
                }
                .padding(.horizontal, 26)
            }
        }
        .onAppear { begin() }
        .onDisappear { finish() }
    }

    // MARK: chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.mutedFar)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(plan.name == "Dors" ? loc.t("Dors", "Sleep") : plan.name)
                .font(.quietRounded(14, .medium)).foregroundStyle(Theme.mist)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 10)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, _ in
                Circle()
                    .fill(i <= stepIndex ? Theme.amberDeep : Theme.line)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 16)
    }

    private var skipButton: some View {
        Button { advanceStep() } label: {
            Text(loc.t("Passer", "Skip"))
                .font(.quietRounded(13, .medium))
                .foregroundStyle(Theme.mutedFar)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Theme.panel.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 30)
    }

    // MARK: stages

    @ViewBuilder
    private func stage(for step: RitualStep) -> some View {
        switch step.kind {
        case .breath:  breathStage(BreathPattern.by(id: step.detail))
        case .shuffle: shuffleStage
        case .nidra:   nidraStage(step)
        case .sounds:  EmptyView()   // handled as a side effect, never rendered
        }
    }

    /// A compact breathing orb reusing the exact pacing math of Le souffle.
    private func breathStage(_ pattern: BreathPattern) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tctx in
            let t = tctx.date.timeIntervalSince(stepStart)
            let r = pattern.resolve(at: t)
            let scale = pattern.orbScale(at: t)
            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.amber.opacity(0.55), Theme.amberDeep.opacity(0.12), .clear],
                                             center: .center, startRadius: 8, endRadius: 130))
                        .frame(width: 240, height: 240)
                        .scaleEffect(reduceMotion ? 1.0 : scale)
                        .opacity(reduceMotion ? 0.35 + 0.65 * scale : 1)
                    Circle()
                        .strokeBorder(Theme.amber.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 150, height: 150)
                        .scaleEffect(reduceMotion ? 1.0 : scale)
                }
                VStack(spacing: 6) {
                    Text(loc.lang == .fr ? r.phase.fr : r.phase.en)
                        .font(.quietSerif(24)).foregroundStyle(Theme.moonlight)
                    Text("\(max(1, Int((r.phaseDuration - r.phaseElapsed).rounded(.up))))")
                        .font(.quietRounded(15)).foregroundStyle(Theme.mutedFar)
                        .monospacedDigit()
                }
            }
        }
    }

    private var shuffleStage: some View {
        VStack(spacing: 18) {
            Text(currentWord)
                .font(.quietSerif(34))
                .foregroundStyle(Theme.moonlight)
                .transition(.opacity)
                .id(currentWord)
                .animation(.easeInOut(duration: 1.2), value: currentWord)
            Text(loc.t("Laisse chaque image passer.", "Let each image drift by."))
                .font(.quietRounded(13)).foregroundStyle(Theme.mutedFar)
        }
    }

    private func nidraStage(_ step: RitualStep) -> some View {
        let script = NidraScript.all.first { $0.id == step.detail } ?? NidraScript.all[0]
        let lines = script.lines(loc.lang)
        return Text(nidraLine < lines.count ? lines[nidraLine] : loc.t("Repose-toi.", "Rest now."))
            .font(.quietSerif(24))
            .foregroundStyle(Theme.moonlight)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .animation(.easeInOut(duration: 1.0), value: nidraLine)
            .padding(.horizontal, 8)
    }

    // MARK: engine

    private func begin() {
        sessionStart = Date()
        startStep(0)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func startStep(_ index: Int) {
        stepIndex = index
        stepStart = Date()
        stepElapsed = 0
        nidraLine = 0
        lastWordAt = -10
        guard let step else { startNightAndRest(); return }

        switch step.kind {
        case .shuffle:
            shuffle = CognitiveShuffle(lang: loc.lang)
        case .sounds:
            startNightAndRest()
        default:
            break
        }
    }

    private func tick() {
        guard !resting, let step else { return }
        stepElapsed = Date().timeIntervalSince(stepStart)

        switch step.kind {
        case .shuffle:
            // A new neutral word every ~8 s, softly spoken.
            if stepElapsed - lastWordAt >= 8 {
                lastWordAt = stepElapsed
                if var s = shuffle {
                    currentWord = s.next()
                    shuffle = s
                }
                if settings.speechEnabled { Narrator.shared.speak(currentWord, lang: loc.lang, volume: 0.55) }
            }
        case .nidra:
            let script = NidraScript.all.first { $0.id == step.detail } ?? NidraScript.all[0]
            let pace = script.secondsPerLine(loc.lang)
            let target = min(Int(stepElapsed / pace), script.lines(loc.lang).count - 1)
            if target > nidraLine {
                nidraLine = target
                if settings.speechEnabled {
                    Narrator.shared.speak(script.lines(loc.lang)[nidraLine], lang: loc.lang,
                                          volume: Float(0.7 * sleepTimer.timer.volumeMultiplier))
                }
            }
        default:
            break
        }

        if step.seconds > 0, stepElapsed >= step.seconds {
            advanceStep()
        }
    }

    private func advanceStep() {
        Narrator.shared.stop()
        if stepIndex + 1 < plan.steps.count {
            startStep(stepIndex + 1)
        } else if step?.kind == .sounds {
            startNightAndRest()
        } else {
            // A plan with no sounds stage (e.g. the 3 a.m. rescue) ends in the
            // dark quiet of the chevet rather than bouncing back to a menu.
            resting = true
        }
    }

    /// The sounds stage: make sure the night is sounding, arm the timer, rest.
    private func startNightAndRest() {
        let soundStep = plan.steps.last { $0.kind == .sounds }
        if soundStep != nil {
            // If nothing is playing yet, lay a gentle default bed.
            if !SoundEngine.shared.anyActive {
                SoundEngine.shared.apply(mix: [.rain: 0.35, .drone: 0.22])
            }
            if !MusicEngine.shared.isPlaying {
                MusicEngine.shared.breathCyclePeriod =
                    BreathPattern.by(id: settings.defaultBreathPatternID).cycleDuration
                MusicEngine.shared.play(.sommeil)
            }
            if let m = soundStep?.minutes, m > 0 {
                sleepTimer.start(minutes: Int(m))
            }
        }
        withAnimation(.easeInOut(duration: 1.2)) { resting = true }
    }

    private func finish() {
        ticker?.invalidate(); ticker = nil
        Narrator.shared.stop()
        let dur = Date().timeIntervalSince(sessionStart)
        if dur > 20 {
            ctx.insert(RitualSession(kind: "ritual", detail: plan.name,
                                     startedAt: sessionStart, duration: dur))
            try? ctx.save()
            Task { await SleepHealth.shared.logWindDown(start: sessionStart, end: Date()) }
        }
    }
}

// MARK: - Ritual editor

/// Compose a ritual: name it, stack steps, save. Kept deliberately small — a
/// bedtime app is no place for a settings maze.
struct RitualEditorView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var rituals: [SavedRitual]

    @State private var name = ""
    @State private var steps: [RitualStep] = [
        RitualStep(kind: .breath, detail: "478", minutes: 3),
        RitualStep(kind: .sounds, minutes: 45),
    ]
    @State private var isDefault = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TextField(loc.t("Nom du rituel", "Ritual name"), text: $name)
                        .font(.quietRounded(16, .medium))
                        .foregroundStyle(Theme.moonlight)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel.opacity(0.7)))

                    ForEach($steps) { $step in
                        stepRow($step)
                    }

                    addStepMenu

                    Toggle(isOn: $isDefault) {
                        Text(loc.t("Rituel du bouton « Dors »", "Used by the Sleep button"))
                            .font(.quietRounded(14)).foregroundStyle(Theme.mist)
                    }
                    .tint(Theme.amberDeep)
                    .padding(.horizontal, 4)

                    Button { save() } label: {
                        Text(loc.t("Enregistrer le rituel", "Save ritual"))
                            .font(.quietRounded(15, .semibold))
                            .foregroundStyle(Theme.ground)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.amber))
                    }
                    .buttonStyle(.plain)
                    .disabled(steps.isEmpty)
                    .opacity(steps.isEmpty ? 0.4 : 1)
                }
                .padding(20)
            }
            .background(Theme.indigoDeep)
            .navigationTitle(loc.t("Nouveau rituel", "New ritual"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("Annuler", "Cancel")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stepRow(_ step: Binding<RitualStep>) -> some View {
        let s = step.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: s.kind.symbol).foregroundStyle(Theme.amber).frame(width: 24)
                Text(loc.t(s.kind.nameFR, s.kind.nameEN))
                    .font(.quietRounded(15, .medium)).foregroundStyle(Theme.moonlight)
                Spacer()
                Button {
                    steps.removeAll { $0.id == s.id }
                } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Theme.mutedFar)
                }
                .buttonStyle(.plain)
            }
            switch s.kind {
            case .breath:
                Picker("", selection: step.detail) {
                    ForEach(BreathPattern.all) { p in
                        Text(loc.t(p.nameFR, p.nameEN)).tag(p.id)
                    }
                }
                .pickerStyle(.segmented)
                minutesStepper(step, range: 1...15, label: loc.t("min de souffle", "min of breath"))
            case .shuffle:
                minutesStepper(step, range: 2...30, label: loc.t("min de brouillage", "min of shuffle"))
            case .nidra:
                Picker("", selection: step.detail) {
                    ForEach(NidraScript.all) { n in
                        Text(loc.t(n.titleFR, n.titleEN)).tag(n.id)
                    }
                }
                .pickerStyle(.segmented)
            case .sounds:
                minutesStepper(step, range: 0...120, by: 15, label: loc.t("min de minuterie (0 = sans fin)", "min timer (0 = endless)"))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel.opacity(0.7)))
    }

    private func minutesStepper(_ step: Binding<RitualStep>, range: ClosedRange<Double>,
                                by delta: Double = 1, label: String) -> some View {
        HStack {
            Text("\(Int(step.wrappedValue.minutes)) \(label)")
                .font(.quietRounded(13)).foregroundStyle(Theme.mist)
            Spacer()
            Stepper("", value: step.minutes, in: range, step: delta).labelsHidden()
        }
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(RitualStepKind.allCases) { kind in
                Button {
                    let detail = kind == .breath ? "478" : (kind == .nidra ? NidraScript.all[0].id : "")
                    let minutes: Double = kind == .sounds ? 45 : (kind == .nidra ? 0 : 5)
                    steps.append(RitualStep(kind: kind, detail: detail, minutes: minutes))
                } label: {
                    Label(loc.t(kind.nameFR, kind.nameEN), systemImage: kind.symbol)
                }
            }
        } label: {
            Label(loc.t("Ajouter une étape", "Add a step"), systemImage: "plus")
                .font(.quietRounded(14, .medium)).foregroundStyle(Theme.amber)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panelHi))
        }
    }

    private func save() {
        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? loc.t("Mon rituel", "My ritual")
            : name.trimmingCharacters(in: .whitespaces)
        if isDefault {
            for r in rituals { r.isDefault = false }
        }
        ctx.insert(SavedRitual(name: finalName, steps: steps, isDefault: isDefault))
        try? ctx.save()
        dismiss()
    }
}
