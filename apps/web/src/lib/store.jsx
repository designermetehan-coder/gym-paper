import * as React from 'react'
import { produce, current, isDraft } from 'immer'
import { get, set, del } from 'idb-keyval'
import { seed } from './seed'
import { programsV2, SCHEDULE_V2, CYCLE_V2, PROGRAM_VERSION, templateFor } from './program'
import { dowOf, todayKey, uid, num, fmt1, keyOf } from './utils'
import { EPOCH, scheduleAt } from './schedule'
import { cloudEnabled, pullRemote, pushRemote, restoreImages } from './cloud'
import { mergeDb } from './merge'

const KEY = 'balli-db-v2'
const PKEY = 'balli-profiles'
const dbKey = (id) => `${KEY}:${id}`
const Ctx = React.createContext(null)
export const useApp = () => React.useContext(Ctx)

const DEF_TARGETS = { kcal: 1800, p: 120, c: 180, f: 60, water: 2500, steps: 8000, waterStep: 500 }
export const SCHEMA_VERSION = 5
// Eksik alanları tamamlar; kullanıcının programlarını asla silmez
export function migrate(d) {
  if (!d || typeof d !== 'object') throw new Error('Geçersiz veri')
  d = { ...d }
  d.log = d.log && typeof d.log === 'object' ? d.log : {}
  for (const k of ['measures', 'programs', 'myFoods', 'recipes', 'cycle', 'customExercises', 'mealTemplates']) d[k] = Array.isArray(d[k]) ? d[k].filter((x) => x != null) : []
  d.programs = d.programs.filter((p) => typeof p === 'object').map((p) => (Array.isArray(p.blocks) ? p : { ...p, blocks: [] }))
  d.schedule = d.schedule && typeof d.schedule === 'object' ? d.schedule : {}
  d.profile = { name: 'Profil', ...(d.profile || {}) }
  d.targets = { ...DEF_TARGETS, ...(d.targets || {}) }
  for (const k of Object.keys(DEF_TARGETS)) if (!(+d.targets[k] > 0)) d.targets[k] = DEF_TARGETS[k]
  if ((d.programsV || 0) < PROGRAM_VERSION) {
    d = d.programs.length ? { ...d, programsV: PROGRAM_VERSION } : { ...d, programs: programsV2(), schedule: SCHEDULE_V2, cycle: CYCLE_V2, cycleIdx: 0, programsV: PROGRAM_VERSION }
  }
  // süperset hareketlerinin set sayısı = tur sayısı
  if ((d.schemaVersion || 0) < 3) {
    d.programs = d.programs.map((p) => ({ ...p, blocks: (p.blocks || []).map((b) => (b.kind === 'superset' ? { ...b, rounds: Math.max(1, +b.rounds || 1), exs: (b.exs || []).map((e) => ({ ...e, sets: Math.max(1, +b.rounds || 1) })) } : b)) }))
    d.measures = d.measures.filter((m) => m && m.date)
    d.schemaVersion = 3
  }
  // v4: sıralı döngü kaldırıldı; haftalık plan tarihli geçmişe taşındı (geçmiş günler eski planı korur)
  if (!Array.isArray(d.scheduleHist) || !d.scheduleHist.length) {
    const days = { 0: null, 1: null, 2: null, 3: null, 4: null, 5: null, 6: null, ...d.schedule }
    // döngü modunda geçmiş günler yalnız günlükteki programId ile görünüyordu; haftalık plan bugünden başlasın
    d.scheduleHist = d.planMode === 'cycle'
      ? [{ from: EPOCH, days: { 0: null, 1: null, 2: null, 3: null, 4: null, 5: null, 6: null } }, { from: todayKey(), days }]
      : [{ from: EPOCH, days }]
  }
  if (d.planMode !== 'weekly') d.planMode = 'weekly'
  // v5 onarım: ileri bir haftadan başlatılmış "her hafta" planı bu haftanın aynı gününden geçerli olsun
  if ((d.schemaVersion || 0) < 5 && Array.isArray(d.scheduleHist) && d.scheduleHist.length > 1) {
    const today = todayKey(), H = d.scheduleHist
    for (let k = 0; k < 7; k++) {
      if (scheduleAt({ scheduleHist: H }, today)[k]) continue
      const fut = H.find((h) => h.from > today && h.days[k])
      if (!fut) continue
      const from = nextOnOrAfter(today, k)
      if (from >= fut.from) continue
      if (!H.some((h) => h.from === from)) { H.push({ from, days: { ...scheduleAt({ scheduleHist: H }, from) } }); H.sort((x, y) => (x.from < y.from ? -1 : 1)) }
      for (const h of H) if (h.from >= from && h.from < fut.from) h.days[k] = fut.days[k]
    }
  }
  if ((d.schemaVersion || 0) < SCHEMA_VERSION) d.schemaVersion = SCHEMA_VERSION
  if (!d.onboarding && Object.keys(d.log).length > 3) d.onboarding = { dismissed: true } // eski kullanıcıya başlangıç kartı gösterme
  if (!Array.isArray(d.targets.goals)) {
    const isMete = d.profile?.name === 'Mete'
    d = { ...d, targets: { ...d.targets, goals: isMete ? [95, 90, 85] : d.targets.goalKg ? [d.targets.goalKg] : [] }, profile: { ...d.profile, startKg: d.profile.startKg ?? (isMete ? 125 : null) } }
  }
  return d
}

