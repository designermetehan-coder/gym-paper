# Security policy

## Supported versions

Only the latest App Store release and the `main` branch receive fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report it through [GitHub private vulnerability reporting](https://github.com/designermetehan-coder/gym-paper/security/advisories/new) with:

- a description of the issue and its impact,
- steps to reproduce,
- the affected app, version and platform.

You will get an acknowledgement within 72 hours and a status update within 7 days.

## Scope notes

- GYM Paper has no user accounts and stores health data on-device and in the user's own iCloud.
- The Supabase anon key used by the optional backend is public by design; access is enforced with row level security and RPC-only tables (see `backend/supabase`). Reports about the anon key being visible are out of scope.
- Never commit real keys. Use `.env.local`, `Config/Signing.local.xcconfig` and Supabase secrets, which are git-ignored.
