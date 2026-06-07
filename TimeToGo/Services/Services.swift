import Foundation
import SwiftData
import UserNotifications

/// App-wide wiring: owns the SwiftData container reference, installs the
/// notification delegate, and offers a context-free way to log events (used by
/// the notification action handler, which has no SwiftUI environment).
@MainActor
final class Services {
    static let shared = Services()
    private init() {}

    private(set) var container: ModelContainer?
    let scheduler = NotificationScheduler.shared
    private let notificationDelegate = NotificationDelegate()

    func configure(container: ModelContainer) {
        self.container = container
        UNUserNotificationCenter.current().delegate = notificationDelegate
        scheduler.registerCategories()
    }

    /// Insert + save an event on a fresh context backed by the shared store.
    func log(_ kind: EventKind, source: EventSource, snoozeMinutes: Int? = nil, at date: Date = .now) {
        guard let container else { return }
        let context = ModelContext(container)
        context.insert(GoEvent(kind: kind, source: source, snoozeMinutes: snoozeMinutes, timestamp: date))
        try? context.save()
    }
}
