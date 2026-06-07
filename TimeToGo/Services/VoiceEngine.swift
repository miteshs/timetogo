import Foundation
import Speech
import AVFoundation

/// On-device speech recognition for the tiny command vocabulary.
///
/// IMPLEMENTATION NOTE
/// -------------------
/// The plan names Apple's iOS 26 `SpeechTranscriber` as the default. This file
/// ships the **`SFSpeechRecognizer` on-device** backend instead, on purpose:
///   • it is a stable API this codebase can be authored against with confidence
///     before Xcode is installed (SpeechTranscriber couldn't be compiler-checked
///     here);
///   • it runs fully on-device (`requiresOnDeviceRecognition = true`) — no
///     network, no large download;
///   • it supports **contextual strings** (our command words), which measurably
///     improves accuracy on atypical speech — exactly our use case.
/// Swapping in `SpeechTranscriber` (or WhisperKit, behind the Settings toggle)
/// is the Phase-6 on-device tuning step; keep this type's surface stable so the
/// backend can change without touching the views.
@MainActor
@Observable
final class VoiceEngine {

    enum State: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    var state: State = .idle
    var transcript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var onFinal: ((String) -> Void)?

    /// Ask for speech + microphone permission. Call before `start`.
    static func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micAuthorized = await AVAudioApplication.requestRecordPermission()
        return speechAuthorized && micAuthorized
    }

    /// Begin listening. `onFinal` fires once with the best transcript when the
    /// user stops talking (or recognition finalizes/errs).
    func start(hints: [String] = IntentParser.commandHints, onFinal: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }
        stop()
        self.onFinal = onFinal
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = hints
        request.addsPunctuation = false
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = .unavailable
            return
        }
        state = .listening

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal { self.finish() }
                }
                if error != nil { self.finish() }
            }
        }
        resetSilenceTimer()
    }

    /// Auto-finish after a short pause so the user needn't tap anything.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func finish() {
        let final = transcript
        let callback = onFinal
        onFinal = nil
        stop()
        callback?(final)
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if state == .listening { state = .idle }
    }
}
