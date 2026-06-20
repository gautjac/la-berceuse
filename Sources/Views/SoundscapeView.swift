import SwiftUI
import SwiftData

/// The generative soundscape mixer: each layer has its own volume slider,
/// saved mixes recall a whole scene, and a sleep-timer chip arms the fade-out.
struct SoundscapeView: View {
    @EnvironmentObject var loc: LocManager
    @EnvironmentObject var sleepTimer: SleepTimerController
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavedMix.createdAt, order: .reverse) private var mixes: [SavedMix]

    @StateObject private var engine = SoundEngine.shared
    @State private var showSave = false
    @State private var newName = ""
    @State private var showTimer = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                if !mixes.isEmpty { savedMixes }

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
            .disabled(!engine.anyActive)
            .opacity(engine.anyActive ? 1 : 0.4)

            Button { engine.stopAll() } label: {
                Label(loc.t("Silence", "Silence"), systemImage: "speaker.slash")
                    .font(.quietRounded(14, .medium))
                    .foregroundStyle(Theme.mist)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel.opacity(0.6)))
            }
            .buttonStyle(.plain)
        }
    }

    private func apply(_ mix: SavedMix) {
        var dict: [SoundLayer: Double] = [:]
        for (k, val) in mix.volumes {
            if let layer = SoundLayer(rawValue: k) { dict[layer] = val }
        }
        engine.apply(mix: dict)
    }

    private func saveMix() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? loc.t("Mélange", "Mix") : name
        var dict: [String: Double] = [:]
        for layer in SoundLayer.allCases where (engine.volumes[layer] ?? 0) > 0.001 {
            dict[layer.rawValue] = engine.volumes[layer] ?? 0
        }
        ctx.insert(SavedMix(name: finalName, volumes: dict))
        try? ctx.save()
    }
}
