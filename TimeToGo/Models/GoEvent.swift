import Foundation
import SwiftData

/// What happened.
enum EventKind: String, Codable, CaseIterable {
    case went              // he used the bathroom
    case snoozed           // reminder pushed back
    case stopped           // reminder dismissed for now
    case reminderFired     // a scheduled reminder was delivered
    case caregiverReminder // the 2:55 PM caregiver reminder was delivered
}

/// How it was recorded.
enum EventSource: String, Codable, CaseIterable {
    case voice    // spoken reply
    case button   // notification action or in-app button
    case manual   // tapped "I went" on the home screen
    case auto     // system-logged
}

/// A single logged event. History counts `.went` per day; logging
/// `.reminderFired` lets History also surface missed reminders later.
@Model
final class GoEvent {
    var id: UUID
    var timestamp: Date
    private var kindRaw: String
    private var sourceRaw: String
    var snoozeMinutes: Int?

    init(kind: EventKind, source: EventSource, snoozeMinutes: Int? = nil, timestamp: Date = .now) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.snoozeMinutes = snoozeMinutes
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .went }
        set { kindRaw = newValue.rawValue }
    }

    var source: EventSource {
        get { EventSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
