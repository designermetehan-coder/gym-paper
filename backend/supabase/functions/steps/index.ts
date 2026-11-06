// iOS Kestirmeler'den gelen adım sayısını kaydeder. Kimlik: kişiye özel anahtar (balli_step_tokens).
// Dağıtım: verify_jwt = false (kimlik doğrulamayı anahtar yapar).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4'

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  if (req.method !== 'POST') return json({ error: 'POST gerekli' }, 405)
  let body: Record<string, unknown>
  try { body = await req.json() } catch { return json({ error: 'Geçersiz JSON' }, 400) }
  const token = String(body.token ?? '').trim()
  // Kestirmeler sayıyı '8.432' ya da '8432,0' gibi gönderebilir
  const raw = String(body.steps ?? '').replace(/[^0-9.,]/g, '')
  const steps = Math.round(Number(raw.includes(',') ? raw.replace(/\./g, '').replace(',', '.') : raw.split('.').length > 2 ? raw.replace(/\./g, '') : raw))
  const date = /^\d{4}-\d{2}-\d{2}$/.test(String(body.date ?? '')) ? String(body.date) : new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Istanbul' })
  if (!/^[a-f0-9]{36}$/.test(token)) return json({ error: 'Anahtar geçersiz' }, 401)
  if (!Number.isFinite(steps) || steps < 0 || steps > 300000) return json({ error: 'Adım sayısı geçersiz' }, 400)
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
  const { data: t } = await db.from('balli_step_tokens').select('user_id').eq('token', token).maybeSingle()
  if (!t) return json({ error: 'Anahtar bulunamadı' }, 401)
  const { data: cur } = await db.from('balli_steps').select('steps').eq('user_id', t.user_id).eq('date', date).maybeSingle()
  if (!cur || steps > cur.steps) {
    const { error } = await db.from('balli_steps').upsert({ user_id: t.user_id, date, steps, updated_at: new Date().toISOString() })
    if (error) return json({ error: 'Kaydedilemedi' }, 500)
  }
  return json({ ok: true, date, steps: Math.max(steps, cur?.steps ?? 0) })
})
