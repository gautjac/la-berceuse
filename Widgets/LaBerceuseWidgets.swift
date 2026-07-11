import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct LaBerceuseWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if canImport(ActivityKit)
        SleepTimerLiveActivity()
        #endif
    }
}

#if canImport(ActivityKit)
/// The sleep timer on the Lock Screen and in the Dynamic Island: a moon, the
/// remaining time counting down by itself, and nothing that lights up a dark
/// bedroom. `Text(timerInterval:)` renders the countdown locally, so the app
/// never has to send updates while you drift off.
struct SleepTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepTimerAttributes.self) { context in
            // Lock screen / banner.
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.50))
                VStack(alignment: .leading, spacing: 2) {
                    Text("La Berceuse")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text("🌙")
                    .font(.system(size: 22))
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.04, green: 0.04, blue: 0.11))
            .activitySystemActionForegroundColor(Color(red: 0.96, green: 0.78, blue: 0.50))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.50))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Le son s'éteint doucement…")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.50))
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.endDate, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.50))
            }
        }
    }
}
#endif
