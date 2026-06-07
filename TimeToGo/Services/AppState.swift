import Foundation
import Observation

/// Lightweight UI state shared between the app and the notification delegate
/// (e.g. tapping a reminder opens the in-app voice screen).
@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    private init() {}

    var selectedTab: Int = 0
    var showReminder: Bool = false

    func presentReminder() {
        selectedTab = 0
        showReminder = true
    }
}
