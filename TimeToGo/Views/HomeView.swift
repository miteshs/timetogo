import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GoEvent.timestamp, order: .reverse) private var events: [GoEvent]
    @Bindable private var appState = AppState.shared

    private var todayWentCount: Int {
        let cal = Calendar.current
        return events.filter { $0.kind == .went && cal.isDateInToday($0.timestamp) }.count
    }

    private var nextReminderText: String {
        guard let next = ReminderSchedule.nextReminder(times: AppSettings.shared.reminderTimes, after: .now) else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: next.date)
    }

    /// A still-pending snooze (the most recent action was a snooze whose time
    /// hasn't arrived yet) is the real next reminder — show it instead of the
    /// next hourly slot.
    private var pendingSnoozeDate: Date? {
        guard let latest = events.first,
              latest.kind == .snoozed,
              let minutes = latest.snoozeMinutes else { return nil }
        let fire = latest.timestamp.addingTimeInterval(TimeInterval(minutes * 60))
        return fire > .now ? fire : nil
    }

    private func minutesRemaining(until date: Date) -> String {
        let mins = max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
        return mins == 1 ? "1 minute" : "\(mins) minutes"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 6) {
                    Text("\(todayWentCount)")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(todayWentCount == 1 ? "time today" : "times today")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You went \(todayWentCount) times today")

                Button(action: logWentNow) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 44))
                        Text("I went now").font(.title2.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 24))
                    .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .accessibilityHint("Records that you used the bathroom just now")

                Button {
                    appState.presentReminder()
                } label: {
                    Label("Answer by voice", systemImage: "mic.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal)

                Spacer()

                Group {
                    if let snooze = pendingSnoozeDate {
                        Label {
                            TimelineView(.periodic(from: .now, by: 60)) { _ in
                                Text("Next reminder in \(minutesRemaining(until: snooze))")
                            }
                        } icon: {
                            Image(systemName: "clock")
                        }
                    } else {
                        Label("Next reminder at \(nextReminderText)", systemImage: "clock")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom)
            }
            .navigationTitle("TimeToGo")
        }
    }

    private func logWentNow() {
        context.insert(GoEvent(kind: .went, source: .manual))
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Speaker.shared.speak("Logged.")
    }
}

#Preview {
    HomeView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
