// İlerleme ve rekor hesapları. Hareketler program kopyalarında farklı id alabildiği için
// geçmiş, hareketin normalize edilmiş ADIYLA eşleştirilir.
import { norm, num, keyOf, todayKey } from './utils'

const LOWER = new Set(['bacak', 'kalca', 'baldir'])
export const e1rm = (kg, reps) => kg * (1 + reps / 30) // Epley

// id → hareket (arşivli ve geçici programlar dahil)
export function exIndex(db) {
  const m = new Map()
  for (const p of db.programs || []) for (const b of p.blocks || []) for (const e of (b.kind === 'single' ? [b.ex] : b.exs || [])) if (e?.id) m.set(e.id, e)
  return m
}

// Bir günün tamamlanmış, tekrar birimli setleri: [{name, ex, kg, reps}]
function doneSets(L, idx) {
  const out = []
  for (const [eid, arr] of Object.entries(L?.sets || {})) {
    const ex = idx.get(eid)
    if (!ex || ex.unit !== 'tekrar' || !Array.isArray(arr)) continue
    for (const s of arr) {
      if (!s?.done) continue
      const kg = num(s.kg), reps = num(s.reps) || num(ex.reps)
      if (kg > 0 && reps > 0) out.push({ name: ex.name, key: norm(ex.name), ex, kg, reps })
    }
  }
  return out
}

// Bütün hareketlerin seans geçmişi: Map<key, [{date, name, sets, best, vol}]> (eskiden yeniye)
export function histories(db) {
  const idx = exIndex(db)
  const H = new Map()
  for (const date of Object.keys(db.log || {}).sort()) {
    const by = new Map()
    for (const s of doneSets(db.log[date], idx)) { if (!by.has(s.key)) by.set(s.key, []); by.get(s.key).push(s) }
    for (const [key, sets] of by) {
      const best = sets.reduce((a, s) => { const v = e1rm(s.kg, s.reps); return !a || v > a.e1rm ? { kg: s.kg, reps: s.reps, e1rm: v } : a }, null)
      if (!H.has(key)) H.set(key, [])
      H.get(key).push({ date, name: sets[0].name, sets, best, vol: sets.reduce((a, s) => a + s.kg * s.reps, 0) })
    }
  }
  return H
}

export const historyOf = (db, name) => histories(db).get(norm(name)) || []

// Rekorlar: önceki en iyi e1RM'i geçen seanslar (ilk seans rekor sayılmaz)
export function prList(db, H = histories(db)) {
  const out = []
  for (const list of H.values()) {
    let best = 0
    list.forEach((s, i) => { if (i > 0 && s.best.e1rm > best + 0.01) out.push({ date: s.date, name: s.name, kg: s.best.kg, reps: s.best.reps, e1rm: s.best.e1rm, prev: best }); best = Math.max(best, s.best.e1rm) })
  }
  return out.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.e1rm - a.e1rm))
}
export const prsOn = (db, date) => prList(db).filter((p) => p.date === date)
export const isPR = (db, name, date) => prsOn(db, date).some((p) => norm(p.name) === norm(name))

// Hafta başı (Pazartesi) anahtarı
export function weekStart(key = todayKey(), offset = 0) {
  const [y, m, d] = key.split('-').map(Number)
  const t = new Date(y, m - 1, d)
  t.setDate(t.getDate() - ((t.getDay() + 6) % 7) + offset * 7)
  return keyOf(t)
}
const addDays = (key, n) => { const [y, m, d] = key.split('-').map(Number); const t = new Date(y, m - 1, d + n); return keyOf(t) }
const inWeek = (date, ws) => date >= ws && date < addDays(ws, 7)

const dayDone = (L, idx) => !!L?.workoutDone || doneSets(L, idx).length > 0 || Object.values(L?.exDone || {}).some(Boolean)

