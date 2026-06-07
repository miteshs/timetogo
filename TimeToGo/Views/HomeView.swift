import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GoEvent.timestamp, order: .reverse) private var events: [GoEvent]
    @Bindable private var appState = AppState.shared
    private var settings: AppSettings { AppSettings.shared }

    @State private var confettiTrigger = 0
    @State private var newSticker: String?

    private var wentTimestamps: [Date] {
        events.filter { $0.kind == .went }.map(\.timestamp)
    }
    private var lifetimeGos: Int { events.filter { $0.kind == .went }.count }
    private var todayWentCount: Int {
        events.filter { $0.kind == .went && Calendar.current.isDateInToday($0.timestamp) }.count
    }
    private var goal: Int { max(1, settings.dailyGoal) }
    private var progress: Double { min(1, Double(todayWentCount) / Double(goal)) }
    private var streak: Int { HistoryStats.currentStreak(wentTimestamps) }

    private var nextReminderText: String {
        guard let next = ReminderSchedule.nextReminder(times: settings.reminderTimes, after: .now) else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: next.date)
    }

    /// A still-pending snooze (the most recent action was a snooze whose time
    /// hasn't arrived yet) is the real next reminder — show it instead.
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
                VStack(spacing: 18) {
                    Spacer()
                    goalRing
                    if streak > 0 { streakPill }
                    wentButton
                    voiceButton
                    Spacer()
                    nextReminderPill
                }
                .padding(.horizontal)

                ConfettiView(trigger: confettiTrigger)
            }
            .overlay(alignment: .top) { stickerBanner }
            .navigationTitle("TimeToGo")
        }
    }

    // MARK: Pieces

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            VStack(spacing: 2) {
                Text("\(todayWentCount)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(todayWentCount >= goal ? "all done! 🎉" : "of \(goal) today")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 230, height: 230)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You went \(todayWentCount) of \(goal) times today")
    }

    private var streakPill: some View {
        Label("\(streak)-day streak", systemImage: "flame.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            .accessibilityLabel("\(streak) day streak")
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

    @ViewBuilder private var stickerBanner: some View {
        if let newSticker {
            Label("New sticker!  \(newSticker)", systemImage: "sparkles")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func logWentNow() {
        let earned = StickerBook.sticker(forGoIndex: lifetimeGos)   // the sticker this go earns
        withAnimation(.snappy) {
            context.insert(GoEvent(kind: .went, source: .manual))
            try? context.save()
        }
        NotificationScheduler.shared.skipNextReminderIfSoon()
        celebrate(newSticker: earned)
    }

    /// Confetti + a success haptic + spoken praise, plus a banner if this go
    /// just unlocked a new sticker.
    private func celebrate(newSticker earned: String?) {
        confettiTrigger += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let earned {
            withAnimation(.bouncy) { newSticker = earned }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation { newSticker = nil }
            }
            Speaker.shared.speak("New sticker! " + Praise.random(name: settings.childName))
        } else {
            Speaker.shared.speak(Praise.random(name: settings.childName))
        }
    }
}

/// Short, varied spoken encouragement (with the child's name when set).
enum Praise {
    static func random(name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        let withName = ["Great job, \(n)!", "Awesome, \(n)!", "You did it, \(n)!", "Way to go, \(n)!", "Nice one, \(n)!"]
        let plain = ["Great job!", "Awesome!", "You did it!", "Way to go!", "Nice one!"]
        return (n.isEmpty ? plain : withName).randomElement()!
    }
}

#Preview {
    HomeView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
