# Web app (PWA)

The web app in `apps/web` was the first version of GYM Paper (codename Ballı). It runs fully offline and installs to the iOS home screen.

## Stack

React 18 · Vite 6 · Tailwind CSS 4 · shadcn/ui-style components · vaul sheets · Tabler Icons · immer · idb-keyval (IndexedDB) · vite-plugin-pwa (Workbox)

## Commands

| Command | Description |
|---|---|
| `npm ci` | Install exact dependency versions |
| `npm run dev` | Development server on http://localhost:5173 |
| `npm test` | Unit tests (plans, workout logic, nutrition parsing) |
| `npm run build` | Production PWA in `dist/` |
| `npm run build:single` | Single-file HTML build in `dist-single/` (no service worker) |
| `npm run test:e2e` | Playwright smoke test against `vite preview`; run `npm run build` first and `npx playwright install chromium` once |

## Structure

| Path | Responsibility |
|---|---|
| `src/screens` | Today, Workout, Session (player), Nutrition, Profile |
| `src/components/ui` | Design-system primitives |
| `src/lib/store.jsx` | App state: `AppProvider`, `update(fn)` with immer, undo, schema migrations |
| `src/lib/merge.js` | Three-way merge used for sync |
| `src/lib/cloud.js` | Optional Supabase backup, split into monthly chunks |
| `src/lib/program.js`, `schedule.js` | Programs, weekly plans and history |
| `src/lib/foods.js`, `search.js` | Built-in food table and search |
| `src/lib/progress.js`, `gamify.js` | Records, volume, streaks |

## Data

- Stored per profile in IndexedDB under `balli-db-v2:<profileId>`, written on every change.
- `migrate()` upgrades older data and never deletes user programs (`schemaVersion`).
- Profile › Data exports a JSON backup that the iOS app can import.

## Cloud backup (optional)

Copy `.env.example` to `.env.local` and fill in your Supabase project:

```
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
```

Leave them empty to keep everything on-device. Server setup is in [backend.md](backend.md).

## Deploying

`vercel.json` is set up for Vercel (Vite preset, `dist/` output, no-cache for `sw.js`). Any static host works.