export function AppProvider({ children }) {
  const [db, setDb] = React.useState(null)
  const [profiles, setProfiles] = React.useState(null) // {active, list:[{id,name}]}
  const [sheets, setSheets] = React.useState([])
  const [tab, setTab] = React.useState('today')
  const [session, setSession] = React.useState(null)
  const activeRef = React.useRef(null)
  const [toasts, setToasts] = React.useState([])
  const [fatal, setFatal] = React.useState(null)
  if (fatal) throw fatal // ErrorBoundary kurtarma ekranını gösterir; veri ezilmez
  const toast = React.useCallback((msg, opts = {}) => {
    const id = uid(); const life = opts.undo ? 4500 : 1600
    const dismiss = () => { setToasts((x) => x.map((y) => (y.id === id ? { ...y, out: true } : y))); setTimeout(() => setToasts((x) => x.filter((y) => y.id !== id)), 300) }
    let used = false
    const undo = opts.undo ? () => { used = true; opts.undo(); dismiss() } : null
    const kind = opts.kind || (/okunamad|alınamad|yapılamad|olmad|bulunamad|hata|geçersiz|başarısız|bağlanılamad|değil\./i.test(msg) ? 'error' : undefined)
    setToasts((x) => [...x.slice(-1), { id, msg, undo, kind }])
    setTimeout(() => { dismiss(); if (!used) opts.onExpire?.() }, life)
  }, [])
  const dbRef = React.useRef(null)
  const clearToasts = React.useCallback(() => setToasts([]), [])

  React.useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        let P = await get(PKEY)
        if (!P) {
          const legacy = await get(KEY)
          if (legacy && legacy.v === 2) { P = { active: 'p1', list: [{ id: 'p1', name: legacy.profile?.name || 'Profil' }] }; await set(dbKey('p1'), legacy); await set(PKEY, P) }
        }
        if (!alive) return
        if (!P) { setProfiles({ active: null, list: [] }); return }
        const d = await get(dbKey(P.active))
        activeRef.current = P.active
        let m
        try { m = migrate(d || seed('blank')) } catch (e) { if (alive) setFatal(e); return }
        setProfiles(P); setDb(m)
      } catch { if (alive) { setProfiles({ active: null, list: [] }) } }
    })()
    return () => { alive = false }
  }, [])
  React.useEffect(() => {
    if (!db || !activeRef.current) return
    const id = activeRef.current
    set(dbKey(id), db).catch(() => {}) // hemen yaz: uygulama aniden kapanırsa son dokunuş kaybolmasın
  }, [db])
  React.useEffect(() => { // uygulama kapanırken/arka plana alınırken bekleyen kaydı hemen yaz
    const flush = () => { const d = dbRef.current, id = activeRef.current; if (d && id) set(dbKey(id), d).catch(() => {}) }
    const vis = () => document.visibilityState === 'hidden' && flush()
    window.addEventListener('pagehide', flush); document.addEventListener('visibilitychange', vis)
    return () => { window.removeEventListener('pagehide', flush); document.removeEventListener('visibilitychange', vis) }
  }, [])

  /* ---- bulut senkronu ---- */
  const [sync, setSync] = React.useState({ status: 'idle', at: null })
  // Senkron (RM-04): son eşitlenen durum (base) cihazda saklanır; iki taraf da değiştiyse kayıt düzeyinde birleştirilir
  const baseKey = (pid) => `balli-syncbase:${pid}`
  const busy = React.useRef(null)
  const pull = React.useCallback(() => {
    if (busy.current) return busy.current
    const run = (async () => {
      const pid = activeRef.current
      const local = dbRef.current
      if (!cloudEnabled || !pid || !navigator.onLine || !local?.cloud) return
      try {
        setSync((x) => ({ ...x, status: 'syncing' }))
        const base = await get(baseKey(pid)).catch(() => null)
        const bAt = base?.updatedAt || 0
        const key = local.cloud?.key || 'main'
        const remote = await pullRemote(pid, key)
        if (activeRef.current !== pid) return
        const latest = dbRef.current
        const remoteChanged = !!remote && (remote.updatedAt || 0) > bAt
        const localChanged = (latest.updatedAt || 0) > bAt
        let next = latest
        if (remoteChanged && localChanged) next = migrate(mergeDb(base, latest, remote))
        else if (remoteChanged) next = migrate({ ...remote, cloud: latest.cloud })
        if (next !== latest) {
          setDb((cur) => (cur === latest ? next : migrate(mergeDb(base, cur, remote))))
          restoreImages(pid, next).catch(() => {})
        }
        if (localChanged || !remote) { await pushRemote(pid, next, remote ? base : null, key) }
        await set(baseKey(pid), next)
        setSync({ status: 'ok', at: Date.now() })
      } catch { setSync((x) => ({ ...x, status: 'error' })) }
    })()
    busy.current = run.finally(() => { busy.current = null })
    return busy.current
  }, [])
  const flushPush = pull
  React.useEffect(() => { // açılışta ve uygulamaya dönünce çek
    if (!db?.cloud) return
    pull()
    const on = () => document.visibilityState === 'visible' && pull()
    document.addEventListener('visibilitychange', on); window.addEventListener('online', pull)
    return () => { document.removeEventListener('visibilitychange', on); window.removeEventListener('online', pull) }
  }, [!!db?.cloud, profiles?.active]) // eslint-disable-line
  React.useEffect(() => { // değişince 3 sn sonra eşitle (birleştirerek)
    if (!cloudEnabled || !db?.cloud) return
    const t = setTimeout(() => { if (!navigator.onLine) setSync((x) => ({ ...x, status: 'offline' })); else pull() }, 3000)
    return () => clearTimeout(t)
  }, [db, pull])

  dbRef.current = db
  const update = React.useCallback((fn) => setDb((d) => produce(d, (draft) => { fn(draft); draft.updatedAt = Date.now() })), [])
  // Geri alınabilir işlem: yalnız bu işlemin ters yamasını uygular (sonraki değişiklikler korunur)
  const withUndo = React.useCallback((msg, fn, kind = 'delete', after) => {
    const pid = activeRef.current
    // Geri alma = "sonrası → öncesi" değişikliğini güncel duruma kayıt düzeyinde uygulamak (3 yönlü birleştirme).
    // Böylece pencere içinde yapılan başka düzenlemeler ve silmeler korunur.
    let before = null, afterState = null
    setDb((cur) => { before = cur; afterState = produce(cur, (d) => { fn(d); d.updatedAt = Date.now() }); return afterState })
    let undone = false
    toast(msg, { kind, undo: () => {
      if (undone || activeRef.current !== pid || !before) return
      undone = true
      setDb((cur) => { try { return { ...mergeDb(afterState, { ...cur, updatedAt: Date.now() + 1 }, before), updatedAt: Date.now() } } catch { return cur } })
    }, onExpire: () => { if (!undone) after?.() } })
  }, [toast])
  const open = React.useCallback((kind, props = {}) => setSheets((s) => [...s, { key: uid(), kind, props }]), [])
  const closeSheet = React.useCallback((key) => setSheets((s) => s.filter((x) => x.key !== key)), [])
  const replace = React.useCallback((d) => setDb((cur) => migrate({ ...d, cloud: cur?.cloud, updatedAt: Date.now() })), [])
  const reset = React.useCallback(() => setDb((d) => migrate({ ...seed('blank', { name: d?.profile?.name }), profile: d?.profile, targets: d?.targets, cloud: d?.cloud, updatedAt: Date.now() })), [])

  const switchProfile = React.useCallback(async (id) => {
    setToasts([]); await flushPush()
    if (db && activeRef.current) await set(dbKey(activeRef.current), db)
    const d = await get(dbKey(id))
    const P = { ...profiles, active: id }
    await set(PKEY, P)
    activeRef.current = id
    setSession(null); setSheets([]); setTab('today')
    setProfiles(P); setDb(migrate(d || seed('blank')))
  }, [db, profiles])
  const createProfile = React.useCallback(async (opts) => {
    setToasts([]); await flushPush()
    if (db && activeRef.current) await set(dbKey(activeRef.current), db)
    if (opts.data) {
      const id = opts.id || uid(); const d = migrate({ ...opts.data, cloud: opts.cloud })
      await set(dbKey(id), d)
      const P = { active: id, list: [...(profiles?.list || []), { id, name: d.profile?.name || 'Profil' }] }
      await set(PKEY, P); activeRef.current = id; if (opts.cloud) await set(baseKey(id), d)
      setSession(null); setSheets([]); setTab('today'); setProfiles(P); setDb(d)
      restoreImages(id, d).catch(() => {})
      return
    }
    let d = opts.template === 'mete' ? { ...seed(), profile: { name: opts.name, startKg: opts.startKg || 125 } } : seed('blank', opts)
    const T = templateFor(opts.template); if (opts.template !== 'mete' && T?.fn) d = { ...d, ...T.fn() }
    const id = opts.id || uid()
    d = { ...d, updatedAt: Date.now(), ...(opts.cloud ? { cloud: opts.cloud } : {}) }
    await set(dbKey(id), d)
    const P = { active: id, list: [...(profiles?.list || []), { id, name: opts.name }] }
    await set(PKEY, P)
    activeRef.current = id
    setSession(null); setSheets([]); setTab('today')
    setProfiles(P); setDb(d)
  }, [db, profiles])
  const renameProfile = React.useCallback((name, id) => {
    const target = id || activeRef.current
    setProfiles((P) => ({ ...P, list: P.list.map((x) => (x.id === target ? { ...x, name } : x)) }))
    if (target === activeRef.current) setDb((d) => (d && d.profile?.name !== name ? produce(d, (x) => { x.profile.name = name; x.updatedAt = Date.now() }) : d))
    else get(dbKey(target)).then((d) => d && set(dbKey(target), { ...d, profile: { ...d.profile, name }, updatedAt: Date.now() })).catch(() => {})
  }, [])
  React.useEffect(() => { if (profiles?.list?.length) set(PKEY, profiles).catch(() => {}) }, [profiles])
  const deleteProfile = React.useCallback(async (id) => {
    setToasts([])
    const list = profiles.list.filter((x) => x.id !== id)
    await del(dbKey(id)).catch(() => {})
    if (!list.length) { await set(PKEY, { active: null, list: [] }); activeRef.current = null; setProfiles({ active: null, list: [] }); setDb(null); return }
    if (id !== profiles.active) { const P = { ...profiles, list }; await set(PKEY, P); setProfiles(P); return }
    const P = { active: list[0].id, list }
    await set(PKEY, P)
    const d = await get(dbKey(P.active))
    activeRef.current = P.active
    setSheets([]); setTab('today'); setProfiles(P); setDb(migrate(d || seed('blank')))
  }, [profiles])

  const value = React.useMemo(() => ({ withUndo, sync, syncNow: pull, activeId: profiles?.active, toasts, toast, clearToasts, db, update, open, sheets, closeSheet, tab, setTab, session, setSession, reset, replace, profiles, switchProfile, createProfile, renameProfile, deleteProfile }),
    [withUndo, sync, pull, toasts, toast, clearToasts, db, update, open, sheets, closeSheet, tab, session, reset, replace, profiles, switchProfile, createProfile, renameProfile, deleteProfile])
  if (!profiles) return null
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

