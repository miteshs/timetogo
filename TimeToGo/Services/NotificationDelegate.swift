import Foundation
import UserNotifications

/// Handles notification presentation and button taps. Action buttons are the
/// 100%-reliable, no-voice-needed path; tapping the body opens the in-app
/// voice screen.
///
/// IMPORTANT — these use the *completion-handler* delegate methods, not the
/// `async` variants. With the `async` variant, UIKit ran its post-action
/// snapshot / state-restoration work on the Swift concurrency pool (a background
/// thread); when a body tap foregrounded the app from a cold launch that work
/// hit `-[UIApplication _updateSnapshotAndStateRestoration…]` off the main
/// thread and crashed with "Call must be made on main thread". The
/// completion-handler form lets us keep everything on the main actor.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    // Show reminders even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            let defaultSnooze = AppSettings.shared.defaultSnoozeMinutes

            switch action {
            case NotificationScheduler.actionWent:
                Services.shared.log(.went, source: .button)
                NotificationScheduler.shared.skipNextReminderIfSoon()

            case NotificationScheduler.actionStop:
                Services.shared.log(.stopped, source: .button)

            case NotificationScheduler.actionSnooze:
                Services.shared.log(.snoozed, source: .button, snoozeMinutes: defaultSnooze)
                await Services.shared.scheduler.scheduleSnooze(minutes: defaultSnooze)

            case UNNotificationDefaultActionIdentifier:
                // Body tapped → open the in-app reminder (voice loop + big buttons).
                AppState.shared.presentReminder()

            default:
                break
            }

            completionHandler()
        }
    }
}
