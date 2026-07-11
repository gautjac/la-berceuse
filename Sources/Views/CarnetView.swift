import SwiftUI
import SwiftData

/// Le carnet de nuit — a quiet page connecting the last two weeks of rituals to
/// the sleep HealthKit reports. Observations, not a dashboard: one headline
/// number, a soft sparkline, a couple of sentences.
struct CarnetView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RitualSession.startedAt, order: .reverse) private var sessions: [RitualSession]

    @State private var nights: [NightRecord] = []
    @State private var loaded = false

    private var insights: CarnetInsights {
        let cutoff = Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date()
        let recent = sessions.filter { $0.startedAt > cutoff }
            .map { (kind: $0.kind, startedAt: $0.startedAt) }
        return CarnetMath.insights(nights: nights, sessions: recent)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !loaded {
                        ProgressView().tint(Theme.amber).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if nights.isEmpty {
                        emptyState
                    } else {
                        content(insights)
                    }
                }
                .padding(22)
            }
            .background(Theme.indigoDeep)
            .navigationTitle(loc.t("Carnet de nuit", "Night journal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc.t("Fermer", "Close")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            nights = await SleepHealth.shared.nights(last: 14)
            loaded = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars").font(.system(size: 34)).foregroundStyle(Theme.mutedFar)
            Text(loc.t("Pas encore de nuits à raconter.", "No nights to tell yet."))
                .font(.quietSerif(20)).foregroundStyle(Theme.moonlight)
            Text(loc.t("Quand Santé aura quelques nuits de sommeil, ton carnet s'écrira ici.",
                       "Once Health has a few nights of sleep, your journal will write itself here."))
                .font(.quietRounded(13)).foregroundStyle(Theme.mist)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    @ViewBuilder
    private func content(_ ins: CarnetInsights) -> some View {
        // Headline: the ritual effect, when there's enough signal.
        if ins.ritualNightCount >= 2, abs(ins.ritualGainMinutes) >= 5 {
            let gain = Int(abs(ins.ritualGainMinutes).rounded())
            card(icon: "sparkles",
                 title: ins.ritualGainMinutes >= 0
                    ? loc.t("Les soirs de rituel, tu dors \(gain) min de plus.",
                            "On ritual nights, you sleep \(gain) more minutes.")
                    : loc.t("Les soirs de rituel, tu dors \(gain) min de moins — les nuits difficiles appellent le rituel.",
                            "Ritual nights run \(gain) minutes shorter — hard nights are when you reach for it."),
                 detail: loc.t("\(ins.ritualNightCount) nuits avec rituel · \(ins.nightCount) nuits observées",
                               "\(ins.ritualNightCount) ritual nights · \(ins.nightCount) nights observed"))
        }

        sparkline(ins)

        card(icon: "moon.zzz",
             title: loc.t(String(format: "En moyenne : %.1f h de sommeil.", ins.averageHours),
                          String(format: "On average: %.1f h of sleep.", ins.averageHours)),
             detail: loc.t("Sur les 14 dernières nuits.", "Across the last 14 nights."))

        if ins.currentStreak >= 2 {
            card(icon: "flame",
                 title: loc.t("\(ins.currentStreak) soirs de rituel d'affilée.",
                              "\(ins.currentStreak) ritual evenings in a row."),
                 detail: loc.t("Doucement, ça devient une habitude.", "Quietly becoming a habit."))
        }

        if let fav = ins.favouriteKind {
            let name = kindName(fav)
            card(icon: "heart",
                 title: loc.t("Ton compagnon de nuit : \(name).", "Your night companion: \(name)."),
                 detail: loc.t("Le rituel que tu choisis le plus souvent.", "The ritual you reach for most."))
        }
    }

    private func kindName(_ kind: String) -> String {
        switch kind {
        case "breath":  return loc.t("le souffle", "breathing")
        case "shuffle": return loc.t("le brouillage", "the shuffle")
        case "nidra":   return loc.t("le repos profond", "deep rest")
        case "ritual":  return loc.t("les rituels", "rituals")
        default:        return loc.t("les sons", "sounds")
        }
    }

    private func sparkline(_ ins: CarnetInsights) -> some View {
        let maxH = max(ins.bars.map(\.asleepHours).max() ?? 8, 8)
        return VStack(alignment: .leading, spacing: 10) {
            Text(loc.t("Les nuits, une à une", "Night by night"))
                .font(.quietRounded(12, .medium)).foregroundStyle(Theme.mutedFar)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(ins.bars.enumerated()), id: \.offset) { _, n in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.amberDeep.opacity(0.55))
                        .frame(height: max(6, 72 * n.asleepHours / maxH))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel.opacity(0.7)))
    }

    private func card(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.amber)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.quietSerif(19)).foregroundStyle(Theme.moonlight)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.quietRounded(12)).foregroundStyle(Theme.mist)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel.opacity(0.7)))
    }
}