/* ---------- kilo hedefleri ---------- */
export function goalState(db) {
  const pts = db.measures.filter((m) => m.kg).sort((a, b) => (a.date < b.date ? -1 : 1))
  const start = db.profile.startKg ?? pts[0]?.kg ?? null
  const cur = pts.at(-1)?.kg ?? start
  const goals = [...(db.targets.goals || [])].sort((a, b) => b - a)
  if (cur == null) return { start, cur, goals, active: goals[0] ?? null, lost: 0, pct: 0, idx: 0, pts }
  let idx = goals.findIndex((g) => cur > g)
  const done = idx === -1 && goals.length > 0
  if (idx === -1) idx = goals.length - 1
  const active = goals[idx] ?? null
  const from = idx > 0 ? goals[idx - 1] : start
  const pct = active == null ? 0 : done ? 1 : Math.max(0, Math.min(1, (from - cur) / ((from - active) || 1)))
  return { start, cur, goals, active, idx, done, pct, left: active == null ? 0 : Math.max(0, cur - active), lost: start != null ? start - cur : 0, pts }
}

/* ---------- log helpers (immer draft) ---------- */
export const dayLog = (d, date) => (d.log[date] ??= {})

/* ---------- workout ---------- */
export const allEx = (prog) => (prog ? prog.blocks.flatMap((b) => (b.kind === 'single' ? [b.ex] : b.exs)) : [])
// Seansta çalışılacak setler (boş süpersetler hariç)
export const findEx = (db, pid, eid) => allEx(db.programs.find((p) => p.id === pid)).find((e) => e.id === eid)

