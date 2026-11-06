// Supabase connection for optional cloud backup.
// Leave empty to run fully on-device (IndexedDB only). To enable, set
// VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in apps/web/.env.local (see .env.example).
// The anon key is public by design; access is enforced by row level security on the server.
export const SUPABASE_URL = ''
export const SUPABASE_ANON_KEY = ''
