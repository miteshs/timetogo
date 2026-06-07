import SwiftUI
import SwiftData

/// The screen shown when a reminder is tapped: it speaks the prompt, listens
/// for a spoken reply, and always offers three large buttons as a fallback.
struct ReminderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var voice = VoiceEngine()
    @State private var status = "Is it time to go?"
    @State private var didHandle = false

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: voice.state == .listening ? "mic.fill" : "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(voice.state == .listening ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: voice.state == .listening)

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

            Spacer()

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
        .interactiveDismissDisabled(false)
        .task { await startFlow() }
        .onDisappear {
            voice.stop()
            Speaker.shared.stop()
        }
    }

    @ViewBuilder
    private func bigButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(color, in: RoundedRectangle(cornerRadius: 20))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(title)
    }

    // MARK: Flow

    private func startFlow() async {
        Speaker.shared.configureSession()
        Speaker.shared.speak("Is it time to go? You can say: I went, snooze, or stop.")

        let granted = await VoiceEngine.requestPermissions()
        guard granted else {
            status = "Tap a button below."
            voice.state = .denied
            return
        }
        // Brief pause so the spoken prompt doesn't bleed into the mic.
        try? await Task.sleep(for: .seconds(2.4))
        guard !didHandle else { return }
        voice.start { text in handleVoice(text) }
    }

    private func handleVoice(_ text: String) {
        guard !didHandle else { return }
        let intent = IntentParser.parse(text, defaultSnooze: settings.defaultSnoozeMinutes)
        if intent == .unknown {
            status = "Sorry, I didn't catch that. Please tap a button."
            Speaker.shared.speak("Sorry, I didn't catch that. Please tap a button.")
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
            status = "Great — logged."
            Speaker.shared.speak("Great, logged.")
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