// Günün program id'si: o güne özel seçim, yoksa o tarihte geçerli haftalık plan
export const programIdFor = (db, date) => { const L = db.log[date]; return L?.programId !== undefined ? L.programId || null : scheduleAt(db, date)[dowOf(date)] || null }
// Atanmış program (hareketsiz olsa da)
export function assignedProgram(db, date) {
  const id = programIdFor(db, date)
  return id ? db.programs.find((p) => p.id === id) || null : null
}
// Günün antrenmanı: hareketi olmayan program dinlenme sayılır
export function programFor(db, date) {
  const p = assignedProgram(db, date)
  return p && allEx(p).length ? p : null
}
export { scheduleAt }

// Hareket başına yapılan set: exDone true → hepsi, false (elle kaldırıldı) → 0, yoksa işaretli setler
const exCount = (L, e) => (L.exDone?.[e.id] === true ? e.sets : L.exDone?.[e.id] === false ? 0 : Math.min(e.sets, (L.sets?.[e.id] || []).filter((s) => s?.done).length))
export function workoutProgress(db, prog, date) {
  const L = db.log[date] || {}
  let tot = 0, done = 0
  allEx(prog).forEach((e) => { tot += e.sets; done += exCount(L, e) })
  const complete = L.workoutDone === true || (tot > 0 && done >= tot)
  return { tot, done, pct: tot ? done / tot : 0, complete }
}
export const exDoneCount = (db, e, date) => exCount(db.log[date] || {}, e)

