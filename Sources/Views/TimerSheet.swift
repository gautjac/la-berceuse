import SwiftUI
import SwiftData

/// Pick a sleep-timer duration. Starting it arms the app-wide fade-out.
struct TimerSheet: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    @State private var custom: Double = 25

    private var settings: Settings { settingsRows.first ?? Settings() }

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.line).frame(width: 38, height: 4).padding(.top, 10)

            Text(loc.t("Minuterie de sommeil", "Sleep timer"))
                .font(.quietSerif(24))
                .foregroundStyle(Theme.moonlight)
            Text(loc.t("Le son s'efface en douceur, puis le silence.",
                       "The sound fades gently, then silence."))
                .font(.quietRounded(13))
                .foregroundStyle(Theme.mist)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(SleepTimer.presetMinutes, id: \.self) { m in
                    preset(minutes: m)
                }
                Button {
                    start(Int(custom))
                } label: {
                    presetLabel("\(Int(custom)) min", subtitle: loc.t("perso", "custom"), active: false)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                Slider(value: $custom, in: 5...180, step: 5)
                    .tint(Theme.amberDeep)
                Text(loc.t("Personnalisé : \(Int(custom)) min", "Custom: \(Int(custom)) min"))
                    .font(.quietRounded(12))
                    .foregroundStyle(Theme.mist)
            }
            .padding(.horizontal, 6)

            if sleepTimer.isActive {
                Button {
                    sleepTimer.cancel()
                    dismiss()
                } label: {
                    Text(loc.t("Arrêter la minuterie (\(sleepTimer.clockString))",
                               "Stop timer (\(sleepTimer.clockString))"))
                        .font(.quietRounded(14, .medium))
                        .foregroundStyle(Theme.ember)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 24)
        .onAppear { custom = Double(settings.defaultTimerMinutes) }
    }

    private func preset(minutes m: Int) -> some View {
        Button { start(m) } label: {
            presetLabel("\(m)", subtitle: "min", active: sleepTimer.isActive && Int(sleepTimer.timer.total / 60) == m)
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(_ big: String, subtitle: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(big).font(.quietRounded(22, .semibold))
            Text(subtitle).font(.quietRounded(11))
        }
        .foregroundStyle(active ? Color.black : Theme.moonlight)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(active ? Theme.amber : Theme.panelHi)
        )
    }

    private func start(_ minutes: Int) {
        sleepTimer.start(minutes: minutes)
        // Persist as the new default.
        settingsRows.first?.defaultTimerMinutes = minutes
        try? ctx.save()
        dismiss()
    }
}
