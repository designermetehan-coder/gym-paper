# Contributing

Thanks for wanting to help! GYM Paper is a small, opinionated app, so here's how to make a change land.

## Before you start

- **Bugs:** open an issue with steps, device/iOS version and a screenshot if it's visual.
- **Features:** open an issue first. The app deliberately stays small (no ads, no accounts, no
  gamification). A short "why" saves us both time.

## Setup

```bash
brew install xcodegen
cd ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # set your bundle id + team id
xcodegen generate
open GymPaper.xcodeproj
```

Run the core tests (pure Swift, no simulator needed):

```bash
cd ios/GymPaperKit && swift test
```

## Code style

- SwiftUI + SwiftData, iOS 18+. Keep logic that doesn't need UIKit/SwiftUI in `GymPaperKit` and cover it with tests.
- Use the design tokens in `GymPaper/Design/Theme.swift` (`Color.b*`, `Font.b*`, `BButton`, `BSheet`…).
  No raw hex colors or one-off font sizes in views.
- Every user-facing string goes through the String Catalog (`Localizable.xcstrings`) — Turkish is the
  source language, English is required for every new string.
- Touch targets ≥ 44 pt, support Dynamic Type and VoiceOver labels on icon-only buttons.
- Some code comments are in Turkish (the app started as a personal Turkish project). New comments can be in English.

## Pull requests

- One topic per PR, with before/after screenshots for UI changes (light **and** dark).
- `swift test` must pass; the GitHub Action builds the app on every push.
- Don't add licensed assets (fonts, MoveKit animations, stock photos) — see `THIRD_PARTY_NOTICES.md`.
