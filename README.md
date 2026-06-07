# TimeToGo

An iOS app that reminds my son — every hour from **3:00–11:00 PM**, plus a special **2:55 PM** reminder to go with his caregiver before she leaves at 3:00 PM — to consider whether it's time to use the bathroom.

He is disabled and his speech is sometimes unclear, so the app provides a **voice interface** tuned for atypical speech (commands: *stop* / *snooze* / *"I went"*; snooze defaults to **5 minutes** if no amount is spoken), with one-tap notification buttons as a fully reliable fallback. It keeps a **daily history** of how many times and at what times he went, and delivers reminders reliably via scheduled **local notifications** (which work even when the app is closed or after a reboot).

**Platform:** iOS 26+, iPhone only.
**Stack:** SwiftUI · SwiftData · WhisperKit (on-device speech) · UserNotifications · AVSpeechSynthesizer.

> Status: project scaffolding pending. See the implementation plan for architecture, build phases, verification strategy, and deployment instructions.
