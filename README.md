# Axis App — First Version

My first app: a personal command center for tracking a home inventory, finances, sleep and daily routines, built with Flutter and Firebase.

> **Archived.** This repository is a snapshot of the original Axis App (v0.1.0 to v0.8.0, December 2025 to March 2026). It is no longer maintained and won't run as-is, because the backend it was built against has since changed. It's kept here to show where my projects started.

## Overview

Axis started as a household inventory tracker and grew, release by release, into a dashboard for everyday life. It syncs across devices through Firebase, lets several people share an inventory, sends reminders when items run low, and pulls in outside data like Fitbit sleep and weather.

## Screenshots

Screens from v0.7.0.

| | | |
|---|---|---|
| <img src="https://github.com/user-attachments/assets/e4163792-8aa9-4369-a20f-2b079564cbe8" width="240" alt="Axis App screenshot 6"> | <img src="https://github.com/user-attachments/assets/22941a64-a05f-4a9b-86b8-bc8ca5f42ac9" width="240" alt="Axis App screenshot 5"> | <img src="https://github.com/user-attachments/assets/dbcb42c8-a57f-4175-8e1c-7e26f4b6ea26" width="240" alt="Axis App screenshot 4"> |
| <img src="https://github.com/user-attachments/assets/fb3c0cae-e00f-4946-bade-af48e4c6bec2" width="240" alt="Axis App screenshot 3"> | <img src="https://github.com/user-attachments/assets/d496a8d8-af8c-48a8-a09b-021ae50b7456" width="240" alt="Axis App screenshot 2"> | <img src="https://github.com/user-attachments/assets/b351cc29-62e6-4d50-a0e1-cbfed8cb5664" width="240" alt="Axis App screenshot 1"> |

## Features

- **Inventory tracking.** Rooms and items with quantities, shared between household members by invite.
- **Low-stock notifications.** A scheduled Cloud Function checks inventories every hour and sends push notifications.
- **Analytics hub.** Interactive stats and a timeline graph of usage over time.
- **Finances.** A finances page with a receipt scanner that uses AI to itemize photographed receipts by category.
- **Morning briefing and nightly debrief.** A daily start-of-day summary with weather, and an end-of-day form with sleep tracking.
- **Fitbit sync.** Imports sleep, steps, heart rate and floors climbed.
- **Customization.** Reorderable home tiles, light and dark themes, color options and detailed notification settings.

## Built with

- [Flutter](https://flutter.dev) (Dart) for Android, iOS and macOS
- Firebase: Authentication, Cloud Firestore, Cloud Messaging and Cloud Functions (Node.js)
- Google Gemini API, for receipt parsing
- Fitbit Web API

## Project structure

```
lib/
  main.dart          app entry point and navigation
  pages/             screens (home, inventory, analytics, finances, briefing, debrief, settings)
  services/          Firestore, notifications, data collection
  models/            data classes
functions/
  index.js           Cloud Functions: hourly inventory check, invite and membership notifications
```

## Running locally

This version is archived and depends on a Firebase project that has since changed, so it won't run unchanged. To build it against your own backend:

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Create a Firebase project and run `flutterfire configure` to replace `lib/firebase_options.dart` and the platform config files.
3. Add a `.env` file at the project root with `GEMINI_API_KEY=your_key`. It is not included in the repo.
4. Run `flutter pub get`, then `flutter run`.

The AI chat module was archived in v0.7.0 and is not included in this repository.

## How it was built

This was the first app I built, and I built it with AI-assisted development. I designed the features and directed the work, and I used **Claude** (Anthropic) and **Gemini** in **Google Antigravity** to write and iterate on the code. Each release is tagged, so the history shows the app growing from a simple inventory list into a multi-feature dashboard.

## Status

**Final version: 0.8.0.** Archived. See the [changelog](CHANGELOG.md) for version history.

## License

The source code is available under the [MIT License](LICENSE). The Axis name and app icon are not covered by the license.
