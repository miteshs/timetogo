import Foundation
import Speech
import AVFoundation
// WhisperKit's public types aren't marked Sendable yet; we only touch them on
// the main actor, so silence the (Swift-6-mode) concurrency warnings for now.
@preconcurrency import WhisperKit

/// On-device speech recognition for the tiny command vocabulary.
///
/// Two backends, same public surface (so the views never change):
/// - **Apple** (default): iOS 26 `SpeechAnalyzer` / `SpeechTranscriber`. Live
///   volatile results drive endpointing; no large download.
/// - **WhisperKit** (opt-in via `AppSettings.useWhisperKit`): captures the
///   utterance, endpoints with simple energy VAD, then batch-transcribes with a
///   local CoreML Whisper model (small.en). Better at atypical speech, but a
///   ~250 MB model downloads on first use.
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

    // Apple SpeechAnalyzer backend
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    // WhisperKit backend — model loaded once per app run and cached statically.
    private static let whisperModel = "openai_whisper-small.en"
    private static var whisper: WhisperKit?
    private static var whisperLoad: Task<WhisperKit, Error>?
    private var samples = SampleBuffer()
    private var hints: [String] = []

    private var sessionTask: Task<Void, Never>?
    private var startTimer: Timer?
    private var endpointTimer: Timer?
    private var maxUtteranceTimer: Timer?
    private var onFinal: ((String) -> Void)?
    private var finishing = false
    private var usingWhisper = false

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

    /// Load (and on first use, download) the WhisperKit model. Cached so repeated
    /// reminders reuse the same loaded model.
    @discardableResult
    static func loadWhisper() async throws -> WhisperKit {
        if let w = whisper { return w }
        if let t = whisperLoad { return try await t.value }
        let task = Task { () throws -> WhisperKit in
            // prewarm compiles the CoreML model at load time so the first
            // transcription isn't slow.
            let config = WhisperKitConfig(model: whisperModel, prewarm: true)
            return try await WhisperKit(config)
        }
        whisperLoad = task
        do {
            let w = try await task.value
            whisper = w
            return w
        } catch {
            whisperLoad = nil   // let a later attempt retry the download/load
            throw error
        }
    }

    /// True once the Whisper model is loaded (so the UI can skip the "preparing" copy).
    static var isWhisperReady: Bool { whisper != nil }

    func start(
        hints: [String] = IntentParser.commandHints,
        startWindow: TimeInterval = 12,
        endpointSilence: TimeInterval = 2.5,
        onFinal: @escaping (String) -> Void
    ) {
        stop()
        self.onFinal = onFinal
        self.hints = hints
        transcript = ""
        heardSpeech = false
        lastErrorText = nil
        finishing = false
        usingWhisper = AppSettings.shared.useWhisperKit
        state = .preparing

        if usingWhisper {
            sessionTask = Task { await runWhisperSession(startWindow: startWindow, endpointSilence: endpointSilence) }
        } else {
            sessionTask = Task { await runSession(startWindow: startWindow, endpointSilence: endpointSilence) }
        }
    }

    // MARK: - Apple SpeechAnalyzer backend

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

    /// Flush the analyzer into a final transcript and deliver it.
    private func finishAnalyzer() async {
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate(); endpointTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        inputContinuation?.finish()

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()

        let result = transcript
        let callback = onFinal
        onFinal = nil
        teardown()
        callback?(result)
    }

    // MARK: - WhisperKit backend

    private func runWhisperSession(startWindow: TimeInterval, endpointSilence: TimeInterval) async {
        do {
            try await Self.loadWhisper()   // downloads (~250 MB) + loads on first use
            samples = SampleBuffer()
            try startWhisperCapture(endpointSilence: min(endpointSilence, Self.whisperEndpointSilence))

            state = .listening
            print("[VoiceEngine] listening via WhisperKit (\(Self.whisperModel))")

            startTimer = Timer.scheduledTimer(withTimeInterval: startWindow, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.heardSpeech else { return }
                    await self.finish()
                }
            }
        } catch {
            lastErrorText = "Whisper setup failed: \((error as NSError).localizedDescription)"
            print("[VoiceEngine] whisper setup error: \(error)")
            state = .unavailable
            await finish()
        }
    }

    private func startWhisperCapture(endpointSilence: TimeInterval) throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "VoiceEngine", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input (\(inputFormat.sampleRate)Hz)."])
        }
        // Whisper wants 16 kHz mono float.
        guard let whisperFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                channels: 1, interleaved: false) else {
            throw NSError(domain: "VoiceEngine", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not build the 16 kHz capture format."])
        }
        let converter = AVAudioConverter(from: inputFormat, to: whisperFormat)
        inputNode.removeTap(onBus: 0)

        // Plain locals so the real-time audio thread never touches the actor.
        let sink = samples
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let converter else { return }
            let ratio = whisperFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var convError: NSError?
            converter.convert(to: out, error: &convError) { _, statusPtr in
                if consumed { statusPtr.pointee = .noDataNow; return nil }
                consumed = true
                statusPtr.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let channel = out.floatChannelData else { return }
            let count = Int(out.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: channel[0], count: count))

            // Energy VAD: once we hear speech, (re)arm the endpoint timer; the
            // utterance ends after `endpointSilence` of quiet.
            var sumSquares: Float = 0
            for sample in chunk { sumSquares += sample * sample }
            let rms = count > 0 ? (sumSquares / Float(count)).squareRoot() : 0
            sink.append(chunk, rms: rms)
            if rms > Self.speechRMSThreshold {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !self.heardSpeech {
                        self.heardSpeech = true
                        self.armMaxUtterance(Self.maxUtterance)   // guarantees we finish
                    }
                    self.armEndpointTimer(endpointSilence)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Stop capture and batch-transcribe the collected audio with WhisperKit.
    private func finishWhisper() async {
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate(); endpointTimer = nil
        maxUtteranceTimer?.invalidate(); maxUtteranceTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let peak = samples.peakRMS
        let audio = samples.drain()
        var text = ""
        // Transcribe only when we actually heard speech and have ~0.3 s+ of
        // audio (avoids Whisper hallucinating words on silence/noise).
        if heardSpeech, audio.count >= 16_000 / 3 {
            state = .preparing   // "thinking…"
            do {
                let wk = try await Self.loadWhisper()
                var options = DecodingOptions(task: .transcribe, language: "en")
                options.temperature = 0
                options.skipSpecialTokens = true
                options.withoutTimestamps = true
                let results = try await wk.transcribe(audioArray: audio, decodeOptions: options)
                // Whisper annotates non-speech as "[MUSIC PLAYING]", "(whooshing)",
                // "[BLANK_AUDIO]", etc. on quiet audio — strip those so they
                // aren't read as a command.
                text = results.map(\.text).joined(separator: " ")
                    .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
                print("[VoiceEngine] whisper heard: \"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\" (\(String(format: "%.1f", Double(audio.count) / 16_000))s audio, rms \(String(format: "%.2f", peak)))")
            } catch {
                lastErrorText = (error as NSError).localizedDescription
                print("[VoiceEngine] whisper transcribe error: \(error)")
            }
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = cleaned
        let callback = onFinal
        onFinal = nil
        teardown()
        callback?(cleaned)
    }

    // MARK: - Shared lifecycle

    private static let speechRMSThreshold: Float = 0.02
    // Commands are short ("I went", "snooze", "stop"); cap the capture so it
    // can't run on and mash multiple phrases into one transcript.
    private static let maxUtterance: TimeInterval = 5
    // Whisper transcribes in a batch, so a shorter end-of-speech pause keeps it
    // responsive (the Apple path can afford a longer one for live results).
    private static let whisperEndpointSilence: TimeInterval = 1.0

    /// Dispatch to whichever backend is running.
    private func finish() async {
        guard !finishing else { return }
        finishing = true
        if usingWhisper { await finishWhisper() } else { await finishAnalyzer() }
    }

    /// Hard cap once speech starts: guarantees the utterance ends even if the
    /// room never drops below the VAD threshold, so we always transcribe.
    private func armMaxUtterance(_ seconds: TimeInterval) {
        maxUtteranceTimer?.invalidate()
        maxUtteranceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.finish() }
        }
    }

    /// Once he's speaking, finalize a short pause after he stops — but only then.
    private func armEndpointTimer(_ seconds: TimeInterval) {
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate()
        endpointTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.finish() }
        }
    }

    private func teardown() {
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        _ = samples.drain()
        if state == .listening || state == .preparing { state = .idle }
    }

    /// Cancel any in-flight session without delivering a result.
    func stop() {
        onFinal = nil
        startTimer?.invalidate(); startTimer = nil
        endpointTimer?.invalidate(); endpointTimer = nil
        maxUtteranceTimer?.invalidate(); maxUtteranceTimer = nil
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

/// Thread-safe accumulator for audio samples captured on the real-time audio
/// thread and drained on the main actor.
private final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [Float] = []
    private var peak: Float = 0

    func append(_ chunk: [Float], rms: Float) {
        lock.lock(); data.append(contentsOf: chunk); if rms > peak { peak = rms }; lock.unlock()
    }

    var peakRMS: Float { lock.lock(); defer { lock.unlock() }; return peak }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let out = data
        data.removeAll(keepingCapacity: false)
        return out
    }
}
