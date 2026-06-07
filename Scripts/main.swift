import Foundation

// Standalone verification of TimeToGo's pure logic. Runs with the Swift
// command-line toolchain (no Xcode needed):  `make verify-logic`
// The real test suite (TimeToGoTests, Swift Testing) mirrors these once Xcode
// is installed; this harness lets us prove the riskiest logic right now.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ FAIL: \(message)")
    }
}

func expectIntent(_ input: String, _ expected: Intent) {
    let got = IntentParser.parse(input)
    check(got == expected, "parse(\"\(input)\") => \(got), expected \(expected)")
}

// MARK: IntentParser

print("IntentParser")
expectIntent("I went", .went)
expectIntent("i wnt", .went)              // fuzzy: 1 edit
expectIntent("done", .went)
expectIntent("all finished", .went)
expectIntent("yep", .went)
// Personal pronunciation: the recognizer renders his "I went" as "I ran".
expectIntent("I ran", .went)
expectIntent("ran", .went)
expectIntent("I rang", .went)
// Natural ways of saying he already went — all count as the "I went" button.
expectIntent("I am done", .went)
expectIntent("just did", .went)
expectIntent("I already went", .went)
expectIntent("all set", .went)

expectIntent("snooze", .snooze(minutes: 5))           // default
expectIntent("snooze ten minutes", .snooze(minutes: 10))
expectIntent("snooze 15", .snooze(minutes: 15))
expectIntent("ten minutes", .snooze(minutes: 10))     // bare duration
expectIntent("give me twenty minutes", .snooze(minutes: 20))
expectIntent("twenty five minutes", .snooze(minutes: 25))
expectIntent("later", .snooze(minutes: 5))
expectIntent("not yet", .snooze(minutes: 5))
expectIntent("in a bit", .snooze(minutes: 5))
expectIntent("half an hour", .snooze(minutes: 30))
expectIntent("an hour", .snooze(minutes: 60))
expectIntent("two hours", .snooze(minutes: 120))      // clamp to max 120

expectIntent("stop", .stop)
expectIntent("cancel", .stop)
expectIntent("no", .stop)
expectIntent("leave me alone", .stop)

expectIntent("", .unknown)
expectIntent("the weather is nice", .unknown)

// "go" must NOT fuzzy-match "no" (stop)
check(IntentParser.parse("go") != .stop, "\"go\" should not be parsed as stop")

// Snooze clamping
check(ReminderSchedule.snoozeMinutes(requested: nil) == 5, "nil snooze => default 5")
check(ReminderSchedule.snoozeMinutes(requested: 0) == 5, "0 snooze => default 5")
check(ReminderSchedule.snoozeMinutes(requested: 10) == 10, "10 => 10")
check(ReminderSchedule.snoozeMinutes(requested: 999) == 120, "999 => clamped 120")

// MARK: ReminderSchedule

print("ReminderSchedule")
let times = ReminderSchedule.dailyTimes()
check(times.count == 10, "default schedule has exactly 10 times (got \(times.count))")
check(times.filter { $0.isCaregiver }.count == 1, "exactly one caregiver reminder")
check(times.first == ReminderTime(hour: 14, minute: 55, isCaregiver: true), "first is 14:55 caregiver")
check(times.contains(ReminderTime(hour: 15, minute: 0, isCaregiver: false)), "has 3:00 PM")
check(times.contains(ReminderTime(hour: 23, minute: 0, isCaregiver: false)), "has 11:00 PM")
check(!times.contains(where: { $0.hour == 0 || $0.hour == 12 }), "no midnight/noon reminders")

// Custom window
let custom = ReminderSchedule.dailyTimes(windowStartHour: 9, windowEndHour: 11)
check(custom.count == 4, "9–11 window + caregiver => 4 times (got \(custom.count))")

// nextDate / nextReminder are calendar-relative; just assert they resolve.
let now = Date()
check(ReminderSchedule.nextDate(hour: 15, minute: 0, after: now) != nil, "nextDate resolves")
check(ReminderSchedule.nextReminder(times: times, after: now) != nil, "nextReminder resolves")
if let next = ReminderSchedule.nextReminder(times: times, after: now) {
    check(next.date > now, "next reminder is in the future")
}

// MARK: HistoryStats

print("HistoryStats")
let cal = Calendar.current
let today = cal.startOfDay(for: Date())
func at(_ dayOffset: Int, _ hour: Int) -> Date {
    cal.date(byAdding: .init(day: dayOffset, hour: hour), to: today)!
}
let sample = [at(0, 15), at(0, 18), at(0, 21), at(-1, 16), at(-2, 9)]
let summaries = HistoryStats.summarize(sample)
check(summaries.count == 3, "3 distinct days (got \(summaries.count))")
check(summaries.first?.day == today, "newest day first")
check(summaries.first?.count == 3, "today has 3 events")
check(summaries.first?.times == [at(0, 15), at(0, 18), at(0, 21)], "today's times sorted ascending")
check(HistoryStats.count(on: Date(), in: sample) == 3, "count(on: today) == 3")

// Streak: sample has today, yesterday, and 2 days ago → 3 in a row.
check(HistoryStats.currentStreak(sample) == 3, "currentStreak == 3 for today/-1/-2")
check(HistoryStats.currentStreak([at(0, 15), at(-2, 9)]) == 1, "currentStreak == 1 when yesterday missing")
check(HistoryStats.currentStreak([]) == 0, "currentStreak == 0 for empty")

// MARK: Result

print("")
if failures == 0 {
    print("✅ All \(checks) checks passed.")
    exit(0)
} else {
    print("❌ \(failures) of \(checks) checks failed.")
    exit(1)
}
