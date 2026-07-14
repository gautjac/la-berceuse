import Foundation
import AVFoundation

/// A soft, slow on-device voice for the cognitive shuffle words and the NSDR
/// scripts. Wraps AVSpeechSynthesizer with sleep-friendly defaults (slow rate,
/// slightly lowered pitch, gentle volume) and routes through the shared
/// `.playback` session so it mixes with the soundscape and plays under lock.
///
/// Voice quality: prefers a downloaded **Premium** voice, then **Enhanced**,
/// then the default compact voice. The user can pick a specific voice per
/// language (incl. Québec French `fr-CA` and an iOS 17 **Personal Voice**) and
/// tune the warmth (rate/pitch) in Settings — stored in `@AppStorage` and read
/// here at speak time.
@MainActor
public final class Narrator: NSObject, ObservableObject {
    public static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    @Published public private(set) var isSpeaking = false

    // @AppStorage keys (kept in sync with SettingsView).
    nonisolated public static func voiceKey(_ lang: Lang) -> String { "berceuse.voiceID.\(lang == .fr ? "fr" : "en")" }
    nonisolated public static let rateKey  = "berceuse.voiceRate"
    nonisolated public static let pitchKey = "berceuse.voicePitch"
    nonisolated public static let defaultRate: Double  = 0.38
    nonisolated public static let defaultPitch: Double = 0.92

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak a single word/line very softly and slowly. `rate`/`pitch` default to
    /// the user's stored warmth settings when omitted.
    public func speak(_ text: String, lang: Lang,
                      rate: Float? = nil, pitch: Float? = nil, volume: Float = 0.7) {
        guard !text.isEmpty else { return }
        // Screenshot rig: voice loading can stall a fresh simulator (the EN
        // voice on iPad hangs the main actor), so demo runs can silence it.
        guard !ProcessInfo.processInfo.arguments.contains("-demoNoSpeech") else { return }
        let d = UserDefaults.standard
        let storedRate  = (d.object(forKey: Self.rateKey)  as? Double) ?? Self.defaultRate
        let storedPitch = (d.object(forKey: Self.pitchKey) as? Double) ?? Self.defaultPitch

        let u = AVSpeechUtterance(string: text)
        u.voice = resolveVoice(for: lang)
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, rate ?? Float(storedRate))
        u.pitchMultiplier = pitch ?? Float(storedPitch)
        u.volume = volume
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        synth.speak(u)
    }

    public func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Resolve the voice to use: the user's chosen voice for this language if it's
    /// set and still installed, otherwise the best automatic pick.
    private func resolveVoice(for lang: Lang) -> AVSpeechSynthesisVoice? {
        let chosen = UserDefaults.standard.string(forKey: Self.voiceKey(lang)) ?? ""
        if !chosen.isEmpty, let v = AVSpeechSynthesisVoice(identifier: chosen) { return v }
        return Self.bestVoice(for: lang)
    }

    /// Best automatic voice for a language: Premium → Enhanced → default.
    public static func bestVoice(for lang: Lang) -> AVSpeechSynthesisVoice? {
        let prefix = String(lang.voiceLanguage.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !isNovelty($0) }
        func pick(_ q: AVSpeechSynthesisVoiceQuality) -> AVSpeechSynthesisVoice? {
            voices.first { $0.quality == q }
        }
        return pick(.premium) ?? pick(.enhanced)
            ?? AVSpeechSynthesisVoice(language: lang.voiceLanguage) ?? voices.first
    }

    /// Voices offered in the Settings picker for a language, best quality first,
    /// plus any iOS 17 Personal Voices (which can be used in any language).
    public static func voiceChoices(for lang: Lang) -> [VoiceChoice] {
        let prefix = String(lang.voiceLanguage.prefix(2))
        let all = AVSpeechSynthesisVoice.speechVoices()
        let matching = all
            .filter { $0.language.hasPrefix(prefix) && !isNovelty($0) }
            .sorted {
                $0.quality.berceuseRank != $1.quality.berceuseRank
                    ? $0.quality.berceuseRank < $1.quality.berceuseRank
                    : $0.name < $1.name
            }
        var out = matching.map { v in
            VoiceChoice(id: v.identifier,
                        label: "\(v.name) · \(v.language) · \(qualityLabel(v.quality, lang: lang))")
        }
        if #available(iOS 17.0, *) {
            let personal = all.filter { $0.voiceTraits.contains(.isPersonalVoice) }
            out += personal.map { v in
                VoiceChoice(id: v.identifier,
                            label: "\(v.name) · \(lang == .fr ? "Voix personnelle" : "Personal Voice")")
            }
        }
        return out
    }

    /// True if at least one Enhanced/Premium voice is installed for the language.
    public static func hasHighQualityVoice(for lang: Lang) -> Bool {
        let prefix = String(lang.voiceLanguage.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices().contains {
            $0.language.hasPrefix(prefix) && ($0.quality == .enhanced || $0.quality == .premium)
        }
    }

    /// Ask for Personal Voice access so those voices appear in the picker (iOS 17+).
    public func requestPersonalVoiceIfPossible() {
        if #available(iOS 17.0, *) {
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in }
        }
    }

    private static func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality, lang: Lang) -> String {
        switch q {
        case .premium:  return "Premium"
        case .enhanced: return lang == .fr ? "Améliorée" : "Enhanced"
        default:        return lang == .fr ? "Standard" : "Standard"
        }
    }

    /// Filter out Apple's "novelty" voices (Bubbles, Bad News, etc.) that clutter
    /// the en-US list and are useless for a bedtime app.
    private static func isNovelty(_ v: AVSpeechSynthesisVoice) -> Bool {
        v.identifier.contains(".speech.synthesis.voice.") == false
            ? false
            : noveltyNames.contains(v.name)
    }
    private static let noveltyNames: Set<String> = [
        "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos",
        "Good News", "Jester", "Organ", "Superstar", "Trinoids", "Whisper",
        "Wobble", "Zarvox"
    ]
}

public struct VoiceChoice: Identifiable, Hashable {
    public let id: String
    public let label: String
}

private extension AVSpeechSynthesisVoiceQuality {
    var berceuseRank: Int {
        switch self {
        case .premium:  return 0
        case .enhanced: return 1
        default:        return 2
        }
    }
}

extension Narrator: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated public func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated public func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
