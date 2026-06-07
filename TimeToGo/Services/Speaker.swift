import Foundation
import AVFoundation

/// Speaks prompts and confirmations aloud (on-device, no network). Uses
/// AVSpeechSynthesizer; a slightly slower rate aids comprehension. Supports a
/// completion callback so callers can wait until speaking finishes before
/// opening the microphone (avoids the prompt bleeding into recognition).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Configure a play-and-record session so TTS and the mic coexist.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try? session.setActive(true, options: [])
    }

    /// Speak `text`. `completion` runs when speaking finishes (or is cancelled).
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        // Replace any pending completion; only the latest utterance's matters.
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let done = self.completion
            self.completion = nil
            done?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.completion = nil }
    }
}
