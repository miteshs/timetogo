import Foundation

/// A single recurring daily reminder time.
struct ReminderTime: Equatable, Hashable {
    var hour: Int
    var minute: Int
    /// The special 2:55 PM "go before the caregiver leaves" reminder.
    var isCaregiver: Bool

    /// Stable identifier used for the notification request id.
    var id: String { "daily.\(hour)_\(minute)" }
}

/// Pure, dependency-free scheduling math. Foundation only, so it can be unit
/// tested (and verified with the standalone Swift compiler) without a device.
enum ReminderSchedule {

    static let defaultCaregiverHour = 14
    static let defaultCaregiverMinute = 55
    static let defaultWindowStartHour = 15   // 3:00 PM
    static let defaultWindowEndHour = 23     // 11:00 PM
    static let defaultSnoozeMinutes = 5

    /// Build the full set of daily reminder times: the caregiver reminder plus
    /// one on the hour across the inclusive window `[startHour ... endHour]`.
    ///
    /// With the defaults (14:55 + 15:00…23:00) this returns exactly 10 times.
    static func dailyTimes(
        caregiverHour: Int = defaultCaregiverHour,
        caregiverMinute: Int = defaultCaregiverMinute,
        windowStartHour: Int = defaultWindowStartHour,
        windowEndHour: Int = defaultWindowEndHour
    ) -> [ReminderTime] {
        var times = [ReminderTime(hour: caregiverHour, minute: caregiverMinute, isCaregiver: true)]
        guard windowEndHour >= windowStartHour else { return times }
        for hour in stride(from: windowStartHour, through: windowEndHour, by: 1) {
            times.append(ReminderTime(hour: hour, minute: 0, isCaregiver: false))
        }
        return times
    }

    /// Resolve a snooze duration: use the requested amount if valid, otherwise
    /// fall back to the default. Clamped to a sane range.
    static func snoozeMinutes(
        requested: Int?,
        defaultMinutes: Int = defaultSnoozeMinutes,
        minMinutes: Int = 1,
        maxMinutes: Int = 120
    ) -> Int {
        guard let requested, requested > 0 else { return defaultMinutes }
        return min(max(requested, minMinutes), maxMinutes)
    }

    /// The next moment strictly after `now` matching the given hour/minute.
    static func nextDate(
        hour: Int,
        minute: Int,
        after now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
    }

    /// The soonest upcoming reminder across all daily times.
    static func nextReminder(
        times: [ReminderTime],
        after now: Date,
        calendar: Calendar = .current
    ) -> (time: ReminderTime, date: Date)? {
        times
            .compactMap { t -> (ReminderTime, Date)? in
                guard let d = nextDate(hour: t.hour, minute: t.minute, after: now, calendar: calendar) else { return nil }
                return (t, d)
            }
            .min { $0.1 < $1.1 }
            .map { (time: $0.0, date: $0.1) }
    }
}
