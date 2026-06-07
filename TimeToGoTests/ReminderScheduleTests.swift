import Testing
import Foundation
@testable import TimeToGo

struct ReminderScheduleTests {

    @Test("Default schedule is exactly 10 daily reminders")
    func defaultCount() {
        let times = ReminderSchedule.dailyTimes()
        #expect(times.count == 10)
        #expect(times.filter(\.isCaregiver).count == 1)
    }

    @Test("Schedule covers 2:55 PM and 3–11 PM on the hour")
    func defaultTimes() {
        let times = ReminderSchedule.dailyTimes()
        #expect(times.first == ReminderTime(hour: 14, minute: 55, isCaregiver: true))
        #expect(times.contains(ReminderTime(hour: 15, minute: 0, isCaregiver: false)))
        #expect(times.contains(ReminderTime(hour: 23, minute: 0, isCaregiver: false)))
        #expect(!times.contains { $0.hour == 0 || $0.hour == 12 })
    }

    @Test("Custom window")
    func customWindow() {
        let times = ReminderSchedule.dailyTimes(windowStartHour: 9, windowEndHour: 11)
        #expect(times.count == 4)   // caregiver + 9,10,11
    }

    @Test("Snooze clamping and default")
    func snoozeClamp() {
        #expect(ReminderSchedule.snoozeMinutes(requested: nil) == 5)
        #expect(ReminderSchedule.snoozeMinutes(requested: 0) == 5)
        #expect(ReminderSchedule.snoozeMinutes(requested: 10) == 10)
        #expect(ReminderSchedule.snoozeMinutes(requested: 999) == 120)
    }

    @Test("Next reminder is in the future")
    func nextReminder() throws {
        let times = ReminderSchedule.dailyTimes()
        let now = Date()
        let next = try #require(ReminderSchedule.nextReminder(times: times, after: now))
        #expect(next.date > now)
    }
}
