import SwiftUI
import SwiftData

/// The cognitive shuffle: a slow stream of unrelated neutral words, one every
/// few seconds, shown large and softly spoken (optional). The mind tries to
/// picture each, then lets it go — which mimics sleep onset and blocks
/// rumination.
struct ShuffleView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]

    @State private var shuffle: CognitiveShuffle?
    @State private var word: String = ""
    @State private var prevWord: String = ""
    @State private var running = false
    @State private var ticker: Timer?
    @State private var sessionStart = Date()
    @State private var interval: Double = 6   // seconds per word
    @State private var fade = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            wordStage
            Spacer()
            paceControl
            startButton
        }
        .padding(.horizontal, 24)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoRun") { start() }
        }
        .onDisappear { stop(persist: true) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(loc.t("Brouillage cognitif", "Cognitive shuffle"))
                .font(.quietSerif(26)).foregroundStyle(Theme.moonlight)
            Text(loc.t("Imagine chaque mot, puis laisse-le partir.",
                       "Picture each word, then let it drift away."))
                .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 18)
    }

    private var wordStage: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.indigo.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 380, height: 380)
            Text(running ? word : loc.t("…", "…"))
                .font(.quietSerif(44, .light))
                .foregroundStyle(Theme.moonlight)
                .opacity(fade ? 0.0 : 1.0)
                .animation(.easeInOut(duration: 0.9), value: fade)
                .animation(.easeInOut(duration: 0.9), value: word)
                .id(word)
                .multilineTextAlignment(.center)
        }
    }

    private var paceControl: some View {
        VStack(spacing: 6) {
            HStack {
                Text(loc.t("Lent", "Slow")).font(.quietRounded(11)).foregroundStyle(Theme.mutedFar)
                Slider(value: $interval, in: 3...10, step: 1)
                    .tint(Theme.amberDeep)
                    .onChange(of: interval) { if running { rearm() } }
                Text(loc.t("Vif", "Brisk")).font(.quietRounded(11)).foregroundStyle(Theme.mutedFar)
            }
            Text(loc.t("Un mot toutes les \(Int(interval)) s",
                       "A word every \(Int(interval)) s"))
                .font(.quietRounded(12)).foregroundStyle(Theme.mist)
        }
        .padding(.bottom, 8)
    }

    private var startButton: some View {
        Button {
            if running { stop(persist: true) } else { start() }
        } label: {
            Text(running ? loc.t("Terminer", "Finish") : loc.t("Commencer", "Begin"))
                .font(.quietRounded(17, .semibold))
                .foregroundStyle(running ? Theme.moonlight : Color.black)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 28)
                    .fill(running ? Theme.panelHi : Theme.amber))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    // MARK: - Engine

    private func start() {
        shuffle = CognitiveShuffle(lang: loc.lang)
        sessionStart = Date()
        running = true
        advance()
        rearm()
    }

    private func rearm() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in self.advance() }
        }
    }

    private func advance() {
        guard var s = shuffle else { return }
        // Brief fade between words.
        fade = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            prevWord = word
            word = s.next()
            shuffle = s
            fade = false
            if settings.speechEnabled {
                Narrator.shared.speak(word, lang: loc.lang)
            }
        }
    }

    private func stop(persist: Bool) {
        guard running else { return }
        running = false
        ticker?.invalidate(); ticker = nil
        Narrator.shared.stop()
        let dur = Date().timeIntervalSince(sessionStart)
        if persist, dur > 20 {
            ctx.insert(RitualSession(kind: "shuffle", detail: "", startedAt: sessionStart, duration: dur))
            try? ctx.save()
            Task { await SleepHealth.shared.logWindDown(start: sessionStart, end: Date()) }
        }
    }
}
