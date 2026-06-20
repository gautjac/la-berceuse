import Foundation

/// A guided NSDR / yoga-nidra (repos profond / non-sleep deep rest) script:
/// a sequence of calm lines, revealed one at a time at a measured pace, and
/// optionally spoken by `Narrator`.
public struct NidraScript: Identifiable, Sendable {
    public let id: String
    public let titleFR: String
    public let titleEN: String
    public let subtitleFR: String
    public let subtitleEN: String
    /// Total intended duration in minutes (used for pacing the lines).
    public let minutes: Int
    public let linesFR: [String]
    public let linesEN: [String]

    public init(id: String, titleFR: String, titleEN: String,
                subtitleFR: String, subtitleEN: String, minutes: Int,
                linesFR: [String], linesEN: [String]) {
        self.id = id
        self.titleFR = titleFR
        self.titleEN = titleEN
        self.subtitleFR = subtitleFR
        self.subtitleEN = subtitleEN
        self.minutes = minutes
        self.linesFR = linesFR
        self.linesEN = linesEN
    }

    public func lines(_ lang: Lang) -> [String] { lang == .fr ? linesFR : linesEN }

    /// Seconds each line is held on screen so the whole script fills `minutes`.
    public func secondsPerLine(_ lang: Lang) -> Double {
        let n = max(1, lines(lang).count)
        return (Double(minutes) * 60.0) / Double(n)
    }

    // MARK: - Built-in scripts

    public static let bodyScan10 = NidraScript(
        id: "bodyscan10",
        titleFR: "Balayage du corps", titleEN: "Body scan",
        subtitleFR: "Dix minutes pour reposer chaque partie de toi.",
        subtitleEN: "Ten minutes to rest every part of you.",
        minutes: 10,
        linesFR: [
            "Installe-toi. Laisse le lit te porter entièrement.",
            "Ferme les yeux si tu le souhaites. Rien à faire, nulle part où aller.",
            "Sens le poids de ton corps qui s'enfonce doucement.",
            "Porte ton attention sur ton pied droit. Laisse-le devenir lourd.",
            "Maintenant ton pied gauche. Tout aussi lourd, tout aussi calme.",
            "Tes deux jambes, relâchées, comme posées sur du sable tiède.",
            "Ton bassin, ton dos. Chaque vertèbre se dépose une à une.",
            "Ton ventre monte et descend, sans effort.",
            "Ta main droite, puis ta main gauche. Les doigts se déplient.",
            "Tes épaules glissent loin de tes oreilles.",
            "Ta mâchoire se desserre. Ta langue repose.",
            "Le tour de tes yeux s'adoucit. Ton front se lisse.",
            "Tout ton corps est lourd, chaud, et parfaitement immobile.",
            "Reste ici, dans ce calme, aussi longtemps que tu veux.",
        ],
        linesEN: [
            "Settle in. Let the bed carry all of you.",
            "Close your eyes if you like. Nothing to do, nowhere to be.",
            "Feel the weight of your body sinking gently.",
            "Bring your attention to your right foot. Let it grow heavy.",
            "Now your left foot. Just as heavy, just as calm.",
            "Both legs, loosening, as if resting on warm sand.",
            "Your hips, your back. Each vertebra setting down, one by one.",
            "Your belly rises and falls, without effort.",
            "Your right hand, then your left. The fingers unfurl.",
            "Your shoulders slide away from your ears.",
            "Your jaw loosens. Your tongue rests.",
            "The skin around your eyes softens. Your forehead smooths.",
            "Your whole body is heavy, warm, and perfectly still.",
            "Stay here, in this calm, as long as you wish.",
        ]
    )

    public static let progressive20 = NidraScript(
        id: "progressive20",
        titleFR: "Détente progressive", titleEN: "Progressive relaxation",
        subtitleFR: "Vingt minutes : tendre, puis tout lâcher.",
        subtitleEN: "Twenty minutes: tense, then let everything go.",
        minutes: 20,
        linesFR: [
            "Allonge-toi confortablement. Laisse ta respiration ralentir d'elle-même.",
            "Inspire lentement par le nez… et laisse l'air repartir sans le pousser.",
            "Serre doucement les orteils des deux pieds. Tiens… et relâche.",
            "Sens la chaleur qui se répand dans tes pieds après le relâchement.",
            "Contracte tes mollets. Tiens un instant… et laisse-les fondre.",
            "Serre les cuisses. Remarque la tension… puis abandonne-la.",
            "Resserre légèrement le ventre. Tiens… et laisse-le s'ouvrir.",
            "Ferme les poings. Sens la force… puis ouvre les mains, paumes vers le ciel.",
            "Hausse les épaules vers les oreilles. Tiens… et laisse-les retomber.",
            "Plisse doucement le visage. Tiens… puis laisse chaque trait se détendre.",
            "Ton corps entier est maintenant relâché, du sommet du crâne aux talons.",
            "À chaque expiration, tu t'enfonces un peu plus dans le matelas.",
            "Imagine une lumière tiède et ambrée qui descend lentement en toi.",
            "Elle réchauffe ta poitrine, ton ventre, tes jambes.",
            "Il n'y a plus rien à tenir. Plus rien à porter.",
            "Ta respiration est lente, longue, régulière.",
            "Laisse les pensées passer comme des nuages, sans les suivre.",
            "Tu es en sécurité. Tu peux te reposer complètement.",
            "Reste dans ce repos profond, suspendu entre veille et sommeil.",
            "Et quand tu seras prêt, laisse simplement le sommeil venir.",
        ],
        linesEN: [
            "Lie down comfortably. Let your breath slow on its own.",
            "Breathe in slowly through the nose… and let the air leave without pushing it.",
            "Gently curl the toes of both feet. Hold… and release.",
            "Feel the warmth spreading through your feet after the release.",
            "Tense your calves. Hold for a moment… and let them melt.",
            "Squeeze your thighs. Notice the tension… then let it go.",
            "Lightly draw in your belly. Hold… and let it open.",
            "Make fists. Feel the strength… then open your hands, palms to the sky.",
            "Lift your shoulders toward your ears. Hold… and let them drop.",
            "Gently scrunch your face. Hold… then let every feature soften.",
            "Your whole body is now released, from the crown of your head to your heels.",
            "With each exhale, you sink a little deeper into the mattress.",
            "Picture a warm, amber light slowly moving down through you.",
            "It warms your chest, your belly, your legs.",
            "There is nothing left to hold. Nothing left to carry.",
            "Your breathing is slow, long, and even.",
            "Let thoughts drift by like clouds, without following them.",
            "You are safe. You can rest completely.",
            "Stay in this deep rest, suspended between waking and sleep.",
            "And when you are ready, simply let sleep come.",
        ]
    )

    public static let all: [NidraScript] = [bodyScan10, progressive20]
    public static func by(id: String) -> NidraScript {
        all.first { $0.id == id } ?? bodyScan10
    }
}
