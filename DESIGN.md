# GYM Paper — Design document

*Metehan Kaya · November 2026*

GYM Paper is a free, account-free workout and nutrition tracker for iPhone and Apple Watch.
One product designer designed and built it end to end with AI: the Figma design system, the SwiftUI app,
the watchOS app, widgets, the landing page and the App Store assets. 1.0 passed App Review in October 2026;
1.1 adds onboarding, a redesigned Watch player and full English.

## Problem

People who train 3–5 times a week with a written program juggle three tools: a coach's app or a
spreadsheet for the program, a calorie app for food, and a timer for rest. Each asks for an account, shows
ads or sells a subscription, and none of them talk to each other.

**Constraints:** one designer + AI · free forever, no backend required · native feel (the first PWA
version never felt native on the Lock Screen, Watch or Health) · Turkish + English.

## Users and jobs

Primary: a self-coached lifter training 3–5 days a week on a fixed split who also wants to lose or hold
weight. Secondary: a beginner following a ready-made plan.

| Job | What "done" looks like |
|---|---|
| Know what to train today | Summary opens on today's workout with one Start button |
| Get through the session without thinking | A player that walks set by set and starts rest on its own |
| Train when the machine is taken | "Machine busy" suggests alternatives for the same muscle |
| Log food in seconds | Type "2 eggs, 1 slice of bread", scan a barcode or reuse a saved meal |
| See if it's working | Weight trend, weekly rings, set volume, a 365-day heat map |
| Leave the phone in the locker | The Watch runs the whole session and syncs back |

## Principles

1. **One sheet of paper.** Each tab answers one question on one screen; detail lives in sheets.
2. **Zero setup to value.** A ready-made program gets someone training in under a minute.
3. **Calm over gamified.** No streak guilt, no badges. Progress is shown, not scored.
4. **Colour means something.** Ink and paper greys carry the UI; lime marks the primary action and fasting.
5. **Private by default.** Nothing leaves the device except through the user's own iCloud and Health.

## Information architecture

| Tab | Question | Order on screen |
|---|---|---|
| Summary | How is today going? | Workout → food → fasting → water + steps → this week → last 365 days |
| Workout | What do I train and how? | Week + day strip, exercises, set and volume totals, Start / Done |
| Nutrition | What have I eaten? | Week + day strip, calories and macros, meals, fasting |
| Profile | Am I getting there? | Current weight + progress, 2×3 tiles, app settings |

**First run:** Welcome → Apple Health → about you → weight and goal → first program → how it works.
Permissions are asked after the flow so a "no" never blocks setup.

**Player:** start anywhere (tab, widget, Shortcut, Watch) → set screen with one primary action → rest starts
by itself (Lock Screen Live Activity + Watch) → "machine busy" swap → pause shrinks the visual → finish writes
the workout to Health.

## Design system

Kept twice and in step: Figma variables/styles and SwiftUI tokens in `ios/GymPaper/Design/Theme.swift`.

| Layer | Figma | Code |
|---|---|---|
| Colour | 63 primitives, 38 semantic tokens (Light/Dark) | `Color.b*` — ink #1C1C1E, no pure black/white |
| Type | Display: SF Pro Bold Italic · Text: SF Pro · Number: SF Pro Heavy Italic | `Font.bDisplay`, `Font.geist`, `Font.bNum` (tabular digits) |
| Spacing | 14 steps, 8 radii, 20 pt cards | constants in `Theme.swift`; targets ≥ 44 pt |
| Components | Button, Icon Button, Segmented, Day Strip, Navigation, Cards & Tiles, Lists, Data Display | `BButton`, `BSheet`, `BSegmented`, `BTopBar`, `BEmpty`… |

**Hybrid liquid glass:** glass only for what floats over content (tab bar, sheets, toasts, top-bar blur);
cards stay opaque so contrast never depends on what scrolls behind. Dark mode has no borders.

## Key decisions

| When | Decision | Trade-off |
|---|---|---|
| Nov 2026 | Open-source code (MIT) and Figma file (CC BY 4.0) | Licensed MoveKit animations removed from the public build |
| Nov 2026 | No gamification | Fewer "come back" hooks |
| Nov 2026 | Social leaderboard hidden | Built but not shipped; needs a server |
| Oct 2026 | Numbers in SF Pro Heavy Italic, tabular | Dropped v1.0's mono look |
| Oct 2026 | Native SwiftUI instead of the PWA | Two codebases until the PWA retired |
| Oct 2026 | Device + private iCloud, no account | No cross-platform sync |
| Oct 2026 | Nutrition logs only, no meal plans | Users bring their own plan |

## How it was built with AI

1. Design in Figma first, bound to variables and styles, so the AI reads tokens instead of guessing pixels.
2. Ask for the smallest shippable change, with the frame and the existing component as context.
3. Run it, screenshot it, compare: scripted simulator captures of ~90 screens (light + dark) per run.
4. Review like a lead: coded findings (QA-, TE-, CR-, SEC-) go to a task board.
5. Keep design and code in sync in the same session.

AI was strong at SwiftUI layout, HealthKit/WidgetKit plumbing, localisation and tests. The designer led
hierarchy, what to cut, motion timing, copy tone — and saying no.

Full version with outcomes and roadmap: see the Figma file's **Case study** page.
