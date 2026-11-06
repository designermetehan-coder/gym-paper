<div align="center">

# GYM Paper

**Workout, nutrition and intermittent fasting in one free, ad-free app.**
Native iOS, Apple Watch and widgets, plus a web PWA. Everything stays on your device.

[App Store](https://apps.apple.com/app/id6826874026) · [Website](https://gympaper.vercel.app) · [Figma file](FIGMA_COMMUNITY_URL) · [Türkçe](README.tr.md)

![GYM Paper screens](docs/assets/screenshots.jpg)

</div>

## Features

| Area | What it does |
|---|---|
| **Workout** | Programs and weekly plans, a full-screen player with sets, reps, weight and rest timer, supersets, personal records |
| **Nutrition** | Food log with calorie and macro rings, free-text entry in Turkish, barcode scan (Open Food Facts), favourites and recipes |
| **Fasting** | Fixed-schedule intermittent fasting with stages, Live Activity and lock-screen countdown |
| **Summary** | Today at a glance, weekly recap and a 365-day activity map |
| **Apple Watch** | Standalone workout player synced with the iPhone, HealthKit workout sessions, complications |
| **Widgets** | Calories left, steps, water, week and workout widgets |
| **Privacy** | No account, no ads, no tracking. Data lives on-device and in your own iCloud; Apple Health is optional |

## Repository layout

```
gym-paper/
├── apps/
│   ├── ios/          SwiftUI app, Apple Watch app, widgets, BalliKit package
│   ├── web/          React PWA (the original prototype, still fully usable)
│   └── site/         Static landing page (gympaper.vercel.app)
├── backend/
│   └── supabase/     Optional edge functions and SQL (food search proxy, cloud backup)
└── docs/             Architecture and setup guides
```

> The project started under the codename **Ballı**, which you will still see in target, module and folder names.

## Quick start

### iOS

Requirements: macOS, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd apps/ios
make bootstrap   # installs XcodeGen, creates Config/Signing.local.xcconfig
make open        # generates Balli.xcodeproj and opens Xcode
make test        # runs BalliKit unit tests
```

Pick the **Balli** scheme and run on a Simulator. To run on a device, put your Team ID in `Config/Signing.local.xcconfig` and change the bundle identifiers (see [docs/ios.md](docs/ios.md)).

### Web

Requirements: Node 20+.

```sh
cd apps/web
npm ci
npm run dev      # http://localhost:5173
npm test         # unit tests
npm run build    # production PWA in dist/
```

The web app works offline with no configuration. Cloud backup is optional, see [docs/backend.md](docs/backend.md).

## Documentation

| Guide | Contents |
|---|---|
| [Architecture](docs/architecture.md) | How the apps, shared logic and data fit together |
| [iOS](docs/ios.md) | Targets, signing, capabilities, localization, exercise media |
| [Web](docs/web.md) | PWA stack, state, sync and tests |
| [Backend](docs/backend.md) | Supabase setup, edge functions and secrets |
| [Design system](docs/design-system.md) | Tokens, components and the Figma file |

## Tech stack

**iOS** SwiftUI · SwiftData + CloudKit · HealthKit · WidgetKit · ActivityKit · WatchConnectivity · Swift Package (BalliKit) · XcodeGen
**Web** React 18 · Vite 6 · Tailwind CSS 4 · shadcn/ui-style components · IndexedDB · Workbox
**Backend** Supabase (Postgres, Edge Functions on Deno), optional

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. For security reports see [SECURITY.md](SECURITY.md).

## License

Code is released under the [MIT License](LICENSE). The Figma design file is shared on Figma Community under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Third-party data, fonts and assets keep their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The 3D exercise animations used in the App Store build come from [MoveKit](https://movekit.com) under a commercial license and are **not** included in this repository.

---

Designed and built by [Metehan Kaya](https://designermete.com).
