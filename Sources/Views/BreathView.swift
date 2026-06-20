import SwiftUI
import SwiftData

/// The breathing-orb pacer. A soft amber orb expands and contracts on the exact
/// pacing math of the chosen `BreathPattern`, with the phase word and a count.
/// Optional gentle haptics on phase changes (device-only). Reduced-motion safe.
struct BreathView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsRows: [Settings]

    @State private var pattern: BreathPattern = .fourSevenEight
    @State private var running = false
    @State private var startDate = Date()
    @State private var sessionStart = Date()
    @State private var lastPhase: BreathPhase = .inhale
    @State private var showPicker = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    var body: some View {
        VStack(spacing: 0) {
            picker
            Spacer()
            TimelineView(.animation(paused: !running)) { tl in
                orb(now: tl.date)
            }
            Spacer()
            controls
        }
        .padding(.horizontal, 24)
        .onAppear {
            pattern = .by(id: settings.defaultBreathPatternID)
            if ProcessInfo.processInfo.arguments.contains("-demoRun") { start() }
        }
        .sheet(isPresented: $showPicker) { patternSheet.presentationDetents([.medium]) }
    }

    // MARK: - Orb

    private func orb(now: Date) -> some View {
        let elapsed = running ? now.timeIntervalSince(startDate) : 0
        let resolved = pattern.resolve(at: elapsed)
        let scale = running ? pattern.orbScale(at: elapsed) : 0.7
        let phaseLabel = loc.t(resolved.phase.fr, resolved.phase.en)
        let remaining = max(0, resolved.phaseDuration - resolved.phaseElapsed)

        // Fire haptic when the phase flips.
        if running, resolved.phase != lastPhase {
            DispatchQueue.main.async {
                handlePhaseChange(resolved.phase)
            }
        }

        return ZStack {
            // Outer breathing halo.
            Circle()
                .fill(
                    RadialGradient(colors: [Theme.amber.opacity(0.28), .clear],
                                   center: .center, startRadius: 0, endRadius: 220)
                )
                .frame(width: 440, height: 440)
                .scaleEffect(reduceMotion ? 0.85 : scale)

            // Core orb.
            Circle()
                .fill(
                    RadialGradient(colors: [Theme.amber.opacity(0.9),
                                            Theme.amberDeep.opacity(0.55),
                                            Theme.ember.opacity(0.18)],
                                   center: .center, startRadius: 4, endRadius: 150)
                )
                .frame(width: 240, height: 240)
                .scaleEffect(reduceMotion ? 0.9 : scale)
                .shadow(color: Theme.amber.opacity(0.35), radius: 40)

            VStack(spacing: 8) {
                Text(running ? phaseLabel : loc.t("Prêt ?", "Ready?"))
                    .font(.quietSerif(28, .regular))
                    .foregroundStyle(Color.black.opacity(0.78))
                if running {
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.quietRounded(40, .light))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .contentTransition(.numericText())
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: running)
    }

    private func handlePhaseChange(_ phase: BreathPhase) {
        guard phase != lastPhase else { return }
        lastPhase = phase
        guard settings.hapticsEnabled else { return }
        switch phase {
        case .inhale:  Haptics.inhale()
        case .holdIn, .holdOut: Haptics.hold()
        case .exhale:  Haptics.exhale()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 18) {
            Button {
                if running { stop() } else { start() }
            } label: {
                Text(running ? loc.t("Terminer", "Finish") : loc.t("Commencer", "Begin"))
                    .font(.quietRounded(17, .semibold))
                    .foregroundStyle(running ? Theme.moonlight : Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(running ? Theme.panelHi : Theme.amber)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 10)
    }

    private var picker: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 8) {
                Text(loc.t(pattern.nameFR, pattern.nameEN))
                    .font(.quietRounded(18, .semibold))
                    .foregroundStyle(Theme.moonlight)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.mutedFar)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(Capsule().fill(Theme.panel.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    private var patternSheet: some View {
        VStack(spacing: 14) {
            Capsule().fill(Theme.line).frame(width: 38, height: 4).padding(.top, 10)
            Text(loc.t("Choisis ton souffle", "Choose your breath"))
                .font(.quietSerif(22)).foregroundStyle(Theme.moonlight)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(BreathPattern.all) { p in
                        Button {
                            pattern = p
                            settingsRows.first?.defaultBreathPatternID = p.id
                            try? ctx.save()
                            if running { restart() }
                            showPicker = false
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.t(p.nameFR, p.nameEN))
                                    .font(.quietRounded(17, .semibold))
                                    .foregroundStyle(Theme.moonlight)
                                Text(loc.t(p.descFR, p.descEN))
                                    .font(.quietRounded(12))
                                    .foregroundStyle(Theme.mist)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(p == pattern ? Theme.amber.opacity(0.16) : Theme.panelHi)
                                    .overlay(RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(p == pattern ? Theme.amberDeep : .clear, lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Theme.indigoDeep)
    }

    // MARK: - Session

    private func start() {
        startDate = Date()
        sessionStart = Date()
        lastPhase = .inhale
        running = true
        if settings.hapticsEnabled { Haptics.inhale() }
    }

    private func restart() { startDate = Date(); lastPhase = .inhale }

    private func stop() {
        running = false
        let dur = Date().timeIntervalSince(sessionStart)
        if dur > 20 {
            ctx.insert(RitualSession(kind: "breath", detail: pattern.id,
                                     startedAt: sessionStart, duration: dur))
            try? ctx.save()
            Task { await SleepHealth.shared.logWindDown(start: sessionStart, end: Date()) }
        }
    }
}
