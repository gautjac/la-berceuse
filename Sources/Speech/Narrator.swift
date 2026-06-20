import Foundation
import AVFoundation

/// A soft, slow on-device voice for the cognitive shuffle words and the NSDR
/// scripts. Wraps AVSpeechSynthesizer with sleep-friendly defaults (slow rate,
/// slightly lowered pitch, gentle volume) and routes through the shared
/// `.playback` session so it mixes with the soundscape and plays under lock.
@MainActor
public final class Narrator: NSObject, ObservableObject {
    public static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    @Published public private(set) var isSpeaking = false

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak a single word/line very softly and slowly.
    public func speak(_ text: String, lang: Lang,
                      rate: Float = 0.38, pitch: Float = 0.92, volume: Float = 0.7) {
        guard !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = bestVoice(for: lang)
        // AVSpeechUtteranceMinimumSpeechRate … keep it slow but intelligible.
        u.rate = max(AVSpeechUtteranceMinimumSpeechRate, rate)
        u.pitchMultiplier = pitch
        u.volume = volume
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0
        synth.speak(u)
    }

    public func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func bestVoice(for lang: Lang) -> AVSpeechSynthesisVoice? {
        let code = lang.voiceLanguage
        // Prefer an enhanced/premium voice if installed, else the default.
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(String(code.prefix(2))) }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: code) ?? voices.first
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
