import Foundation
import Speech
import AVFoundation

/// On-device speech recognition for the tiny command vocabulary, built on the
/// iOS 26 `SpeechAnalyzer` / `SpeechTranscriber` API.
///
/// Why this backend: the legacy `SFSpeechRecognizer` fails to initialize in the
/// Simulator (its Siri "understanding" asset isn't provisioned). `SpeechAnalyzer`
/// uses a separate, downloadable model pipeline (`AssetInventory`) that works in
/// the Simulator and on device, runs fully on-device, and is Apple's current
/// recommended engine.
///
/// TIMING (accessibility-critical): a long "no speech yet" window lets the user
/// take his time to begin; a short pause-timeout only starts *after* speech is
/// detected, so he is never cut off mid-sentence.
@MainActor
@Observable
final class VoiceEngine {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case denied
        case unavailable
    }

    var state: State = .idle
    var transcript: String = ""
    var heardSpeech: Bool = false
    var lastErrorText: String?

    private let locale = Locale(identifier: "en-US")
    private let audioEngine = AVAudioEngine()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?

    private var startTimer: Timer?
    private var endpointTimer: Timer?
    private var onFinal: ((String) -> Void)?
    private var finishing = false

    /// Log which transcription locales the OS has available/installed — decisive
    /// for telling whether on-device speech is possible in this environment.
    static func logAssetDiagnostics() async {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        print("[VoiceEngine] supportedLocales(\(supported.count)): \(supported.map { $0.identifier(.bcp47) })")
        print("[VoiceEngine] installedLocales(\(installed.count)): \(installed.map { $0.identifier(.bcp47) })")
    }

    /// Ask for microphone (and speech) permission. Call before `start`.
    static func requestPermissions() async -> Bool {
        let micAuthorized = await AVAudioApplication.requestRecordPermission()
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        return micAuthorized
    }

    func start(
        hints: [String] = IntentParser.commandHints,
        startWindow: TimeInterval = 12,
        endpointSilence: TimeInterval = 2.5,
        onFinal: @escaping (String) -> Void
    ) {
        stop()
        self.onFinal = onFinal
        transcript = ""
        heardSpeech = false
        lastErrorText = nil
        finishing = false
        state = .preparing

        sessionTask = Task { await runSession(startWindow: startWindow, endpointSilence: endpointSilence) }
    }

    private func runSession(startWindow: TimeInterval, endpointSilence: TimeInterval) async {
        do {
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            self.transcriber = transcriber

            // Reserve (subscribe to) the locale first — the asset system won't
            // report or perform the model download otherwise ("not subscribed to
            // transcription.en"). Then install the on-device model if needed
            // (first run downloads it; later runs return nil).
            let reserved = (try? await AssetInventory.reserve(locale: locale)) ?? false
            print("[VoiceEngine] reserve(en-US) = \(reserved)")
            if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                print("[VoiceEngine] downloading speech model…")
                try await installRequest.downloadAndInstall()
                print("[VoiceEngine] speech model installed")
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw NSError(domain: "VoiceEngine", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "No compatible audio format for the transcriber."])
            }

            let (inputStream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputContinuation = continuation

            // Consume transcription results: keep the latest text, reset the
            // pause timer as words arrive.
            resultsTask = Task { @MainActor in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            self.transcript = text
                            self.heardSpeech = true
                            self.armEndpointTimer(endpointSilence)
                        }
                    }
                } catch {
                    self.lastErrorText = (error as NSError).localizedDescription
                    print("[VoiceEngine] results error: \(error)")
                }
            }

            try startAudioCapture(to: continuation, analyzerFormat: analyzerFormat)
            try await analyzer.start(inputSequence: inputStream)

            state = .listening
            print("[VoiceEngine] listening via SpeechAnalyzer (format \(analyzerFormat.sampleRate)Hz)")

            // Generous window to BEGIN talking; if nothing is heard, finish empty.
            startTimer = Timer.scheduledTimer(withTimeInterval: startWindow, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.heardSpeech else { return }
                    await self.finish()
                }
            }
        } catch {
            lastErrorText = "Voice setup failed: \((error as NSError).localizedDescription)"
            print("[VoiceEngine] setup error: \(error)")
            state = .unavailable
            await finish()
        }
    }

    private func startAudioCapture(to continuation: AsyncStream<AnalyzerInput>.Continuation,
                                   analyzerFormat: AVAudioFormat) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "VoiceEngine", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input (\(inputFormat.sampleRate)Hz). Check the simulator/Mac mic."])
        }

        let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        inputNode.removeTap(onBus: 0)
        // Capture plain locals so the real-time audio thread doesn't touch the actor.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converter else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var convError: NSError?
            converter.convert(to: outBuffer, error: &convError) { _, statusPtr in
                if consumed { statusPtr.pointee = .noDataNow; return nil }
                consumed = true
                statusPtr.pointee = .haveData
                return buffer
            }
            if outBuffer.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: outBuffer))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Once he's speaking, finalize a short pause after he stops — but only then.
    private func armEndpointTimer(_ seconds: TimeInterval) {
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate()
        endpointTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.finish() }
        }
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true

        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate(); endpointTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()

        // Flush remaining audio into a final transcript.
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()

        let result = transcript
        let callback = onFinal
        onFinal = nil
        teardown()
        callback?(result)
    }

    private func teardown() {
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        if state == .listening || state == .preparing { state = .idle }
    }

    /// Cancel any in-flight session without delivering a result.
    func stop() {
        onFinal = nil
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate(); endpointTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()
        resultsTask?.cancel()
        sessionTask?.cancel()
        teardown()
        if state != .denied && state != .unavailable { state = .idle }
    }
}
