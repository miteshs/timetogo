import Foundation
import Observation

/// User-configurable settings, persisted to `UserDefaults`. `@Observable` so
/// SwiftUI updates live; call `persist()` after mutating from the UI.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var windowStartHour: Int = ReminderSchedule.defaultWindowStartHour
    var windowEndHour: Int = ReminderSchedule.defaultWindowEndHour
    var caregiverHour: Int = ReminderSchedule.defaultCaregiverHour
    var caregiverMinute: Int = ReminderSchedule.defaultCaregiverMinute
    var defaultSnoozeMinutes: Int = ReminderSchedule.defaultSnoozeMinutes
    /// Opt-in WhisperKit backend (deferred — see Phase 6). Off by default.
    var useWhisperKit: Bool = false
    /// Empty string means no PIN lock on Settings.
    var settingsPIN: String = ""
    /// When this build was first launched — drives the "reinstall by" banner.
    var installDate: Date = .now

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let start = "settings.windowStartHour"
        static let end = "settings.windowEndHour"
        static let cgHour = "settings.caregiverHour"
        static let cgMinute = "settings.caregiverMinute"
        static let snooze = "settings.defaultSnoozeMinutes"
        static let whisper = "settings.useWhisperKit"
        static let pin = "settings.pin"
        static let install = "settings.installDate"
    }

    private init() {
        if defaults.object(forKey: Key.start) != nil { windowStartHour = defaults.integer(forKey: Key.start) }
        if defaults.object(forKey: Key.end) != nil { windowEndHour = defaults.integer(forKey: Key.end) }
        if defaults.object(forKey: Key.cgHour) != nil { caregiverHour = defaults.integer(forKey: Key.cgHour) }
        if defaults.object(forKey: Key.cgMinute) != nil { caregiverMinute = defaults.integer(forKey: Key.cgMinute) }
        if defaults.object(forKey: Key.snooze) != nil { defaultSnoozeMinutes = defaults.integer(forKey: Key.snooze) }
        useWhisperKit = defaults.bool(forKey: Key.whisper)
        settingsPIN = defaults.string(forKey: Key.pin) ?? ""
        if let date = defaults.object(forKey: Key.install) as? Date {
            installDate = date
        } else {
            defaults.set(installDate, forKey: Key.install)
        }
    }

    func persist() {
        defaults.set(windowStartHour, forKey: Key.start)
        defaults.set(windowEndHour, forKey: Key.end)
        defaults.set(caregiverHour, forKey: Key.cgHour)
        defaults.set(caregiverMinute, forKey: Key.cgMinute)
        defaults.set(defaultSnoozeMinutes, forKey: Key.snooze)
        defaults.set(useWhisperKit, forKey: Key.whisper)
        defaults.set(settingsPIN, forKey: Key.pin)
    }

    /// The full daily reminder set derived from the current window/caregiver settings.
    var reminderTimes: [ReminderTime] {
        ReminderSchedule.dailyTimes(
            caregiverHour: caregiverHour,
            caregiverMinute: caregiverMinute,
            windowStartHour: windowStartHour,
            windowEndHour: windowEndHour
        )
    }

    /// Free-account builds stop launching ~7 days after install.
    var reinstallByDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: installDate) ?? installDate
    }
}
