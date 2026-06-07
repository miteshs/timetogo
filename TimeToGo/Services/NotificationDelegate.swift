import Foundation
import UserNotifications

/// Handles notification presentation and button taps. Action buttons are the
/// 100%-reliable, no-voice-needed path; tapping the body opens the in-app
/// voice screen.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    // Show reminders even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let defaultSnooze = await AppSettings.shared.defaultSnoozeMinutes

        switch action {
        case NotificationScheduler.actionWent:
            await Services.shared.log(.went, source: .button)

        case NotificationScheduler.actionStop:
            await Services.shared.log(.stopped, source: .button)

        case NotificationScheduler.actionSnooze:
            await Services.shared.log(.snoozed, source: .button, snoozeMinutes: defaultSnooze)
            await Services.shared.scheduler.scheduleSnooze(minutes: defaultSnooze)

        case UNNotificationDefaultActionIdentifier:
            // Body tapped → open the in-app reminder (voice loop + big buttons).
            await AppState.shared.presentReminder()

        default:
            break
        }
    }
}
