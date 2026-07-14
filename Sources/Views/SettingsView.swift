import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var settingsRows: [Settings]
    @Query(sort: \RitualSession.startedAt, order: .reverse) private var history: [RitualSession]

    @AppStorage("berceuse.voiceID.fr") private var voiceIDfr = ""
    @AppStorage("berceuse.voiceID.en") private var voiceIDen = ""
    @AppStorage(Narrator.rateKey) private var voiceRate = Narrator.defaultRate
    @AppStorage(Narrator.pitchKey) private var voicePitch = Narrator.defaultPitch

    private var activeVoiceID: Binding<String> {
        Binding(
            get: { loc.lang == .fr ? voiceIDfr : voiceIDen },
            set: { if loc.lang == .fr { voiceIDfr = $0 } else { voiceIDen = $0 } }
        )
    }

    private var settings: Settings {
        if let s = settingsRows.first { return s }
        let s = Settings(); ctx.insert(s); return s
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    section(loc.t("Langue", "Language")) {
                        Picker("", selection: Binding(
                            get: { loc.lang },
                            set: { loc.lang = $0 }
                        )) {
                            Text("Français").tag(Lang.fr)
                            Text("English").tag(Lang.en)
                        }
                        .pickerStyle(.segmented)
                    }

                    section(loc.t("Ambiance", "Ambience")) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("Pénombre", "Dimness"))
                                    .font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
                                Slider(value: Binding(
                                    get: { settings.dimLevel },
                                    set: { settings.dimLevel = $0; try? ctx.save() }
                                ), in: 0.25...1.0)
                                .tint(Theme.amberDeep)
                            }
                            toggle(loc.t("Tamiser automatiquement", "Auto-dim at night"),
                                   get: { settings.autoDim }, set: { settings.autoDim = $0 })
                        }
                    }

                    section(loc.t("Sensations", "Feedback")) {
                        VStack(spacing: 14) {
                            toggle(loc.t("Vibrations du souffle", "Breath haptics"),
                                   get: { settings.hapticsEnabled },
                                   set: { settings.hapticsEnabled = $0; Haptics.enabled = $0 })
                            toggle(loc.t("Voix douce (lecture des mots)", "Soft voice (spoken words)"),
                                   get: { settings.speechEnabled }, set: { settings.speechEnabled = $0 })
                        }
                    }

                    section(loc.t("Voix", "Voice")) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("Voix parlée", "Spoken voice"))
                                    .font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
                                Picker(selection: activeVoiceID) {
                                    Text(loc.t("Automatique (meilleure voix)", "Automatic (best voice)")).tag("")
                                    ForEach(Narrator.voiceChoices(for: loc.lang)) { c in
                                        Text(c.label).tag(c.id)
                                    }
                                } label: { EmptyView() }
                                .pickerStyle(.menu)
                                .tint(Theme.amber)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("Lenteur", "Slowness"))
                                    .font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
                                // Lower rate = slower; show as "slowness" so left = calmer.
                                Slider(value: Binding(
                                    get: { 0.50 - voiceRate },          // 0 (fast) … 0.20 (slowest)
                                    set: { voiceRate = 0.50 - $0 }
                                ), in: 0.02...0.20)
                                .tint(Theme.amberDeep)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(loc.t("Hauteur", "Pitch"))
                                    .font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
                                Slider(value: $voicePitch, in: 0.80...1.10)
                                    .tint(Theme.amberDeep)
                            }

                            Button {
                                Narrator.shared.speak(
                                    loc.t("Respire lentement… laisse la nuit venir.",
                                          "Breathe slowly… let the night come."),
                                    lang: loc.lang)
                            } label: {
                                Label(loc.t("Aperçu de la voix", "Preview voice"),
                                      systemImage: "speaker.wave.2.fill")
                                    .font(.quietRounded(14, .semibold))
                                    .foregroundStyle(Theme.amber)
                            }

                            if !Narrator.hasHighQualityVoice(for: loc.lang) {
                                Text(loc.t("Astuce : téléchargez une voix « Améliorée » ou « Premium » dans Réglages → Accessibilité → Contenu énoncé → Voix, puis choisissez-la ici.",
                                           "Tip: download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices, then pick it here."))
                                    .font(.quietRounded(11)).foregroundStyle(Theme.mutedFar)
                            }
                        }
                    }

                    if !history.isEmpty {
                        section(loc.t("Tes rituels", "Your rituals")) {
                            VStack(spacing: 10) {
                                ForEach(history.prefix(8)) { s in
                                    historyRow(s)
                                }
                            }
                        }
                    }

                    Text(loc.t("La Berceuse — entièrement hors-ligne. Bonne nuit.",
                               "La Berceuse — fully offline. Sleep well."))
                        .font(.quietRounded(11)).foregroundStyle(Theme.mutedFar)
                        .padding(.top, 8)

                    // The atelier signature — the house équerre, quiet as a
                    // colophon. Links out to the family's hub site.
                    Link(destination: URL(string: "https://atelier-jac.netlify.app")!) {
                        HStack(spacing: 9) {
                            Image("AtelierMark")
                                .resizable().scaledToFit()
                                .frame(width: 15, height: 15)
                            Text(loc.t("Une appli de L'Atelier", "An app from L'Atelier"))
                                .font(.quietRounded(11, .medium))
                        }
                        .foregroundStyle(Theme.mutedFar)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .onAppear { Narrator.shared.requestPersonalVoiceIfPossible() }
            .background(Theme.indigoDeep.ignoresSafeArea())
            .navigationTitle(loc.t("Réglages", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("OK", "Done")) { dismiss() }.tint(Theme.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.quietRounded(11, .semibold)).foregroundStyle(Theme.mutedFar)
                .padding(.leading, 4)
            content()
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel.opacity(0.7)))
        }
    }

    private func toggle(_ label: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: { set($0); try? ctx.save() })) {
            Text(label).font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
        }
        .tint(Theme.amberDeep)
    }

    private func historyRow(_ s: RitualSession) -> some View {
        let kindLabel: String = {
            switch s.kind {
            case "breath":  return loc.t("Souffle", "Breath")
            case "shuffle": return loc.t("Brouillage", "Shuffle")
            case "nidra":   return loc.t("Repos profond", "Deep rest")
            default:        return loc.t("Son", "Sound")
            }
        }()
        let mins = Int((s.duration / 60).rounded())
        return HStack {
            Text(kindLabel).font(.quietRounded(14)).foregroundStyle(Theme.moonlight)
            Spacer()
            Text("\(mins) min").font(.quietRounded(13)).foregroundStyle(Theme.mist)
            Text(s.startedAt.formatted(.dateTime.weekday(.abbreviated)))
                .font(.quietRounded(12)).foregroundStyle(Theme.mutedFar)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