/* draft: haftalık planda `dow` gününü `from` tarihinden itibaren değiştirir; önceki tarihler etkilenmez */
export function setScheduleFrom(d, from, dow, pid) {
  if (!Array.isArray(d.scheduleHist) || !d.scheduleHist.length) d.scheduleHist = [{ from: EPOCH, days: { ...d.schedule } }]
  const H = d.scheduleHist
  if (!H.some((h) => h.from === from)) { H.push({ from, days: { ...scheduleAt(d, from) } }); H.sort((a, b) => (a.from < b.from ? -1 : 1)) }
  for (const h of H) if (h.from >= from) h.days[dow] = pid || null
  clearFutureOverrides(d, from, dow)
  for (let i = H.length - 1; i > 0; i--) if (JSON.stringify(H[i].days) === JSON.stringify(H[i - 1].days)) H.splice(i, 1) // aynı planı tekrarlayan kayıtlar
  d.schedule = { ...scheduleAt(d, todayKey()) }
}
/* draft: güne program ata. repeat: bu tarihten itibaren her hafta aynı gün (geçmiş tarihte yalnız o gün) */
export function assignDay(d, date, pid, repeat) {
  const L = dayLog(d, date)
  if (repeat && date >= todayKey()) {
    // "her hafta tekrarla" ileri bir haftadan seçilse de bu haftanın aynı gününden başlar
    const from = nextOnOrAfter(todayKey(), dowOf(date))
    delete L.programId; setScheduleFrom(d, from < date ? from : date, dowOf(date), pid)
  } else L.programId = pid || null
}
// bugün ya da sonrasındaki ilk `dow` günü
export function nextOnOrAfter(day, dow) { const [y, m, dd] = day.split('-').map(Number); const t = new Date(y, m - 1, dd); t.setDate(t.getDate() + ((dow - ((t.getDay() + 6) % 7)) + 7) % 7); return keyOf(t) }
// gelecekteki o haftagününe ait, henüz çalışılmamış "yalnız bu gün" seçimlerini kaldırır (haftalık plan görünsün)
function clearFutureOverrides(d, from, dow) {
  for (const k of Object.keys(d.log)) {
    const L = d.log[k]
    if (k >= from && dowOf(k) === dow && L.programId !== undefined && !activeDay(L)) {
      const p = L.programId && d.programs.find((x) => x.id === L.programId)
      if (!p || p.temp || !allEx(p).length) delete L.programId
    }
  }
}

