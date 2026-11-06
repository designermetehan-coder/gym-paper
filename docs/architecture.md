# Architecture

GYM Paper ships as three clients that share the same product model, plus an optional backend.

```
            ┌───────────────────────┐        WatchConnectivity        ┌──────────────────┐
            │  iPhone app (SwiftUI) │◀───────────────────────────────▶│  Apple Watch app │
            │  SwiftData + CloudKit │                                 │  HealthKit       │
            └──────────┬────────────┘                                 └────────┬─────────┘
                       │ App Group snapshot                                    │
             ┌─────────▼─────────┐                                   ┌─────────▼─────────┐
             │ iPhone widgets &  │                                   │ Watch             │
             │ Live Activities   │                                   │ complications     │
             └───────────────────┘                                   └───────────────────┘

        BalliKit (Swift package): calorie engine, plans, fasting, food parsing, merge, sharing
        ────────────────────────────────────────────────────────────────────────────────────
        Web PWA (React): same data model in IndexedDB, JSON backup compatible with the iOS app

                         Optional: Supabase (food search proxy, cloud backup)
```

## Principles

- **On-device first.** No account is needed. The iPhone app stores data with SwiftData and syncs through the user's private iCloud database. The web app stores data in IndexedDB.
- **Pure logic in a package.** Anything that does not touch UI or Apple frameworks lives in `BalliKit` so it can be unit tested with `swift test` on macOS.
- **One design language.** Tokens defined in Figma are mirrored in `Balli/Design/Theme.swift` (iOS) and `src/index.css` (web).

## iOS modules

| Path | Responsibility |
|---|---|
| `Balli/App` | App entry point, model container setup (CloudKit with local fallback) |
| `Balli/Models` | SwiftData models: `UserProfile`, `WorkoutProgram`, `DayLog`, `BodyMeasure`, `SavedFood`, `Recipe`, `ExerciseMedia`, plus the versioned schema and migration plan |
| `Balli/Views` | Screens: Today (Summary), Workout, Nutrition, Profile, onboarding, barcode flow |
| `Balli/Logic` | Screen-independent rules: workout progression, nutrition maths, food emoji/images |
| `Balli/Services` | Health, Live Activities, rest alarm, step watcher and Watch sync, widget sync, food search, persistence helpers |
| `Balli/Design` | Theme tokens, shared chrome (top bar, bottom fade), empty states, exercise media lookup |
| `BalliKit` | `CalorieEngine`, `Plan`, `Fasting`, `Nutrition`, `FoodSearch` / `FoodClients`, `DayMerge`, `ProgramShare`, `PWABackup`, `WidgetSnapshot` |
| `BalliWatch` | Watch home, workout player, HealthKit workout session, snapshot for complications |
| `BalliWidgets` | iPhone widgets and the workout Live Activity |
| `BalliWatchWidgets` | Watch complications |
| `Shared` | Code compiled into several targets (localization helper, Live Activity attributes) |

## Data flow

1. Views read and write SwiftData models through a `ModelContext`; `Store.save` reports failures to the UI instead of failing silently.
2. After each change `WidgetSync` writes a small `WidgetSnapshot` into the App Group container and reloads widget timelines.
3. `WatchSync` sends a `WatchPayload` (today's workout, settings) to the Watch with `updateApplicationContext`; the Watch sends `WatchEvent`s back (set logged, workout completed, fasting ended or skipped).
4. HealthKit is optional: steps, active energy, weight and body data are read to personalise calorie targets; finished workouts are written back.

## Web app

The web app (`apps/web`) is the original prototype. It keeps the full feature set and uses the same JSON backup format, so a backup made on the web can be imported on iOS (`BalliKit/PWABackup`). See [web.md](web.md).

## Backend (optional)

Two Supabase Edge Functions: a FatSecret proxy that keeps API credentials on the server, and a steps endpoint for iOS Shortcuts. Cloud backup for the web app uses Supabase Auth and row level security. See [backend.md](backend.md).
