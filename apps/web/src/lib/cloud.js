// Bulut senkronu (Supabase). Uygulama önce cihazda çalışır (IndexedDB); internet varken veriler
// kişinin hesabına yedeklenir, yeni cihazda giriş yapınca geri gelir. Son değişiklik kazanır.
import { get, set } from 'idb-keyval'
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config'

const URL_ = import.meta.env.VITE_SUPABASE_URL || SUPABASE_URL
const KEY_ = import.meta.env.VITE_SUPABASE_ANON_KEY || SUPABASE_ANON_KEY
export const cloudEnabled = !!(URL_ && KEY_)

const clients = new Map()
async function client(pid) {
  if (!cloudEnabled) return null
  if (clients.has(pid)) return clients.get(pid)
  const { createClient } = await import('@supabase/supabase-js')
  const c = createClient(URL_, KEY_, { auth: { storageKey: `balli-auth-${pid}`, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } })
  clients.set(pid, c)
  return c
}

const authErr = (e) => {
  const m = (e?.message || '').toLowerCase()
  if (m.includes('invalid login')) return 'E-posta ya da şifre hatalı.'
  if (m.includes('already registered') || m.includes('already been registered')) return 'Bu e-postayla zaten hesap var; giriş yap.'
  if (m.includes('password')) return 'Şifre en az 6 karakter olmalı.'
  if (m.includes('email not confirmed')) return 'E-posta onayı bekleniyor.'
  if (m.includes('rate')) return 'Çok sık denendi, biraz sonra tekrar dene.'
  return 'Bağlanılamadı. İnternetini kontrol edip tekrar dene.'
}
export async function signIn(pid, email, password) {
  const c = await client(pid)
  const { data, error } = await c.auth.signInWithPassword({ email, password })
  if (error) throw new Error(authErr(error))
  return { userId: data.user.id, email }
}
export async function signUp(pid, email, password) {
  const c = await client(pid)
  const { data, error } = await c.auth.signUp({ email, password })
  if (error) throw new Error(authErr(error))
  if (!data.session) throw new Error('Hesap oluşturuldu ama e-posta onayı açık. Kurulumda onayı kapatman gerekiyor.')
  return { userId: data.user.id, email }
}
// Şifre sıfırlama: e-postaya bağlantı gider; bağlantı uygulamayı #type=recovery ile açar
export async function requestPasswordReset(pid, email) {
  const c = await client(pid)
  const { error } = await c.auth.resetPasswordForEmail(email, { redirectTo: location.origin + '/' })
  if (error) throw new Error(authErr(error))
}
// URL'deki kurtarma oturumunu kurar; varsa e-postayı döner
export async function consumeRecovery(pid) {
  const h = new URLSearchParams(location.hash.slice(1))
  if (h.get('type') !== 'recovery' || !h.get('access_token')) return null
  const c = await client(pid)
  const { data, error } = await c.auth.setSession({ access_token: h.get('access_token'), refresh_token: h.get('refresh_token') })
  history.replaceState(null, '', location.pathname)
  if (error) throw new Error('Bağlantının süresi dolmuş. Yeniden şifre sıfırlama iste.')
  return data.user?.email || null
}
export async function updatePassword(pid, password) {
  const c = await client(pid)
  const { error } = await c.auth.updateUser({ password })
  if (error) throw new Error(authErr(error))
}
export async function signOut(pid) { const c = await client(pid); await c?.auth.signOut() }
export async function sessionUser(pid) {
  const c = await client(pid); if (!c) return null
  const { data } = await c.auth.getSession()
  return data.session?.user || null
}

/* ---- veri ----
   CR-10: Kayıtlar aylık parçalara bölünür: '<key>' = günlük hariç her şey, '<key>:log:YYYY-MM' = o ayın günleri.
   Gönderirken yalnız değişen aylar yüklenir. CR-22: key profil başına seçilebilir (varsayılan 'main'). */
