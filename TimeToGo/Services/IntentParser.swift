import Foundation

/// What the user meant when they spoke (or tapped) a reply to a reminder.
enum Intent: Equatable {
    case went                  // "I went" / "done" / "finished"
    case snooze(minutes: Int)  // "snooze" / "ten minutes" / "later"
    case stop                  // "stop" / "cancel" / "no"
    case unknown               // couldn't tell — ask again / fall back to buttons
}

/// Pure, dependency-free natural-language → `Intent` mapping, tuned for a tiny
/// command vocabulary spoken by someone whose speech may be unclear. Uses
/// substring + token-level fuzzy matching so near-misses ("i wnt") still land.
///
/// Foundation only — unit tested and verified without a device.
enum IntentParser {

    static let defaultSnoozeMinutes = ReminderSchedule.defaultSnoozeMinutes

    /// Command words we feed to the recognizer as hints (improves accuracy).
    static let commandHints = [
        "I went", "went", "done", "finished",
        "snooze", "later", "minutes", "ten minutes", "five minutes",
        "stop", "cancel"
    ]

    // MARK: Keyword sets

    private static let wentWords = ["went", "gone", "done", "finished", "complete", "completed", "did", "yep", "yeah"]
    private static let snoozeWords = ["snooze", "later", "wait", "minute", "minutes", "min", "mins", "soon", "while", "remind", "bit"]
    // Multi-word snooze cues (checked as substrings).
    private static let snoozePhrases = ["not yet", "not now", "in a bit", "hold on", "a while", "give me", "couple"]
    private static let stopWords = ["stop", "cancel", "dismiss", "quit", "nope", "no", "off"]
    private static let stopPhrases = ["leave me", "go away", "turn off", "all done"]

    // MARK: Public

    static func parse(_ raw: String, defaultSnooze: Int = defaultSnoozeMinutes) -> Intent {
        let text = normalize(raw)
        if text.isEmpty { return .unknown }

        let hasStop = containsAny(text, stopWords) || containsAnyPhrase(text, stopPhrases)
        let hasSnooze = containsAny(text, snoozeWords) || containsAnyPhrase(text, snoozePhrases)
        let hasWent = containsAny(text, wentWords)
        let number = parseNumber(text)

        // Explicit stop wins, unless it's actually a snooze ("not now, later").
        if hasStop && !hasSnooze && !hasWent && number == nil {
            return .stop
        }
        // Any snooze cue, or a bare duration ("ten minutes"), means snooze.
        if hasSnooze || (number != nil && !hasWent) {
            return .snooze(minutes: ReminderSchedule.snoozeMinutes(requested: number, defaultMinutes: defaultSnooze))
        }
        if hasWent { return .went }
        if hasStop { return .stop }
        return .unknown
    }

    // MARK: Normalization

    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " { return Character(scalar) }
            return " "
        }
        let cleaned = String(scalars).replacingOccurrences(of: "-", with: " ")
        return cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    // MARK: Matching

    private static func tokens(_ text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        let toks = tokens(text)
        for kw in keywords {
            for tok in toks where fuzzyEqual(tok, kw) { return true }
        }
        return false
    }

    private static func containsAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        for p in phrases where text.contains(p) { return true }
        return false
    }

    /// Exact for very short words; allow 1 edit for medium, 2 for long. Keeps
    /// "go" from fuzzily matching "no" while still catching "wnt" → "went".
    static func fuzzyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let threshold = b.count <= 3 ? 0 : (b.count <= 6 ? 1 : 2)
        if threshold == 0 { return false }
        if abs(a.count - b.count) > threshold { return false }
        return levenshtein(a, b) <= threshold
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }

    // MARK: Number parsing ("ten", "15", "an hour", "half an hour")

    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60
    ]

    static func parseNumber(_ text: String) -> Int? {
        let mentionsHour = text.contains("hour")
        if text.contains("half") && mentionsHour { return 30 }

        // Digits, e.g. "snooze 10".
        if let digits = firstInteger(in: text) {
            return mentionsHour ? digits * 60 : digits
        }

        // Spelled-out numbers, supporting "twenty five".
        let toks = tokens(text)
        var total: Int? = nil
        var i = 0
        while i < toks.count {
            let w = toks[i]
            if let tenVal = tens[w] {
                var value = tenVal
                if i + 1 < toks.count, let oneVal = ones[toks[i + 1]], oneVal < 10 {
                    value += oneVal
                    i += 1
                }
                total = (total ?? 0) + value
            } else if let oneVal = ones[w] {
                total = (total ?? 0) + oneVal
            }
            i += 1
        }

        if mentionsHour { return (total ?? 1) * 60 }   // "an hour" → 60
        return total
    }

    private static func firstInteger(in text: String) -> Int? {
        var digits = ""
        for ch in text {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }
}
