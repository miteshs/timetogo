import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \GoEvent.timestamp, order: .reverse) private var events: [GoEvent]

    private var summaries: [HistoryStats.DaySummary] {
        HistoryStats.summarize(events.filter { $0.kind == .went }.map(\.timestamp))
    }

    private var chartData: [HistoryStats.DaySummary] {
        Array(summaries.prefix(14).reversed())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
        }
    }

    @ViewBuilder
    private var content: some View {
        if summaries.isEmpty {
            ContentUnavailableView(
                "No history yet",
                systemImage: "list.bullet.rectangle",
                description: Text("Each time you record going, it shows up here by day.")
            )
        } else {
            List {
                chartSection
                ForEach(summaries) { day in
                    daySection(day)
                }
            }
        }
    }

    private var chartSection: some View {
        Section {
            Chart(chartData) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Times", day.count)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 180)
            .padding(.vertical, 4)
        } header: {
            Text("Last 2 weeks")
        }
    }

    private func daySection(_ day: HistoryStats.DaySummary) -> some View {
        Section {
            ForEach(Array(day.times.enumerated()), id: \.offset) { _, time in
                Label(timeString(time), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text(dayHeader(day.day))
        } footer: {
            Text(day.count == 1 ? "1 time" : "\(day.count) times")
        }
    }

    private func dayHeader(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