/* draft: program içeriği değişmeden önce, geçmişte bu programla çalışılmış günleri değişmeyen arşiv kopyasına bağlar.
   Hareket id'leri korunur; böylece eski set kayıtları kopyada görünmeye devam eder. */
const activeDay = (L) => !!L && (L.workoutDone === true || Object.values(L.exDone || {}).some((v) => v === true) || Object.values(L.sets || {}).some((a) => Array.isArray(a) && a.some((s) => s?.done)))
export function freezePast(d, pid) {
  const p = d.programs.find((x) => x.id === pid)
  if (!p || p.archived) return // arşiv kopyası zaten geçmişe ait
  const today = todayKey()
  const days = Object.keys(d.log).filter((k) => k < today && activeDay(d.log[k]) && programIdFor(d, k) === pid)
  if (!days.length) return
  const snap = { ...structuredClone(isDraft(p) ? current(p) : p), id: uid(), archived: true, snapOf: pid }
  d.programs.push(snap)
  for (const k of days) d.log[k].programId = snap.id
}

export function lastLifted(db, eid, beforeDate) {
  const keys = Object.keys(db.log).filter((k) => k < beforeDate).sort().reverse()
  for (const k of keys) {
    const s = db.log[k]?.sets?.[eid]
    const hit = s && s.filter((x) => x && x.done && num(x.kg) > 0).pop()
    if (hit) return { date: k, ...hit }
  }
  return null
}

