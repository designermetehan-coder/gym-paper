# Backend (optional)

Everything in GYM Paper works without a server. The Supabase project in `backend/supabase` adds:

| Piece | File | Used by |
|---|---|---|
| Cloud backup tables with row level security | `schema.sql` | Web app (`src/lib/cloud.js`) |
| Steps endpoint for an iOS Shortcuts automation | `functions/steps`, `schema.sql` | Shortcuts, results shown in the web app |
| FatSecret food search proxy | `functions/fatsecret` | iOS app, web app |
| Friends' step leaderboard (RPC only) | `social.sql` | iOS app, disabled in the current release |

## Setup

1. Create a project at [supabase.com](https://supabase.com) and install the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started).
2. Apply the SQL. Paste `schema.sql` (and optionally `social.sql`) into the dashboard's SQL editor, or run them with `psql`. Both scripts are idempotent:
   ```sh
   psql "$SUPABASE_DB_URL" -f backend/supabase/schema.sql
   psql "$SUPABASE_DB_URL" -f backend/supabase/social.sql   # optional
   ```
   Then link the CLI from the `backend` folder: `cd backend && supabase link --project-ref <project-ref>`.
3. Set function secrets:
   ```sh
   supabase secrets set FATSECRET_CLIENT_ID=... FATSECRET_CLIENT_SECRET=...
   # optional: FATSECRET_SCOPE=premier|basic (default premier), FATSECRET_REGION=TR
   ```
   `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to functions automatically.
4. Deploy the functions:
   ```sh
   supabase functions deploy fatsecret
   supabase functions deploy steps --no-verify-jwt   # authenticates with a per-user token
   ```
5. Point the clients at your project:
   - Web: `apps/web/.env.local` (see [web.md](web.md#cloud-backup-optional))
   - iOS: `supabaseURL` and `anonKey` in `Balli/Services/FoodService.swift` (and `SocialView.swift` if you enable the leaderboard)

## Security model

- Clients only ever hold the **anon** key, which is public by design.
- Backup tables have row level security: users can read and write only their own rows.
- Social tables have RLS enabled with no policies; all access goes through `security definer` RPCs.
- Third-party credentials (FatSecret) live only in Supabase secrets.
- Never commit the service role key or `.env.local`.
