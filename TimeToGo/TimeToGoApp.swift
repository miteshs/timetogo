import SwiftUI
import SwiftData

@main
struct TimeToGoApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: GoEvent.self)
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
        Services.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { await bootstrap() }
        }
        .modelContainer(container)
    }

    /// Ask for notification permission and (re)install the daily schedule.
    @MainActor
    private func bootstrap() async {
        let granted = await NotificationScheduler.shared.requestAuthorization()
        if granted {
            await NotificationScheduler.shared.rescheduleDaily(times: AppSettings.shared.reminderTimes)
        }
        await VoiceEngine.logAssetDiagnostics()
        // Warm the default (Apple) speech model now, off the critical path, so the
        // first reminder's mic opens instantly instead of installing it then.
        if !AppSettings.shared.useWhisperKit {
            Task { await VoiceEngine.prewarmAnalyzerAssets() }
        }
    }
}
