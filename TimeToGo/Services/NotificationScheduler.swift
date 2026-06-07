import Foundation
import UserNotifications

/// Builds and registers the local notifications that drive the whole app.
/// Reminders are scheduled as *repeating* calendar triggers, so they fire on
/// the exact schedule even when the app is closed or after a reboot — no
/// background process required (iOS won't allow one anyway).
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    // Identifiers
    static let category = "REMINDER"
    static let actionWent = "WENT"
    static let actionSnooze = "SNOOZE"
    static let actionStop = "STOP"
    static let dailyPrefix = "daily."
    static let snoozePrefix = "snooze."
    static let testPrefix = "test."

    private let center = UNUserNotificationCenter.current()

    // MARK: Authorization

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Categories / actions

    func registerCategories() {
        let went = UNNotificationAction(identifier: Self.actionWent, title: "I went ✓", options: [])
        let snooze = UNNotificationAction(
            identifier: Self.actionSnooze,
            title: "Snooze \(AppSettings.shared.defaultSnoozeMinutes) min",
            options: []
        )
        let stop = UNNotificationAction(identifier: Self.actionStop, title: "Stop", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: Self.category,
            actions: [went, snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    // MARK: Content

    private func makeContent(isCaregiver: Bool, titlePrefix: String = "") -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if isCaregiver {
            content.title = titlePrefix + "Time to go 🚻"
            content.body = "Try to go now — before your caregiver leaves at 3:00."
        } else {
            content.title = titlePrefix + "Is it time to go? 🚻"
            content.body = "Tap to answer by voice, or use the buttons below."
        }
        content.categoryIdentifier = Self.category
        content.interruptionLevel = .timeSensitive
        // Phase 5 will swap in a recorded "Is it time to go?" prompt.caf here.
        content.sound = .default
        return content
    }

    // MARK: Daily schedule

    /// Replace the repeating daily reminders with the given set.
    func rescheduleDaily(times: [ReminderTime] = ReminderSchedule.dailyTimes()) async {
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(Self.dailyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        for time in times {
            var comps = DateComponents()
            comps.hour = time.hour
            comps.minute = time.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: time.id,
                content: makeContent(isCaregiver: time.isCaregiver),
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: Snooze + test

    func scheduleSnooze(minutes: Int) async {
        let seconds = TimeInterval(max(1, minutes) * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.snoozePrefix)\(UUID().uuidString)",
            content: makeContent(isCaregiver: false),
            trigger: trigger
        )
        try? await center.add(request)
    }

    func fireTestReminder(after seconds: TimeInterval = 10) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.testPrefix)\(UUID().uuidString)",
            content: makeContent(isCaregiver: false, titlePrefix: "Test — "),
            trigger: trigger
        )
        try? await center.add(request)
    }

    func pendingDailyCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(Self.dailyPrefix) }.count
    }

    /// Clear delivered notifications and any leftover snooze/test requests, while
    /// keeping the repeating daily reminders intact. Used by "Clear history".
    func clearTransientNotifications() async {
        center.removeAllDeliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter {
            $0.hasPrefix(Self.snoozePrefix) || $0.hasPrefix(Self.testPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
