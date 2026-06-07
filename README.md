# TimeToGo

An iOS app that reminds my son — every hour from **3:00–11:00 PM**, plus a special **2:55 PM** reminder to go with his caregiver before she leaves at 3:00 PM — to consider whether it's time to use the bathroom.

He is disabled and his speech is sometimes unclear, so the app provides a **voice interface** tuned for atypical speech (commands: *stop* / *snooze* / *"I went"*; snooze defaults to **5 minutes** if no amount is spoken), with one-tap notification buttons as a fully reliable fallback. It keeps a **daily history** of how many times and at what times he went, and delivers reminders reliably via scheduled **local notifications** (which work even when the app is closed or after a reboot).

**Platform:** iOS 26+, iPhone only.
**Stack:** SwiftUI · SwiftData · Speech (on-device) · UserNotifications · AVSpeechSynthesizer · Swift Charts.

---

## How it works (the important constraint)

iOS does **not** let an app listen to the microphone in the background — only Siri can. So the app does **not** "run in the background listening." Instead:

1. **Scheduled local notifications** are the reliable engine — they fire on the exact schedule even when the app is closed or after a reboot. No background process needed.
2. Each reminder shows **one-tap buttons** — `I went ✓` · `Snooze 5` · `Stop` — that work right from the lock screen with no voice at all.
3. **Voice activates when he taps the notification**: the app opens, speaks the prompt, listens, and understands "I went / snooze ten minutes / stop." Speaking a number sets a custom snooze; otherwise it defaults to 5 minutes.

`Stop` dismisses **only that one reminder** — the daily schedule keeps running.

---

## Project structure

This project uses **[XcodeGen](https://github.com/yonatankoren/XcodeGen)** — the Xcode project is generated from [`project.yml`](project.yml), so `TimeToGo.xcodeproj` is **not** committed. Run `make generate` after cloning.

```
TimeToGo/
  TimeToGoApp.swift          # @main — SwiftData container, notification delegate, schedules reminders
  Models/                    # GoEvent (SwiftData), AppSettings (UserDefaults)
  Services/
    ReminderSchedule.swift   # PURE schedule math (unit-tested without a device)
    IntentParser.swift       # PURE speech-text → intent (fuzzy match + number words)
    HistoryStats.swift       # PURE per-day aggregation
    NotificationScheduler.swift / NotificationDelegate.swift
    VoiceEngine.swift        # on-device Speech recognition
    Speaker.swift            # AVSpeechSynthesizer text-to-speech
    AppState.swift / Services.swift
  Views/                     # Home, Reminder, History, Settings
TimeToGoTests/               # Swift Testing unit tests
Scripts/main.swift           # standalone pure-logic checks (no Xcode needed)
```

---

## Build & run (Makefile)

| Command | What it does | Needs Xcode? |
|---|---|---|
| `make verify-logic` | Compile & run the pure-logic checks | **No** — Swift CLT only |
| `make generate` | (Re)generate `TimeToGo.xcodeproj` from `project.yml` | No |
| `make build` | Build for the iPhone simulator | Yes |
| `make test` | Run the unit tests on the simulator | Yes |
| `make run` | Build, boot the simulator, install & launch | Yes |
| `make device` | Build for a connected iPhone | Yes |

### First-time setup
1. Install **Xcode** from the Mac App Store.
2. `brew install xcodegen`
3. **Xcode ▸ Settings ▸ Accounts ▸ "+"** → sign in with your free Apple ID (your "Personal Team").
4. `make run` → the app launches in the iPhone 17 simulator.

To open in Xcode instead: `make generate && open TimeToGo.xcodeproj`.

---

## Install on his iPhone (free Apple ID, USB cable)

1. `make generate && open TimeToGo.xcodeproj`
2. Select the **TimeToGo** target → **Signing & Capabilities** → set **Team** to your Personal Team (bundle id `com.mpshah.timetogo`).
   - If signing rejects the **Time-Sensitive** entitlement on a free account, delete `TimeToGo/TimeToGo.entitlements` and the `CODE_SIGN_ENTITLEMENTS` line in `project.yml`, then `make generate` again. The app still works; reminders just won't pierce Focus modes.
3. Plug in his iPhone → **Trust** → enable **Settings ▸ Privacy & Security ▸ Developer Mode** (restarts the phone).
4. Pick his device in the Xcode toolbar → **Run**.
5. First launch on the phone: **Settings ▸ General ▸ VPN & Device Management** → trust your developer certificate.

> **⚠️ Free-account 7-day expiry:** the app stops launching ~7 days after each install. Reconnect to the Mac and re-run before the **"reinstall by"** date shown on the in-app Settings screen. Enrolling in the Apple Developer Program ($99/yr) later upgrades this to ~1-year installs with no code changes (and unlocks Critical Alerts + TestFlight).

---

## Voice engine note

The default voice backend is Apple's **on-device `SFSpeechRecognizer`** (no network, no large download, supports command-word hints that help with atypical speech). The plan also allows for Apple's newer `SpeechTranscriber` and an opt-in **WhisperKit** path; those are evaluated during **Phase 6 (on-device tuning)** against his actual speech. `VoiceEngine`'s public surface is intentionally backend-agnostic so the engine can be swapped without touching the views.

---

## Status

Phases 1–5 implemented (scaffold + build harness, notifications engine, data/history, voice, polish/settings/accessibility). Phase 6 (on-device tuning to his voice) and Phase 7 (cable install) happen on the Mac + his iPhone.
