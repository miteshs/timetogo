import Foundation
import AVFoundation

/// Speaks prompts and confirmations aloud (on-device, no network). Uses
/// AVSpeechSynthesizer; a slightly slower rate aids comprehension.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private init() {}

    private let synthesizer = AVSpeechSynthesizer()

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

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
