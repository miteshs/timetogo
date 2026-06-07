import SwiftUI
import SwiftData

/// The screen shown when a reminder is tapped: it speaks the prompt, listens
/// for a spoken reply, and always offers three large buttons as a fallback.
struct ReminderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var voice = VoiceEngine()
    @State private var status = "Is it time to go?"
    @State private var didHandle = false
    @State private var didStartFlow = false
    @State private var voiceAttempts = 0
    @State private var typedAnswer = ""
    @State private var confettiTrigger = 0

    private let maxVoiceAttempts = 2
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        ZStack {
            GlassBackground()
            VStack(spacing: 24) {
                Spacer()

                micBadge

                Text(status)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if !voice.transcript.isEmpty {
                    Text("“\(voice.transcript)”")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if let err = voice.lastErrorText {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                #if targetEnvironment(simulator)
                // The Simulator has no on-device speech models, so type a reply to
                // exercise the same parse → handle flow. (Real voice works on device.)
                HStack {
                    TextField("Type a reply (sim test)", text: $typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { submitTyped() }
                    Button("Send") { submitTyped() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                #endif

                VStack(spacing: 14) {
                    bigButton("I went ✓", color: .green) { handle(.went, source: .button) }
                    bigButton("Snooze \(settings.defaultSnoozeMinutes) min", color: .orange) {
                        handle(.snooze(minutes: settings.defaultSnoozeMinutes), source: .button)
                    }
                    bigButton("Stop", color: .red) { handle(.stop, source: .button) }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

            ConfettiView(trigger: confettiTrigger)
        }
        .interactiveDismissDisabled(false)
        .task { await maybeStartFlow() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Cold launch from a notification: the sheet appears before the
                // app is foreground-active. Start once we actually are.
                Task { await maybeStartFlow() }
            } else {
                // Capturing audio off the foreground is forbidden — stop cleanly.
                voice.stop()
                Speaker.shared.stop()
            }
        }
        .onDisappear {
            voice.stop()
            Speaker.shared.stop()
        }
    }

    private var micBadge: some View {
        Image(systemName: voice.state == .listening ? "mic.fill" : "questionmark.circle")
            .font(.system(size: 50))
            .foregroundStyle(voice.state == .listening ? Color.accentColor : .secondary)
            .symbolEffect(.pulse, isActive: voice.state == .listening)
            .frame(width: 112, height: 112)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }

    @ViewBuilder
    private func bigButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.glassProminent)
        .tint(color)
        .accessibilityLabel(title)
    }

    // MARK: Flow

    /// Start the voice flow exactly once, and only when the app is truly
    /// foreground-active. On a cold launch from a notification the reminder
    /// sheet's `.task` runs while the app is still becoming active; opening the
    /// mic then crashes (iOS forbids capture off the foreground), which looked
    /// like the app "crashing or going to the background" on a notification tap.
    private func maybeStartFlow() async {
        guard scenePhase == .active, !didStartFlow else { return }
        didStartFlow = true
        await startFlow()
    }

    private func startFlow() async {
        Speaker.shared.configureSession()

        #if targetEnvironment(simulator)
        // No speech models in the Simulator — skip the (doomed) voice attempt and
        // let the tester type or tap. Real voice runs on device.
        status = "Voice needs a real device. Type a reply or tap a button."
        await speak("Is it time to go?")
        #else
        let granted = await VoiceEngine.requestPermissions()
        guard granted else {
            status = "Tap a button below."
            voice.state = .denied
            return
        }
        // No spoken prompt — open the mic and start listening right away.
        beginListening()
        #endif
    }

    /// Debug (simulator): parse a typed reply through the same path as voice.
    private func submitTyped() {
        let text = typedAnswer.trimmingCharacters(in: .whitespaces)
        typedAnswer = ""
        guard !didHandle, !text.isEmpty else { return }
        let intent = IntentParser.parse(text, defaultSnooze: settings.defaultSnoozeMinutes)
        if intent == .unknown {
            status = "Didn't understand: “\(text)”"
            return
        }
        handle(intent, source: .voice)
    }

    /// Speak and wait until it finishes.
    private func speak(_ text: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Speaker.shared.speak(text) { cont.resume() }
        }
    }

    private func beginListening() {
        guard !didHandle else { return }
        status = "Listening… take your time."
        voice.start { text in handleVoice(text) }
    }

    private func handleVoice(_ text: String) {
        guard !didHandle else { return }
        let intent = IntentParser.parse(text, defaultSnooze: settings.defaultSnoozeMinutes)

        if intent == .unknown {
            voiceAttempts += 1
            if voiceAttempts < maxVoiceAttempts {
                // Encourage and give another full, generous listening window.
                let nudge = text.isEmpty ? "Take your time. Say: I went, snooze, or stop."
                                         : "I didn't quite catch that. Please say it again."
                status = text.isEmpty ? "Take your time — I'm listening." : "One more time?"
                Task {
                    await speak(nudge)
                    beginListening()
                }
                return
            }
            status = "No problem — please tap a button below."
            Speaker.shared.speak("No problem. Please tap a button.")
            return
        }
        handle(intent, source: .voice)
    }

    private func handle(_ intent: Intent, source: EventSource) {
        guard !didHandle else { return }
        didHandle = true
        voice.stop()

        switch intent {
        case .went:
            log(.went, source)
            NotificationScheduler.shared.skipNextReminderIfSoon()
            confettiTrigger += 1
            status = "Great job! 🎉"
            Speaker.shared.speak(Praise.random(name: settings.childName))
        case .snooze(let minutes):
            log(.snoozed, source, minutes)
            Task { await NotificationScheduler.shared.scheduleSnooze(minutes: minutes) }
            status = "Okay — reminding you in \(minutes) minutes."
            Speaker.shared.speak("Okay, I'll remind you in \(minutes) minutes.")
        case .stop:
            log(.stopped, source)
            status = "Stopped this reminder."
            Speaker.shared.speak("Stopped.")
        case .unknown:
            didHandle = false
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        }
    }

    private func log(_ kind: EventKind, _ source: EventSource, _ snooze: Int? = nil) {
        context.insert(GoEvent(kind: kind, source: source, snoozeMinutes: snooze))
        try? context.save()
    }
}

#Preview {
    ReminderView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