// Son n haftanın hacmi ve antrenman sayısı (eskiden yeniye)
export function weeks(db, n = 8) {
  const idx = exIndex(db)
  const cur = weekStart()
  const W = Array.from({ length: n }, (_, i) => ({ start: weekStart(cur, i - n + 1), vol: 0, workouts: 0 }))
  for (const [date, L] of Object.entries(db.log || {})) {
    const w = W.find((x) => inWeek(date, x.start)); if (!w) continue
    w.vol += doneSets(L, idx).reduce((a, s) => a + s.kg * s.reps, 0)
    if (dayDone(L, idx)) w.workouts++
  }
  return W
}

// Ardışık en az 1 antrenmanlı hafta sayısı; bu hafta henüz boşsa seri bozulmaz
export function streakWeeks(db) {
  const idx = exIndex(db)
  const done = new Set(Object.entries(db.log || {}).filter(([, L]) => dayDone(L, idx)).map(([d]) => weekStart(d)))
  let off = done.has(weekStart()) ? 0 : -1, n = 0
  while (done.has(weekStart(todayKey(), off))) { n++; off-- }
  return n
}

// Ağırlık önerisi: son seansta hedef setlerin hepsi hedef tekrarla yapıldıysa artır
export function suggestKg(db, ex, date) {
  if (!ex || ex.unit !== 'tekrar') return null
  const list = historyOf(db, ex.name).filter((s) => s.date < date)
  const last = list.at(-1)
  if (!last) return null
  const top = Math.max(...last.sets.map((s) => s.kg))
  const target = num(ex.reps) || 0
  const hit = last.sets.length >= (num(ex.sets) || 1) && last.sets.filter((s) => s.kg >= top).every((s) => s.reps >= target) && last.sets.every((s) => s.reps >= target)
  const inc = LOWER.has(norm(ex.muscle)) ? 5 : 2.5
  return { kg: hit ? top + inc : top, up: hit, last }
}

/* ---------- Güç seviyesi (GM-06) ----------
   Eşikler: Strength Level (strengthlevel.com) ortalama kullanıcı standartlarından yuvarlanmış
   1RM / vücut ağırlığı oranları. Sırasıyla Başlangıç, Acemi, Orta, İleri, Elit seviyesine giriş eşiği.
   Barfiks/çene çekme: tek sette yapılan en çok tekrar (ek ağırlıksız) ile ölçülür.
   Dumbbell, makine, incline ve yardımlı varyantlar dahil edilmez: oranlar halter hareketleri için geçerli. */
export const LEVELS = ['Başlangıç', 'Acemi', 'Orta', 'İleri', 'Elit']
export const LIFTS = [
  { id: 'bench', name: 'Bench press', names: ['barbell bench press', 'bench press', 'flat bench press'], m: [0.5, 0.75, 1.0, 1.5, 2.0], f: [0.25, 0.5, 0.75, 1.0, 1.5] },
  { id: 'squat', name: 'Squat', names: ['back squat', 'squat', 'barbell squat', 'barbell back squat', 'high bar squat', 'low bar squat'], m: [0.75, 1.25, 1.5, 2.25, 2.75], f: [0.5, 0.75, 1.25, 1.5, 2.0] },
  { id: 'deadlift', name: 'Deadlift', names: ['deadlift', 'conventional deadlift', 'barbell deadlift', 'sumo deadlift'], m: [1.0, 1.5, 2.0, 2.5, 3.0], f: [0.5, 1.0, 1.25, 1.75, 2.5] },
  { id: 'ohp', name: 'Overhead press', names: ['overhead press', 'military press', 'barbell overhead press', 'standing overhead press', 'barbell shoulder press', 'ohp'], m: [0.35, 0.55, 0.75, 1.05, 1.35], f: [0.2, 0.35, 0.5, 0.75, 1.0] },
  { id: 'row', name: 'Barbell row', names: ['barbell row', 'bent over row', 'barbell bent over row', 'pendlay row'], m: [0.5, 0.75, 1.0, 1.5, 1.75], f: [0.25, 0.4, 0.65, 0.9, 1.2] },
  { id: 'pullup', name: 'Barfiks', names: ['pull up', 'pullup', 'chin up', 'chinup', 'barfiks', 'wide grip pull up', 'neutral grip pull up'], reps: true, m: [1, 5, 11, 18, 25], f: [1, 2, 5, 10, 16] },
]
export const liftOf = (name) => { const n = norm(name); return LIFTS.find((l) => l.names.includes(n)) || null }

