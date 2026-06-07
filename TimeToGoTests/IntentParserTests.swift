import Testing
@testable import TimeToGo

struct IntentParserTests {

    @Test("Went commands, including fuzzy near-misses", arguments: [
        "I went", "i wnt", "went", "done", "all finished", "yep"
    ])
    func wentCommands(input: String) {
        #expect(IntentParser.parse(input) == .went)
    }

    @Test("Personal pronunciation: recognizer renders his 'I went' as 'ran'", arguments: [
        "I ran", "ran", "I rang", "i run"
    ])
    func personalWentVariants(input: String) {
        #expect(IntentParser.parse(input) == .went)
    }

    @Test("Stop commands", arguments: ["stop", "cancel", "no", "leave me alone"])
    func stopCommands(input: String) {
        #expect(IntentParser.parse(input) == .stop)
    }

    @Test("Snooze with explicit and spelled amounts")
    func snoozeAmounts() {
        #expect(IntentParser.parse("snooze") == .snooze(minutes: 5))           // default
        #expect(IntentParser.parse("snooze 15") == .snooze(minutes: 15))
        #expect(IntentParser.parse("snooze ten minutes") == .snooze(minutes: 10))
        #expect(IntentParser.parse("ten minutes") == .snooze(minutes: 10))     // bare duration
        #expect(IntentParser.parse("give me twenty minutes") == .snooze(minutes: 20))
        #expect(IntentParser.parse("twenty five minutes") == .snooze(minutes: 25))
        #expect(IntentParser.parse("half an hour") == .snooze(minutes: 30))
        #expect(IntentParser.parse("an hour") == .snooze(minutes: 60))
        #expect(IntentParser.parse("two hours") == .snooze(minutes: 120))      // clamped
        #expect(IntentParser.parse("later") == .snooze(minutes: 5))
        #expect(IntentParser.parse("not yet") == .snooze(minutes: 5))
    }

    @Test("Unknown / ambiguous input")
    func unknown() {
        #expect(IntentParser.parse("") == .unknown)
        #expect(IntentParser.parse("the weather is nice") == .unknown)
    }

    @Test("Short words don't over-fuzzy-match")
    func noOverMatch() {
        #expect(IntentParser.parse("go") != .stop)   // "go" must not match "no"
    }

    @Test("Custom default snooze is honored")
    func customDefault() {
        #expect(IntentParser.parse("snooze", defaultSnooze: 8) == .snooze(minutes: 8))
    }
}