const monthOf = (k) => k.slice(0, 7)
function splitLog(log = {}) {
  const m = {}
  for (const [d, v] of Object.entries(log)) (m[monthOf(d)] ??= {})[d] = v
  return m
}
export async function pullRemote(pid, key = 'main') {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return null
  const { data, error } = await c.from('balli_data').select('profile_key, data').eq('user_id', u.id).or(`profile_key.eq.${key},profile_key.like.${key}:log:*`)
  if (error) throw error
  const core = data?.find((r) => r.profile_key === key)?.data
  if (!core) return null
  const log = { ...(core.log || {}) } // eski tek parça yedekler günlüğü içinde taşır
  for (const r of data) if (r.profile_key !== key) Object.assign(log, r.data || {})
  return { ...core, log }
}
export async function pushRemote(pid, db, base = null, key = 'main') {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return false
  const now = new Date().toISOString()
  const { log, ...core } = db
  const months = splitLog(log), prev = base ? splitLog(base.log) : null
  const rows = [{ user_id: u.id, profile_key: key, data: core, updated_at: now }]
  // bulutta henüz parçası olmayan ay (eski tek parça yedek ya da ilk gönderim) her durumda yüklenir
  const { data: have } = await c.from('balli_data').select('profile_key').eq('user_id', u.id).like('profile_key', `${key}:log:%`)
  const existing = new Set((have || []).map((r) => r.profile_key.split(':log:')[1]))
  for (const [m, days] of Object.entries(months)) {
    if (prev && existing.has(m) && JSON.stringify(prev[m]) === JSON.stringify(days)) continue
    rows.push({ user_id: u.id, profile_key: `${key}:log:${m}`, data: days, updated_at: now })
  }
  // tümüyle silinen aylar
  const gone = prev ? Object.keys(prev).filter((m) => !months[m]) : []
  const { error } = await c.from('balli_data').upsert(rows)
  if (error) throw error
  if (gone.length) await c.from('balli_data').delete().eq('user_id', u.id).in('profile_key', gone.map((m) => `${key}:log:${m}`))
  await syncImages(c, u.id, db)
  return true
}
// Hesaptaki ayrı yedekleri listeler (CR-22)
export async function listBackups(pid) {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return []
  const { data } = await c.from('balli_data').select('profile_key, data->profile, updated_at').eq('user_id', u.id).not('profile_key', 'like', '%:log:%')
  return (data || []).map((r) => ({ key: r.profile_key, name: r.profile?.name || 'Profil', at: r.updated_at }))
}

/* ---- görseller (besin/tarif) ---- */
const imageIds = (db) => [...db.myFoods.map((f) => f.image), ...db.recipes.map((r) => r.image)].filter((x) => x?.startsWith?.('img-'))
async function syncImages(c, uid, db) {
  const done = new Set((await get('balli-cloud-imgs').catch(() => null)) || [])
  for (const id of imageIds(db)) {
    if (done.has(id)) continue
    const blob = await get(id); if (!blob) continue
    const { error } = await c.storage.from('balli-images').upload(`${uid}/${id}.jpg`, blob, { upsert: true, contentType: 'image/jpeg' })
    if (!error) done.add(id)
  }
  await set('balli-cloud-imgs', [...done])
}
export async function restoreImages(pid, db) {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return
  for (const id of imageIds(db)) {
    if (await get(id)) continue
    const { data } = await c.storage.from('balli-images').download(`${u.id}/${id}.jpg`)
    if (data) await set(id, data)
  }
}

/* ---- adım otomasyonu (iOS Kestirmeler → edge function) ---- */
export const STEPS_ENDPOINT = `${URL_}/functions/v1/steps`
export async function getStepsToken(pid, create = false) {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) throw new Error('Önce bulut yedeğine giriş yap.')
  const { data } = await c.from('balli_step_tokens').select('token').eq('user_id', u.id).maybeSingle()
  if (data?.token || !create) return data?.token || null
  const { data: d2, error } = await c.from('balli_step_tokens').insert({ user_id: u.id }).select('token').single()
  if (error) throw new Error('Anahtar oluşturulamadı.')
  return d2.token
}
export async function resetStepsToken(pid) {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return null
  await c.from('balli_step_tokens').delete().eq('user_id', u.id)
  return getStepsToken(pid, true)
}
export async function pullSteps(pid, since) {
  const c = await client(pid); const u = await sessionUser(pid); if (!u) return []
  const { data, error } = await c.from('balli_steps').select('date, steps').eq('user_id', u.id).gte('date', since)
  if (error) throw error
  return data || []
}

/* ---- hata kaydı (kişisel veri gönderilmez) ---- */
export async function reportError(msg, stack) {
  try {
    if (!cloudEnabled || !navigator.onLine) return
    const k = 'balli-err-' + String(msg).slice(0, 80)
    if (sessionStorage.getItem(k)) return
    sessionStorage.setItem(k, '1')
    await fetch(`${URL_}/rest/v1/balli_errors`, { method: 'POST', headers: { apikey: KEY_, Authorization: `Bearer ${KEY_}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify({ msg: String(msg).slice(0, 1000), stack: String(stack || '').slice(0, 4000), ua: navigator.userAgent.slice(0, 200), ver: import.meta.env.VITE_VER || 'web' }) })
  } catch {}
}
