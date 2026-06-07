import Foundation

/// Pure aggregation helpers for the history screen. Operate on plain `Date`
/// values (not the SwiftData model) so they're trivially unit-testable and
/// compile without Xcode.
enum HistoryStats {

    /// One day's worth of "I went" events.
    struct DaySummary: Identifiable, Equatable {
        var day: Date            // start-of-day
        var count: Int
        var times: [Date]        // sorted ascending
        var id: Date { day }
    }

    /// Group "went" timestamps by calendar day, newest day first, with each
    /// day's times sorted earliest-first.
    static func summarize(_ timestamps: [Date], calendar: Calendar = .current) -> [DaySummary] {
        let grouped = Dictionary(grouping: timestamps) { calendar.startOfDay(for: $0) }
        return grouped
            .map { day, times in
                DaySummary(day: day, count: times.count, times: times.sorted())
            }
            .sorted { $0.day > $1.day }
    }

    /// Count of events that fall on the same calendar day as `date`.
    static func count(on date: Date, in timestamps: [Date], calendar: Calendar = .current) -> Int {
        let target = calendar.startOfDay(for: date)
        return timestamps.filter { calendar.startOfDay(for: $0) == target }.count
    }

    /// Consecutive days with at least one "went", counting back from today (or
    /// from yesterday if there's nothing yet today, so a fresh morning doesn't
    /// read as a broken streak). Returns 0 if the most recent day is older.
    static func currentStreak(_ timestamps: [Date], asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(timestamps.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday, days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
