import SwiftUI
import SwiftData

/// The generative soundscape mixer: each layer has its own volume slider,
/// saved mixes recall a whole scene, and a sleep-timer chip arms the fade-out.
struct SoundscapeView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavedMix.createdAt, order: .reverse) private var mixes: [SavedMix]
    @Query private var settingsRows: [Settings]

    @StateObject private var engine = SoundEngine.shared
    @StateObject private var music = MusicEngine.shared
    @State private var showSave = false
    @State private var newName = ""
    @State private var showTimer = false

    private var settings: Settings { settingsRows.first ?? Settings() }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                if !mixes.isEmpty { savedMixes }

                musicCard

                VStack(spacing: 14) {
                    ForEach(SoundLayer.allCases) { layer in
                        layerRow(layer)
                    }
                }

                actionRow
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            syncBreathPeriod()
            // `-demoMusic` auto-starts the generative engine for screenshots.
            if ProcessInfo.processInfo.arguments.contains("-demoMusic"), !music.isPlaying {
                music.play()
            }
        }
        .sheet(isPresented: $showTimer) {
            TimerSheet().presentationDetents([.medium]).presentationBackground(Theme.indigoDeep)
        }
        .alert(loc.t("Nom du mélange", "Mix name"), isPresented: $showSave) {
            TextField(loc.t("Ma nuit", "My night"), text: $newName)
            Button(loc.t("Enregistrer", "Save")) { saveMix() }
            Button(loc.t("Annuler", "Cancel"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc.t("Sons", "Soundscapes"))
                    .font(.quietSerif(30)).foregroundStyle(Theme.moonlight)
                Text(loc.t("Compose ta nuit, couche par couche.",
                           "Compose your night, layer by layer."))
                    .font(.quietRounded(13)).foregroundStyle(Theme.mist)
            }
            Spacer()
            Button { showTimer = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    if sleepTimer.isActive {
                        Text(sleepTimer.clockString).font(.quietRounded(13, .medium))
                    }
                }
                .foregroundStyle(sleepTimer.isActive ? Theme.amber : Theme.mutedFar)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Theme.panel.opacity(0.7)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Generative music

    /// The "Musique" card — a generative composer in the spirit of brain.fm /
    /// Endel: pick a program, and the music evolves endlessly, breathes with the
    /// active pacer, and winds down with the sleep timer.
    private var musicCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(music.isPlaying ? Theme.amber : Theme.mutedFar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.t("Musique générative", "Generative music"))
                        .font(.quietRounded(15, .medium)).foregroundStyle(Theme.moonlight)
                    Text(loc.t(music.program.descFR, music.program.descEN))
                        .font(.quietRounded(12)).foregroundStyle(Theme.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    syncBreathPeriod()
                    music.toggle()
                } label: {
                    Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(music.isPlaying ? Theme.amber : Theme.amberDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(music.isPlaying ? loc.t("Pause", "Pause") : loc.t("Jouer", "Play"))
            }

            // Program chips.
            HStack(spacing: 8) {
                ForEach(MusicProgram.allCases) { prog in
                    let on = music.program == prog
                    Button {
                        music.program = prog
                        syncBreathPeriod()
                        if music.isPlaying { music.nudge() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: prog.symbol).font(.system(size: 12))
                            Text(loc.t(prog.nameFR, prog.nameEN)).font(.quietRounded(13, .medium))
                        }
                        .foregroundStyle(on ? Theme.ground : Theme.mist)
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(Capsule().fill(on ? Theme.amber : Theme.panelHi))
                    }
                    .buttonStyle(.plain)
                }
            }

            if music.isPlaying {
                musicSlider(loc.t("Intensité", "Intensity"), "dial.low",
                            value: Binding(get: { music.intensity },
                                           set: { music.intensity = $0; music.nudge() }))
                musicSlider(loc.t("Complexité", "Complexity"), "circle.hexagongrid",
                            value: Binding(get: { music.complexity },
                                           set: { music.complexity = $0; music.nudge() }))
                musicSlider(loc.t("Pulsation", "Pulse"), "waveform.path",
                            value: Binding(get: { music.pulse },
                                           set: { music.pulse = $0; music.nudge() }))

                Text(loc.t("Espace de la mélodie", "Melody space"))
                    .font(.quietRounded(11, .medium)).foregroundStyle(Theme.mutedFar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                musicSlider(loc.t("Écho", "Echo"), "arrow.triangle.2.circlepath",
                            value: Binding(get: { music.echo },
                                           set: { music.echo = $0; music.nudge() }))
                musicSlider(loc.t("Réverbération", "Reverb"), "drop",
                            value: Binding(get: { music.reverb },
                                           set: { music.reverb = $0; music.nudge() }))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.panel.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(music.isPlaying ? Theme.amberDeep.opacity(0.45) : Theme.line.opacity(0.5), lineWidth: 1))
        )
    }

    private func musicSlider(_ title: String, _ symbol: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15))
                .foregroundStyle(Theme.mutedFar).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.quietRounded(12, .medium)).foregroundStyle(Theme.mist)
                Slider(value: value, in: 0...1).tint(Theme.amberDeep)
            }
        }
    }

    /// Keep the generative pulse locked to the user's chosen breath pattern.
    private func syncBreathPeriod() {
        music.breathCyclePeriod = BreathPattern.by(id: settings.defaultBreathPatternID).cycleDuration
    }

    private var savedMixes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mixes) { mix in
                    Button { apply(mix) } label: {
                        Text(mix.name)
                            .font(.quietRounded(13, .medium))
                            .foregroundStyle(Theme.moonlight)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Theme.panelHi))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            ctx.delete(mix); try? ctx.save()
                        } label: { Label(loc.t("Supprimer", "Delete"), systemImage: "trash") }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func layerRow(_ layer: SoundLayer) -> some View {
        let v = Binding<Double>(
            get: { engine.volumes[layer] ?? 0 },
            set: { engine.setVolume($0, for: layer) }
        )
        let active = (engine.volumes[layer] ?? 0) > 0.001
        return HStack(spacing: 14) {
            Image(systemName: layer.symbol)
                .font(.system(size: 19))
                .foregroundStyle(active ? Theme.amber : Theme.mutedFar)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t(layer.nameFR, layer.nameEN))
                    .font(.quietRounded(15, .medium))
                    .foregroundStyle(active ? Theme.moonlight : Theme.mist)
                Slider(value: v, in: 0...1)
                    .tint(Theme.amberDeep)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panel.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(active ? Theme.amberDeep.opacity(0.4) : Theme.line.opacity(0.5), lineWidth: 1))
        )
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                newName = ""
                showSave = true
            } label: {
                Label(loc.t("Enregistrer le mélange", "Save mix"), systemImage: "heart")
                    .font(.quietRounded(14, .medium))
                    .foregroundStyle(Theme.moonlight)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panelHi))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)

            Button {
                engine.stopAll()
                music.stop()
            } label: {
                Label(loc.t("Silence", "Silence"), systemImage: "speaker.slash")
                    .font(.quietRounded(14, .medium))
                    .foregroundStyle(Theme.mist)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel.opacity(0.6)))
            }
            .buttonStyle(.plain)
        }
    }

    /// A mix is worth saving if any ambient layer is up OR generative music is on.
    private var canSave: Bool { engine.anyActive || music.isPlaying }

    private func apply(_ mix: SavedMix) {
        var dict: [SoundLayer: Double] = [:]
        for (k, val) in mix.volumes {
            if let layer = SoundLayer(rawValue: k) { dict[layer] = val }
        }
        engine.apply(mix: dict)

        // Recall the generative-music scene, if the mix saved one.
        if let raw = mix.musicProgram, let prog = MusicProgram(rawValue: raw) {
            music.intensity = mix.musicIntensity
            music.pulse = mix.musicPulse
            music.complexity = mix.musicComplexity
            music.echo = mix.musicEcho
            music.reverb = mix.musicReverb
            syncBreathPeriod()
            music.play(prog)
        } else {
            music.stop()
        }
    }

    private func saveMix() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? loc.t("Mélange", "Mix") : name
        var dict: [String: Double] = [:]
        for layer in SoundLayer.allCases where (engine.volumes[layer] ?? 0) > 0.001 {
            dict[layer.rawValue] = engine.volumes[layer] ?? 0
        }
        ctx.insert(SavedMix(name: finalName, volumes: dict,
                            musicProgram: music.isPlaying ? music.program.rawValue : nil,
                            musicIntensity: music.intensity,
                            musicPulse: music.pulse,
                            musicComplexity: music.complexity,
                            musicEcho: music.echo,
                            musicReverb: music.reverb))
        try? ctx.save()
    }
}
