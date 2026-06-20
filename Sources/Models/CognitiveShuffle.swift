import Foundation

/// The cognitive shuffle ("brouillage cognitif" / "serial diverse imagining"),
/// a sleep-onset technique researched by Dr Luc Beaudoin. You imagine a slow
/// stream of unrelated, emotionally-neutral words; the mind's attempt to make
/// each one concrete, then dropping it for the next, mimics the incoherent
/// micro-dreams of sleep onset and blocks rumination.
///
/// This generator produces a deterministic-but-varied stream from a curated
/// neutral-noun word bank, in FR or EN. Determinism (seedable RNG) makes the
/// timing/sequence math fully testable; the seed defaults to the wall clock so
/// each real session differs.
public struct CognitiveShuffle {

    /// A small, fast, seedable PRNG (SplitMix64) so sequences are reproducible
    /// in tests yet varied in production.
    public struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        public init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        public mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    public let lang: Lang
    private var rng: SeededRNG
    /// A shuffled deck we draw from; reshuffled (without immediate repeats) when
    /// exhausted, so the stream never repeats a word until the bank cycles.
    private var deck: [String]
    private var index: Int = 0
    private var lastWord: String?

    public init(lang: Lang, seed: UInt64? = nil) {
        self.lang = lang
        self.rng = SeededRNG(seed: seed ?? UInt64(Date().timeIntervalSince1970 * 1000))
        var bank = lang == .fr ? Self.bankFR : Self.bankEN
        bank.shuffle(using: &self.rng)
        self.deck = bank
    }

    /// The next neutral word in the stream.
    public mutating func next() -> String {
        if index >= deck.count {
            // Reshuffle for another pass.
            deck.shuffle(using: &rng)
            index = 0
            // Avoid an immediate repeat across the seam.
            if let last = lastWord, deck.first == last, deck.count > 1 {
                deck.swapAt(0, 1)
            }
        }
        let word = deck[index]
        index += 1
        lastWord = word
        return word
    }

    /// Produce a stream of `count` words (used in tests and for previews).
    public mutating func stream(_ count: Int) -> [String] {
        (0..<count).map { _ in next() }
    }

    /// The size of the active word bank.
    public var bankSize: Int { deck.count }

    // MARK: - Word banks (concrete, emotionally-neutral nouns)

    /// French neutral nouns — concrete, sleep-safe, no charged content.
    public static let bankFR: [String] = [
        "pomme", "rivière", "fenêtre", "tabouret", "nuage", "crayon", "lanterne",
        "biscuit", "sentier", "horloge", "écharpe", "galet", "bougie", "panier",
        "feuille", "ruban", "tasse", "ancre", "voile", "tambour", "miel",
        "échelle", "plume", "coquille", "moulin", "violon", "brouette", "noisette",
        "lampe", "barque", "jardin", "tuile", "carafe", "balcon", "muraille",
        "clé", "ardoise", "épine", "tonneau", "saule", "phare", "radeau",
        "grenier", "marteau", "ruisseau", "cabane", "girouette", "boussole",
        "édredon", "oreiller", "couverture", "berceau", "veilleuse", "ourson",
        "sablier", "carrousel", "lucarne", "pelote", "navette", "brindille",
        "mésange", "hérisson", "renard", "loutre", "chouette", "libellule",
        "marguerite", "lavande", "fougère", "mousse", "champignon", "noyau",
        "ardoisière", "comète", "planète", "dune", "lagune", "estuaire",
        "wagon", "quai", "pont", "tunnel", "balise", "fanal", "amarre",
    ]

    /// English neutral nouns — concrete, sleep-safe.
    public static let bankEN: [String] = [
        "apple", "river", "window", "stool", "cloud", "pencil", "lantern",
        "biscuit", "trail", "clock", "scarf", "pebble", "candle", "basket",
        "leaf", "ribbon", "cup", "anchor", "sail", "drum", "honey",
        "ladder", "feather", "shell", "windmill", "violin", "barrow", "hazelnut",
        "lamp", "rowboat", "garden", "tile", "carafe", "balcony", "wall",
        "key", "slate", "thorn", "barrel", "willow", "lighthouse", "raft",
        "attic", "hammer", "brook", "cabin", "weathervane", "compass",
        "quilt", "pillow", "blanket", "cradle", "nightlight", "teddy",
        "hourglass", "carousel", "skylight", "yarn", "shuttle", "twig",
        "sparrow", "hedgehog", "fox", "otter", "owl", "dragonfly",
        "daisy", "lavender", "fern", "moss", "mushroom", "kernel",
        "quarry", "comet", "planet", "dune", "lagoon", "estuary",
        "wagon", "platform", "bridge", "tunnel", "buoy", "beacon", "mooring",
    ]
}
