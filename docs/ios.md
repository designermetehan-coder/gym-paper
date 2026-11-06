# iOS, Apple Watch and widgets

## Requirements

- macOS with **Xcode 26** or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 18+ / watchOS 11+ deployment targets

## Getting started

```sh
cd apps/ios
make bootstrap   # installs XcodeGen, creates Config/Signing.local.xcconfig
make open        # generates Balli.xcodeproj and opens it
```

The Xcode project is generated from `project.yml` and is not committed. Run `make project` again after pulling changes that touch `project.yml` or add files.

| Command | Description |
|---|---|
| `make project` | Generate `Balli.xcodeproj` |
| `make open` | Generate and open in Xcode |
| `make test` | Run `BalliKit` unit tests with `swift test` |
| `make clean` | Remove the generated project and build products |

## Schemes

| Scheme | What it builds |
|---|---|
| **Balli** | Full iPhone app with widgets and the embedded Watch app |
| **Balli Watch** | Watch app on its own |
| **Balli Lite** | iPhone app without iCloud, HealthKit, widgets or Live Activities (compiled with `LITE`). The quickest way to try the app on a personal team |

Pass `-demo` as a launch argument to start with demo data in a separate local store.

## Signing and identifiers

1. Put your Team ID in `Config/Signing.local.xcconfig` (git-ignored):
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```
2. The capabilities below are tied to bundle identifiers you must own. Replace `com.metehankaya.balli` everywhere in `project.yml` and in the code (`grep -r "com.metehankaya" .`) with your own prefix:

| Capability | Identifier |
|---|---|
| App, widgets, Watch app | `com.metehankaya.balli`, `.widgets`, `.watchkitapp`, `.watchkitapp.widgets` |
| App Group (widgets and complications) | `group.com.metehankaya.balli` |
| iCloud / CloudKit | `iCloud.com.metehankaya.balli` |
| Background task | `com.metehankaya.balli.steps` |

## Localization

Turkish is the development language. English translations live in String Catalogs:

- `Balli/Resources/Localizable.xcstrings`
- `BalliWatch/Localizable.xcstrings`, `BalliWidgets/Localizable.xcstrings`, `BalliWatchWidgets/Localizable.xcstrings`
- Permission prompts: `en.lproj/InfoPlist.strings`

Keys are the Turkish source strings. Add an English value for every new key.

## Exercise media

| Source | Location | In this repo |
|---|---|---|
| free-exercise-db photos (two frames per move) and Turkish how-to text | `Balli/Resources/ExerciseMedia`, `exercise-library.json` | Yes |
| MoveKit 3D animations (iPhone video, Watch frame sequences) | `Balli/Resources/Motion`, `Balli/Resources/MotionWatch` | **No**, licensed |
| Name → MoveKit slug map | `Balli/Resources/mk-map.json` | Yes |

`Motion.swift` looks for a MoveKit file first and falls back to the photos, so the app works without the animations. If you have your own MoveKit license, place the converted files as `mk-<slug>.mp4` in `Balli/Resources/Motion` and the Watch frames in `Balli/Resources/MotionWatch`, then run `make project`. Both folders are git-ignored.

## Optional services

Food search uses Open Food Facts directly and FatSecret through a Supabase Edge Function. To enable FatSecret, deploy the backend (see [backend.md](backend.md)) and set `supabaseURL` and `anonKey` in `Balli/Services/FoodService.swift`. Without it, search falls back to the built-in list and Open Food Facts.

The friends' step leaderboard (`SocialView.swift`) is disabled in the current release.

## iPhone Duo

Foldable layouts are compiled only with the `DUO_SDK` flag, which requires Xcode 27.1. Earlier toolchains ignore that code.

## Tests

`BalliKit` holds the testable logic (calorie engine, plans, fasting stages, food parsing, merge, sharing, widget snapshots):

```sh
make test
```
