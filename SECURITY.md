# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.
Use GitHub's **Report a vulnerability** button (Security → Advisories) on this repository.
You'll get a reply within a few days.

## What's in scope

- The iOS, watchOS and widget code in `ios/`
- The landing page in `site/`

## Design notes

- **No account, no server by default.** All data lives on device (SwiftData) and in the user's own
  private iCloud database (CloudKit). The open-source build ships with **no backend credentials**.
- **Optional backend.** The FatSecret food-search proxy and the social step leaderboard need your own
  Supabase project. Credentials go in `ios/Config/Secrets.xcconfig`, which is git-ignored. Only the
  public (anon/publishable) key belongs in the app; keep service keys and FatSecret secrets on the server.
- **Untrusted input.** Shared workout links/QR codes are size-capped, decompression-capped and
  clamped field by field (`GymPaperKit/ProgramShare.swift`). Backup and share files are size-capped
  before they are read (`GymPaperKit/SafeRead.swift`). Universal links are accepted from one exact host.
- **Health data** is read from and written to HealthKit only with the user's permission and never
  leaves the device except through the user's own iCloud.
