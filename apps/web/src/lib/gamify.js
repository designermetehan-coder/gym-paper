// Oyunlaştırma (GM-01/02/03/04/08): saf fonksiyonlar. React ya da depolama bağımlılığı yok, birim testleriyle sınanır.
import { scheduleAt } from './schedule'

const pad = (n) => String(n).padStart(2, '0')
export const keyOfDate = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const parse = (k) => { const [y, m, d] = String(k).split('-').map(Number); return new Date(y, m - 1, d) }
export const shiftKey = (k, n) => { const d = parse(k); d.setDate(d.getDate() + n); return keyOfDate(d) }
const dow = (k) => (parse(k).getDay() + 6) % 7 // Pzt = 0
const fin = (v) => (Number.isFinite(+v) ? +v : 0)

/** ISO hafta anahtarı: "2026-W43" */
export function isoWeek(k) {
  const d = parse(k)
  d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7)) // haftanın perşembesi
  const y = d.getFullYear()
  const w1 = new Date(y, 0, 4)
  const w = 1 + Math.round(((d - w1) / 864e5 - 3 + ((w1.getDay() + 6) % 7)) / 7)
  return `${y}-W${pad(w)}`
}

const dayEntries = (L) => [...(L?.entries || []), ...(L?.extras || [])]
const dayMacros = (L) => dayEntries(L).reduce((a, e) => ({ kcal: a.kcal + fin(e.kcal), p: a.p + fin(e.p) }), { kcal: 0, p: 0 })

/** Günün "aktif" sayılması: yemek kaydı, tamamlanan antrenman ya da adım hedefi */
export function isActive(db, k) {
  const L = db.log?.[k]
  if (!L) return false
  return dayEntries(L).length > 0 || !!L.workoutDone || fin(L.steps) >= fin(db.targets?.steps || 8000)
}

/* ---------- GM-01 Günlük halkalar ---------- */
// Kalori: hedefin %90–105'i "kapalı". %110 üstü uyarı tonu; az yemek ödüllendirilmez.
export function rings(db, k) {
  const T = db.targets || {}
  const m = dayMacros(db.log?.[k])
  const steps = fin(db.log?.[k]?.steps)
  const kr = T.kcal > 0 ? m.kcal / T.kcal : 0
  const pr = T.p > 0 ? m.p / T.p : 0
  const sr = T.steps > 0 ? steps / T.steps : 0
  return {
    kcal: { value: m.kcal, target: T.kcal, ratio: kr, closed: kr >= 0.9 && kr <= 1.05, over: kr > 1.1 },
    protein: { value: m.p, target: T.p, ratio: pr, closed: pr >= 1 },
    steps: { value: steps, target: T.steps, ratio: sr, closed: sr >= 1 },
  }
}

/* ---------- GM-02 Seri ve dondurma ---------- */
// Seri bugün ya da dün biten ardışık aktif günler. Her ISO haftada 1 dondurma hakkı; tek bir boş günü köprüler.
// Dönüş: { count, activeToday, frozen: [k], pending: {hafta: gün} (henüz kaydedilmemiş dondurmalar), freezeReady }
export function streak(db, today) {
  const used = { ...(db.streak?.freezes || {}) }
  const pending = {}
  const frozen = []
  const activeToday = isActive(db, today)
  const earliest = Object.keys(db.log || {}).sort()[0]
  let k = activeToday ? today : shiftKey(today, -1)
  let count = 0
  for (let i = 0; i < 800 && earliest && k >= earliest; i++) {
    if (isActive(db, k)) { count++; k = shiftKey(k, -1); continue }
    // boş gün: bu hafta dondurma kullanılabiliyor mu ve öncesinde aktif bir gün var mı (köprü)?
    const w = isoWeek(k)
    const can = (used[w] === k || used[w] == null) && count > 0 && isActive(db, shiftKey(k, -1))
    if (!can) break
    if (used[w] == null) { used[w] = k; pending[w] = k }
    frozen.push(k); count++; k = shiftKey(k, -1)
  }
  const wNow = isoWeek(today)
  return { count, activeToday, frozen, pending, freezeReady: used[wNow] == null }
}

/** Son n gün: [{k, active, frozen}] (eskiden yeniye) */
export function streakCalendar(db, today, n = 30) {
  const s = streak(db, today)
  const fz = new Set([...s.frozen, ...Object.values(db.streak?.freezes || {})])
  return Array.from({ length: n }, (_, i) => { const k = shiftKey(today, i - n + 1); return { k, active: isActive(db, k), frozen: !isActive(db, k) && fz.has(k) } })
}

/* ---------- GM-04 Haftalık skor ---------- */
// Son 7 gün (bugün dahil): antrenman %35, protein %35, su %15, adım %15. Planlı antrenman yoksa ağırlıklar yeniden dağıtılır.
const plannedOn = (db, k) => {
  const L = db.log?.[k]
  const id = L?.programId !== undefined ? L.programId : scheduleAt(db, k)[dow(k)]
  const p = id && (db.programs || []).find((x) => x.id === id)
  return p ? (p.blocks || []).some((b) => (b.kind === 'single' ? b.ex : b.exs?.length)) : !!id // hareketsiz program dinlenme sayılır
}
export function weekScore(db, end) {
  const T = db.targets || {}
  const days = Array.from({ length: 7 }, (_, i) => shiftKey(end, i - 6))
  let planned = 0, done = 0, prot = 0, water = 0, steps = 0
  for (const k of days) {
    const L = db.log?.[k] || {}
    const pl = plannedOn(db, k)
    if (pl) planned++
    if (L.workoutDone) done++
    if (T.p > 0 && dayMacros(L).p >= 0.9 * T.p) prot++
    if (T.water > 0 && fin(L.water) >= T.water) water++
    if (T.steps > 0 && fin(L.steps) >= T.steps) steps++
  }
  const parts = [
    { key: 'workout', label: 'Antrenman', w: 35, v: planned ? Math.min(1, done / planned) : null, detail: planned ? `${done}/${planned} gün` : 'Plan yok' },
    { key: 'protein', label: 'Protein', w: 35, v: prot / 7, detail: `${prot}/7 gün` },
    { key: 'water', label: 'Su', w: 15, v: water / 7, detail: `${water}/7 gün` },
    { key: 'steps', label: 'Adım', w: 15, v: steps / 7, detail: `${steps}/7 gün` },
  ]
  const act = parts.filter((p) => p.v != null)
  const W = act.reduce((a, p) => a + p.w, 0) || 1
  const score = Math.round(act.reduce((a, p) => a + p.v * p.w, 0) / W * 100)
  return { score, parts, from: days[0], to: end }
}
export function weekScoreDelta(db, end) {
  const cur = weekScore(db, end), prev = weekScore(db, shiftKey(end, -7))
  return { ...cur, prev: prev.score, delta: cur.score - prev.score }
}

/* ---------- GM-03 Kilo kademesi ---------- */
// Ulaşılan ama kutlanmamış hedefler (en düşük olan önce gösterilir)
export function pendingGoals(db, cur, hasMeasure) {
  if (cur == null || !hasMeasure) return []
  const seen = new Set((db.celebrated || []).map(Number))
  return [...(db.targets?.goals || [])].map(Number).filter((g) => cur <= g && !seen.has(g)).sort((a, b) => a - b)
}
