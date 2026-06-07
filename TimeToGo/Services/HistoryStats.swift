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
}