/* draft: antrenmanı tamamlandı say; bütün hareketler işaretlenir */
export function completeWorkout(d, date, progId) {
  const L = dayLog(d, date)
  L.workoutDone = true
  if (L.programId === undefined) L.programId = progId
  const X = (L.exDone ??= {})
  allEx(d.programs.find((p) => p.id === progId)).forEach((e) => { X[e.id] = true })
}
/* draft: tamamlandı işaretini kaldır; setler girilmiş olsa da hareketler yapılmadı sayılır */
export function uncompleteWorkout(d, date, progId) {
  const L = dayLog(d, date)
  L.workoutDone = false
  const X = (L.exDone ??= {})
  allEx(d.programs.find((p) => p.id === progId)).forEach((e) => { X[e.id] = false })
}
/* draft: listedeki kutucuk; hepsi yapılınca antrenman tamamlanır */
export function toggleExDone(d, date, progId, e) {
  const L = dayLog(d, date)
  const on = exCount(L, e) < e.sets
  ;(L.exDone ??= {})[e.id] = on
  const prog = d.programs.find((p) => p.id === progId)
  if (on && allEx(prog).every((x) => exCount(L, x) >= x.sets)) completeWorkout(d, date, progId)
  else if (!on && L.workoutDone) L.workoutDone = false
}

/* ---------- nutrition ---------- */
const fin = (v) => (Number.isFinite(+v) ? +v : 0)
export const itemMacros = (it) => { const g = fin(it.g), P = it.per100 || {}; return { kcal: (fin(P.kcal) * g) / 100, p: (fin(P.p) * g) / 100, c: (fin(P.c) * g) / 100, f: (fin(P.f) * g) / 100 } }
const Z = () => ({ kcal: 0, p: 0, c: 0, f: 0 })
const add = (a, b, k = 1) => { a.kcal += fin(b.kcal) * k; a.p += fin(b.p) * k; a.c += fin(b.c) * k; a.f += fin(b.f) * k; return a }

export const MEALS = [['kahvalti', 'Sabah'], ['ogle', 'Öğle'], ['ara', 'Ara öğün'], ['aksam', 'Akşam']]
// Kullanıcının seçtiği öğünler (Ayarlar › Öğünler); include: o an düzenlenen kaydın öğünü kapalı olsa da listede kalsın
export const mealsOf = (db, include) => { const on = db?.targets?.meals; return on?.length ? MEALS.filter(([k]) => on.includes(k) || k === include) : MEALS }
export const defaultMeal = (db) => {
  const h = new Date().getHours(); const pref = h < 11 ? 'kahvalti' : h < 15 ? 'ogle' : h < 18 ? 'ara' : 'aksam'
  const ks = mealsOf(db).map(([k]) => k); if (ks.includes(pref)) return pref
  const order = MEALS.map(([k]) => k), pi = order.indexOf(pref)
  return ks.reduce((best, k) => (Math.abs(order.indexOf(k) - pi) < Math.abs(order.indexOf(best) - pi) ? k : best), ks[0])
}

