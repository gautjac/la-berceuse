import SwiftUI
import SwiftData

/// Pick an NSDR / yoga-nidra script.
struct NidraListView: View {
    @EnvironmentObject var loc: LocManager
    @State private var selected: NidraScript?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(loc.t("Repos profond", "Deep rest"))
                        .font(.quietSerif(30)).foregroundStyle(Theme.moonlight)
                    Text(loc.t("NSDR & yoga-nidra : reposer sans dormir.",
                               "NSDR & yoga-nidra: rest without sleeping."))
                        .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                ForEach(NidraScript.all) { script in
                    Button { selected = script } label: { scriptCard(script) }
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $selected) { script in
            NidraPlayerView(script: script)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoNidra") {
                selected = NidraScript.bodyScan10
            }
        }
    }

    private func scriptCard(_ s: NidraScript) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.14)).frame(width: 56, height: 56)
                Text("\(s.minutes)")
                    .font(.quietRounded(20, .semibold)).foregroundStyle(Theme.amber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t(s.titleFR, s.titleEN))
                    .font(.quietRounded(18, .semibold)).foregroundStyle(Theme.moonlight)
                Text(loc.t(s.subtitleFR, s.subtitleEN))
                    .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "play.circle").font(.system(size: 26)).foregroundStyle(Theme.amberDeep)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.panel.opacity(0.78))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line.opacity(0.6), lineWidth: 1)))
    }
}

/// Plays a script line-by-line at a calm pace, optionally spoken, over the
/// night sky. A subtle progress arc tracks the journey.
struct NidraPlayerView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    let script: NidraScript

    @State private var lineIndex = 0
    @State private var running = true
    @State private var ticker: Timer?
    @State private var sessionStart = Date()
    @State private var fade = false

    private var settings: Settings { settingsRows.first ?? Settings() }
    private var lines: [String] { script.lines(loc.lang) }
    private var progress: Double {
        lines.isEmpty ? 0 : Double(lineIndex + 1) / Double(lines.count)
    }

    var body: some View {
        ZStack {
            NightSky(dim: settings.dimLevel, glow: 0.8)
            VStack {
                topBar
                Spacer()
                lineStage
                Spacer()
                progressArc
                controls
            }
            .padding(.horizontal, 26)
        }
        .onAppear { begin() }
        .onDisappear { finish() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.mutedFar)
            }
            Spacer()
            Text(loc.t(script.titleFR, script.titleEN))
                .font(.quietRounded(14, .medium)).foregroundStyle(Theme.mist)
            Spacer()
            Image(systemName: "xmark").opacity(0)   // balance
        }
        .padding(.top, 18)
    }

    private var lineStage: some View {
        Text(lineIndex < lines.count ? lines[lineIndex] : loc.t("Repose-toi.", "Rest now."))
            .font(.quietSerif(26, .regular))
            .foregroundStyle(Theme.moonlight)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .opacity(fade ? 0 : 1)
            .animation(.easeInOut(duration: 1.0), value: fade)
            .animation(.easeInOut(duration: 1.0), value: lineIndex)
            .padding(.horizontal, 10)
    }

    private var progressArc: some View {
        ZStack {
            Circle().stroke(Theme.line.opacity(0.5), lineWidth: 3).frame(width: 56, height: 56)
            Circle().trim(from: 0, to: progress)
                .stroke(Theme.amberDeep, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
                .animation(.easeInOut, value: progress)
        }
        .padding(.bottom, 18)
    }

    private var controls: some View {
        Button {
            running.toggle()
            if running { rearm() } else { ticker?.invalidate(); Narrator.shared.stop() }
        } label: {
            Image(systemName: running ? "pause.fill" : "play.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.black)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Theme.amber))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 30)
    }

    // MARK: - Pacing

    private func begin() {
        sessionStart = Date()
        lineIndex = 0
        speakCurrent()
        rearm()
    }

    private func rearm() {
        ticker?.invalidate()
        let pace = script.secondsPerLine(loc.lang)
        ticker = Timer.scheduledTimer(withTimeInterval: pace, repeats: true) { _ in
            Task { @MainActor in self.advance() }
        }
    }

    private func advance() {
        guard running else { return }
        if lineIndex + 1 >= lines.count {
            ticker?.invalidate()
            return
        }
        fade = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            lineIndex += 1
            fade = false
            speakCurrent()
        }
    }

    private func speakCurrent() {
        guard settings.speechEnabled, lineIndex < lines.count else { return }
        Narrator.shared.speak(lines[lineIndex], lang: loc.lang, volume: 0.7)
    }

    private func finish() {
        ticker?.invalidate(); ticker = nil
        Narrator.shared.stop()
        let dur = Date().timeIntervalSince(sessionStart)
        if dur > 20 {
            ctx.insert(RitualSession(kind: "nidra", detail: script.id,
                                     startedAt: sessionStart, duration: dur))
            try? ctx.save()
            Task { await SleepHealth.shared.logWindDown(start: sessionStart, end: Date()) }
        }
    }
}
