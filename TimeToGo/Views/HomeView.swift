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
            ZStack {
                GlassBackground()
                VStack(spacing: 22) {
                    Spacer()
                    countCard
                    wentButton
                    voiceButton
                    Spacer()
                    nextReminderPill
                }
                .padding(.horizontal)
            }
            .navigationTitle("TimeToGo")
        }
    }

    // MARK: Pieces

    private var countCard: some View {
        VStack(spacing: 6) {
            Text("\(todayWentCount)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(todayWentCount == 1 ? "time today" : "times today")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You went \(todayWentCount) times today")
    }

    private var wentButton: some View {
        Button(action: logWentNow) {
            Label("I went now", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        }
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
        .accessibilityHint("Records that you used the bathroom just now")
    }

    private var voiceButton: some View {
        Button {
            appState.presentReminder()
        } label: {
            Label("Answer by voice", systemImage: "mic.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder private var nextReminderPill: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(.bottom, 8)
    }

    private func logWentNow() {
        withAnimation(.snappy) {
            context.insert(GoEvent(kind: .went, source: .manual))
            try? context.save()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Speaker.shared.speak("Logged.")
    }
}

#Preview {
    HomeView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
