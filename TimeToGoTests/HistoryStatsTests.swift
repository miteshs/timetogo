import Testing
import Foundation
@testable import TimeToGo

struct HistoryStatsTests {

    private let cal = Calendar.current

    private func at(_ dayOffset: Int, _ hour: Int) -> Date {
        let today = cal.startOfDay(for: Date())
        return cal.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: today)!
    }

    @Test("Groups by day, newest first, times ascending")
    func grouping() {
        let sample = [at(0, 21), at(0, 15), at(0, 18), at(-1, 16), at(-2, 9)]
        let summaries = HistoryStats.summarize(sample)

        #expect(summaries.count == 3)
        #expect(summaries.first?.count == 3)
        #expect(summaries.first?.times == [at(0, 15), at(0, 18), at(0, 21)])
        // Newest day first.
        #expect(summaries[0].day > summaries[1].day)
    }

    @Test("Count on a given day")
    func countOnDay() {
        let sample = [at(0, 15), at(0, 18), at(-1, 16)]
        #expect(HistoryStats.count(on: Date(), in: sample) == 2)
    }

    @Test("Empty input")
    func empty() {
        #expect(HistoryStats.summarize([]).isEmpty)
    }
}
