import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var unlocked = false
    @State private var pinEntry = ""
    @State private var newPIN = ""
    @State private var lastTestMessage: String?
    @State private var whisperStatus: String?
    @State private var whisperLoading = false

    var body: some View {
        NavigationStack {
            if isLocked {
                lockScreen
            } else {
                settingsForm
            }
        }
    }

    private var isLocked: Bool { !settings.settingsPIN.isEmpty && !unlocked }

    // MARK: Lock screen

    private var lockScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Settings are locked").font(.title2.bold())
            SecureField("Enter PIN", text: $pinEntry)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Button("Unlock") {
                if pinEntry == settings.settingsPIN { unlocked = true }
                pinEntry = ""
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Settings")
    }

    // MARK: Form

    private var settingsForm: some View {
        Form {
            Section {
                Stepper("Start: \(hourLabel(settings.windowStartHour))",
                        value: $settings.windowStartHour, in: 0...23)
                Stepper("End: \(hourLabel(settings.windowEndHour))",
                        value: $settings.windowEndHour, in: 0...23)
            } header: {
                Text("Reminder window")
            } footer: {
                Text("Reminders fire on the hour across this window, every day.")
            }

            Section {
                DatePicker("Time", selection: caregiverBinding, displayedComponents: .hourAndMinute)
            } header: {
                Text("Caregiver reminder")
            } footer: {
                Text("A special reminder before the caregiver leaves (default 2:55 PM).")
            }

            Section {
                Stepper("Default: \(settings.defaultSnoozeMinutes) min",
                        value: $settings.defaultSnoozeMinutes, in: 1...60)
            } header: {
                Text("Snooze")
            } footer: {
                Text("Used when no amount is spoken. Saying e.g. “snooze ten minutes” overrides it.")
            }

            Section {
                Toggle("Use WhisperKit (advanced)", isOn: $settings.useWhisperKit)
                if let whisperStatus {
                    HStack(spacing: 10) {
                        if whisperLoading { ProgressView() }
                        Text(whisperStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Default voice is Apple's on-device recognizer. WhisperKit may handle atypical speech better, but downloads a ~250 MB model on first use (Wi-Fi) and responds a little slower.")
            }

            Section("Reminders") {
                Button("Reschedule now") { Task { await reschedule() } }
                Button("Fire a test reminder (10s)") {
                    Task {
                        await NotificationScheduler.shared.fireTestReminder()
                        lastTestMessage = "Test reminder scheduled — lock the phone and wait ~10s."
                    }
                }
                if let lastTestMessage {
                    Text(lastTestMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Installed", value: dateString(settings.installDate))
                LabeledContent("Reinstall by", value: dateString(settings.reinstallByDate))
            } header: {
                Text("Install")
            } footer: {
                Text("Free Apple ID builds stop launching ~7 days after install. Reconnect to the Mac and re-run before this date.")
            }

            Section {
                if settings.settingsPIN.isEmpty {
                    SecureField("Set a PIN (optional)", text: $newPIN)
                        .keyboardType(.numberPad)
                    Button("Save PIN") {
                        settings.settingsPIN = newPIN
                        settings.persist()
                        newPIN = ""
                    }
                    .disabled(newPIN.count < 4)
                } else {
                    Button("Remove PIN", role: .destructive) {
                        settings.settingsPIN = ""
                        settings.persist()
                    }
                }
            } header: {
                Text("Lock")
            } footer: {
                Text("Stops accidental changes that would disable reminders.")
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings.windowStartHour) { applyAndReschedule() }
        .onChange(of: settings.windowEndHour) { applyAndReschedule() }
        .onChange(of: settings.defaultSnoozeMinutes) { settings.persist(); NotificationScheduler.shared.registerCategories() }
        .onChange(of: settings.useWhisperKit) {
            settings.persist()
            if settings.useWhisperKit { loadWhisperModel() } else { whisperStatus = nil }
        }
        .task {
            if settings.useWhisperKit, VoiceEngine.isWhisperReady { whisperStatus = "Voice model ready." }
        }
    }

    // MARK: Helpers

    private var caregiverBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = settings.caregiverHour
                c.minute = settings.caregiverMinute
                return Calendar.current.date(from: c) ?? .now
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.caregiverHour = c.hour ?? settings.caregiverHour
                settings.caregiverMinute = c.minute ?? settings.caregiverMinute
                applyAndReschedule()
            }
        )
    }

    private func applyAndReschedule() {
        settings.persist()
        Task { await reschedule() }
    }

    private func reschedule() async {
        await NotificationScheduler.shared.rescheduleDaily(times: settings.reminderTimes)
    }

    /// Download + load the WhisperKit model when the toggle is turned on, so it's
    /// ready before a reminder fires. ~250 MB on first use; cached afterward.
    private func loadWhisperModel() {
        guard !VoiceEngine.isWhisperReady else { whisperStatus = "Voice model ready."; return }
        whisperLoading = true
        whisperStatus = "Downloading voice model (~250 MB)… keep this screen open on Wi-Fi."
        Task {
            do {
                try await VoiceEngine.loadWhisper()
                whisperLoading = false
                whisperStatus = "Voice model ready."
            } catch {
                whisperLoading = false
                whisperStatus = "Couldn't load the model: \(error.localizedDescription)"
                settings.useWhisperKit = false
                settings.persist()
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var c = DateComponents()
        c.hour = hour
        c.minute = 0
        let date = Calendar.current.date(from: c) ?? .now
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

#Preview {
    SettingsView()
}