// Vücut ağırlığı: son ölçüm, yoksa başlangıç kilosu
export function bodyweight(db) {
  const m = [...(db.measures || [])].filter((x) => num(x.kg) > 0 && x.date).sort((a, b) => (a.date < b.date ? -1 : 1)).at(-1)
  return num(m?.kg) || num(db.profile?.startKg) || 0
}

// Değeri (oran ya da tekrar) seviyeye çevirir. idx: 0..4, -1 = Başlangıç eşiğinin de altı
export function levelFor(value, th) {
  let idx = -1
  th.forEach((t, i) => { if (value >= t - 1e-9) idx = i })
  const next = idx + 1 < th.length ? th[idx + 1] : null
  const from = idx >= 0 ? th[idx] : 0
  const pct = next == null ? 1 : Math.max(0, Math.min(1, (value - from) / (next - from || 1)))
  return { idx: Math.max(0, idx), label: LEVELS[Math.max(0, idx)], next, nextLabel: next != null ? LEVELS[idx + 1] : null, pct }
}

// Barfiks için en çok tekrar (tamamlanmış set, ek ağırlıksız da sayılır)
function maxReps(db, lift) {
  const idx = exIndex(db); let best = 0, date = null
  for (const [d, L] of Object.entries(db.log || {})) for (const [eid, arr] of Object.entries(L?.sets || {})) {
    const ex = idx.get(eid); if (!ex || !lift.names.includes(norm(ex.name)) || !Array.isArray(arr)) continue
    for (const s of arr) if (s?.done) { const r = num(s.reps) || num(ex.reps); if (r > best) { best = r; date = d } }
  }
  return { best, date }
}

// Ana hareketlerin güç seviyeleri. sex: 'm' | 'f' (yoksa null döner)
export function strengthLevels(db, H = histories(db)) {
  const sex = db.profile?.sex
  const bw = bodyweight(db)
  if (sex !== 'm' && sex !== 'f') return { need: 'sex', bw, rows: [] }
  const rows = []
  for (const lift of LIFTS) {
    const th = lift[sex]
    if (lift.reps) {
      const { best, date } = maxReps(db, lift)
      if (!best) continue
      const lv = levelFor(best, th)
      rows.push({ lift, value: best, unit: 'tekrar', date, ...lv, toNext: lv.next != null ? Math.max(0, lv.next - best) : 0 })
      continue
    }
    if (!bw) continue
    let best = null
    for (const n of lift.names) for (const s of H.get(n) || []) if (!best || s.best.e1rm > best.e1rm) best = { ...s.best, date: s.date }
    if (!best) continue
    const ratio = best.e1rm / bw
    const lv = levelFor(ratio, th)
    rows.push({ lift, value: best.e1rm, ratio, unit: 'kg', date: best.date, ...lv, toNext: lv.next != null ? Math.max(0, lv.next * bw - best.e1rm) : 0 })
  }
  return { need: bw ? null : 'bw', bw, rows }
}

// Bir hareketin seviyesi (ExerciseSheet için)
export function levelOfExercise(db, name) {
  const lift = liftOf(name); if (!lift) return null
  const r = strengthLevels(db)
  return r.rows.find((x) => x.lift.id === lift.id) || null
}

// Seans içi rekor: bu set, bu tarihten önceki en iyi e1RM'i geçiyor mu? (ilk seans rekor sayılmaz)
export function beatsPrevBest(db, name, date, kg, reps) {
  const prev = historyOf(db, name).filter((s) => s.date < date)
  if (!prev.length) return false
  const best = Math.max(...prev.map((s) => s.best.e1rm))
  return num(kg) > 0 && num(reps) > 0 && e1rm(num(kg), num(reps)) > best + 0.01
}