export function entriesOf(db, date) {
  const L = db.log[date] || {}
  return [...(L.entries || []), ...(L.extras || []).map((e) => ({ meal: 'ara', ...e }))]
}
export function nutrition(db, date) {
  const entries = entriesOf(db, date)
  const eat = Z()
  entries.forEach((e) => add(eat, e))
  const byMeal = Object.fromEntries(MEALS.map(([k]) => [k, entries.filter((e) => (e.meal || 'ara') === k)]))
  return { entries, eat, byMeal, target: db.targets }
}
export function recentFoods(db, limit = 8) {
  const seen = new Set(), out = []
  for (const k of Object.keys(db.log).sort().reverse()) {
    for (const e of [...(db.log[k].entries || [])].reverse()) {
      if (!e.per100 || seen.has(e.foodName || e.name)) continue
      seen.add(e.foodName || e.name)
      out.push({ id: 'r-' + e.id, name: e.foodName || e.name, per100: e.per100, portions: e.portions || {}, lastG: e.g, image: e.image || null })
      if (out.length >= limit) return out
    }
  }
  return out
}
export const entryFrom = (food, g, meal, label) => ({
  id: uid(), meal, name: label || `${fmt1(g)} g ${food.name}`, foodName: food.name, g, per100: food.per100, portions: food.portions || {},
  image: food.image || null, ...macrosOf(food.per100, g),
})
const macrosOf = (per100, g) => itemMacros({ per100, g })

export const recipeTotals = (r) => {
  const t = Z()
  r.items.forEach((i) => add(t, itemMacros(i)))
  const g = r.items.reduce((a, i) => a + (+i.g || 0), 0)
  const sv = Math.max(1, +r.servings || 1)
  return { total: t, perServing: { kcal: t.kcal / sv, p: t.p / sv, c: t.c / sv, f: t.f / sv }, grams: g }
}

/* ---------- images (IndexedDB blobs) ---------- */
export async function saveImage(file, max = 1200) {
  const bmp = await createImageBitmap(file).catch(() => null)
  let blob = file
  if (bmp) {
    const s = Math.min(1, max / Math.max(bmp.width, bmp.height))
    const c = document.createElement('canvas')
    c.width = Math.round(bmp.width * s); c.height = Math.round(bmp.height * s)
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height)
    blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 0.82))
  }
  const id = 'img-' + uid()
  await set(id, blob)
  return id
}
const urlCache = new Map()
export const deleteImage = (id) => { if (!id) return; const u = urlCache.get(id); if (u) { URL.revokeObjectURL(u); urlCache.delete(id) } return del(id).catch(() => {}) }
export function useImage(id) {
  const [url, setUrl] = React.useState(() => urlCache.get(id) || null)
  React.useEffect(() => {
    if (!id) return setUrl(null)
    if (urlCache.has(id)) return setUrl(urlCache.get(id))
    let alive = true
    get(id).then((b) => { if (b && alive) { const u = URL.createObjectURL(b); urlCache.set(id, u); setUrl(u) } })
    return () => { alive = false }
  }, [id])
  return url
}
export async function exportAll(db) {
  const imgs = {}
  const ids = [...db.myFoods.map((f) => f.image), ...db.recipes.map((r) => r.image)].filter(Boolean)
  for (const id of ids) {
    const b = await get(id)
    if (b) imgs[id] = await new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.readAsDataURL(b) })
  }
  return JSON.stringify({ app: 'balli', exportedAt: new Date().toISOString(), db, imgs })
}
export async function importAll(text) {
  let j
  try { j = JSON.parse(text) } catch { throw new Error('Dosya okunamadı. Geçerli bir Ballı yedeği seç.') }
  if (j?.app !== 'balli' || !j.db || typeof j.db !== 'object') throw new Error('Bu dosya bir Ballı yedeği değil.')
  const d = migrate(j.db) // eksik alanları tamamlar, bozuksa hata verir
  for (const [id, dataUrl] of Object.entries(j.imgs || {})) {
    if (!/^img-[a-z0-9]+$/i.test(id) || typeof dataUrl !== 'string' || !dataUrl.startsWith('data:image/')) continue
    try { const b = await (await fetch(dataUrl)).blob(); await set(id, b) } catch {}
  }
  return d
}
