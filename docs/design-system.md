# Design system

The GYM Paper design system lives in Figma and is shared on Figma Community under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/):
**[GYM Paper · iOS Design System](FIGMA_COMMUNITY_URL)**

## Figma file structure

| Section | Pages |
|---|---|
| Start | Read me, Cover |
| Screens | iPhone · v1.1, All states, Apple Watch, Widgets & Complications |
| Marketing | App Store assets, Instagram, Launch, Wallpapers |
| Foundations | Colors, Typography, Spacing & Radius, Elevation, Icons |
| Components | Button, Icon Button, Segmented, Day Strip, Navigation, Cards & Tiles, Lists, Data Display |
| Blocks | Workout Card, Nutrition Card, Metric Card, Weight Goal Card, Player Controls |

## Tokens

Variables are organised in three collections:

| Collection | Modes | Contents |
|---|---|---|
| **Primitives** | Value | 63 raw colors: neutral scale, brand lime, accent hues and alpha steps |
| **Color** | Light, Dark | 38 semantic colors (background, surface, ink, muted, separator, accent, ring colors…) that alias primitives |
| **Spacing** | Value | 14 spacing steps and 8 radius values |

Components only reference **Color** and **Spacing** variables, never primitives, so both themes come for free.

### Typography

| Group | Styles | Use |
|---|---|---|
| Display | Large Title, Title, Section, Row, Button Large, Button | SF Pro Bold Italic: screen titles, exercise names, buttons |
| Text | Headline, Body, Body Medium, Small, Caption, Caption Medium, Micro | SF Pro: body copy and labels |
| Number | Hero, XL, L, M, S, XS | SF Pro Heavy Italic with tabular figures: weights, calories, timers |

### Effects

`Elevation/Device`, `Elevation/Primary Button`, `Elevation/Media`, `Blur/Bar Background` (progressive blur behind the top bar and tab bar).

## Principles

- **Ink, not black.** The primary color is near-black `#1C1C1E` (`#E5E5E7` in dark mode); pure black and white are avoided.
- **Lime means brand.** `#C6FF3D` is used for primary actions, the fasting countdown and brand moments, never for decoration.
- **Numbers lead.** Key values use the italic number styles; labels stay small and muted.
- **Touch first.** Minimum tap target 44 pt; inputs use 16 pt text to avoid zoom on iOS web.

## Mapping to code

| Figma | iOS | Web |
|---|---|---|
| Color variables | `Balli/Design/Theme.swift` (`bPrimary`, `bFg`, `bSel`…) | CSS variables in `src/index.css` |
| Text styles | `Font.bDisplay(_:)`, `Font.bNum(_:)`, system text styles | Tailwind utilities |
| Spacing & radius | Layout values in SwiftUI views (`Theme.swift`, `Chrome.swift`) | Tailwind spacing scale |
| Components | SwiftUI views in `Balli/Views` and `Balli/Design/Chrome.swift` | `src/components/ui` |

When a token changes in Figma, update both code mappings in the same pull request.
