# Contributing

Thanks for your interest in GYM Paper. Bug reports, ideas and pull requests are all welcome.

## Before you start

- **Bugs:** open an issue with the bug report template. Include device, OS version and steps to reproduce.
- **Features:** open a feature request first so we can agree on scope before you write code.
- **Small fixes** (typos, docs, obvious bugs) can go straight to a pull request.

## Development setup

See the [README](README.md#quick-start) and the guides in [docs/](docs). In short:

```sh
# iOS
cd apps/ios && make bootstrap && make open

# Web
cd apps/web && npm ci && npm run dev
```

## Pull requests

1. Fork the repo and create a branch from `main`: `feat/short-description`, `fix/short-description` or `docs/short-description`.
2. Keep the change focused. One topic per pull request.
3. Run the tests that cover your change:
   - iOS shared logic: `cd apps/ios && make test`
   - Web: `cd apps/web && npm test && npm run build`
4. For UI changes, add before/after screenshots (light and dark) to the pull request.
5. Fill in the pull request template.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org):

```
feat(watch): sync paused state with iPhone
fix(nutrition): parse "1,5 dilim" as 1.5 slices
docs: explain signing setup
```

Common scopes: `ios`, `watch`, `widgets`, `kit`, `web`, `site`, `backend`, `docs`.

## Code style

**Swift**
- SwiftUI and Swift Concurrency; keep views small and move logic into `Balli/Logic` or `BalliKit`.
- Pure, platform-independent logic belongs in `BalliKit` with unit tests.
- Use the design tokens in `Balli/Design/Theme.swift` (colors, fonts, spacing) instead of literal values.
- Four-space indentation.

**JavaScript / React**
- Function components and hooks; state changes go through `update()` in `src/lib/store.jsx`.
- UI primitives live in `src/components/ui`; reuse them before adding new ones.
- Two-space indentation, no semicolons where the surrounding code has none.

**Localization**
- Turkish is the source language; English strings live in String Catalogs (`*.xcstrings`).
- Every new user-facing string needs both a Turkish and an English entry.

**Comments**
- Many existing code comments are in Turkish. New comments can be in English or Turkish; please keep them short and explain *why*, not *what*.

## Design changes

The Figma file is the source of truth for tokens and components (see [docs/design-system.md](docs/design-system.md)). If your change introduces a new color, type style or component, mention it in the pull request so the Figma file can be updated too.

## Code of conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
