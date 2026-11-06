import * as React from 'react'
import { IconX, IconPlayerSkipForward, IconChevronLeft, IconCheck, IconPlus, IconPlayerPlayFilled, IconTrophy, IconSparkles, IconPlayerPauseFilled, IconChevronDown, IconBarbell } from '@tabler/icons-react'
import { Button, Badge, Progress } from '@/components/ui'
import { Ring, Stepper, ExerciseMedia } from '@/components/common'
import { useApp, lastLifted, dayLog, completeWorkout } from '@/lib/store'
import { mmss, num, fmt, fmt1, cn, haptic, norm } from '@/lib/utils'
import { prsOn, suggestKg, beatsPrevBest } from '@/lib/progress'
import { burst } from '@/components/confetti'

function buildSteps(prog) {
  const steps = []
  let n = 0
  prog.blocks.forEach((b) => {
    n++
    if (b.kind === 'single') {
      for (let i = 0; i < b.ex.sets; i++) steps.push({ ex: b.ex, si: i, of: b.ex.sets, rest: b.ex.rest, label: `#${n}` })
    } else if (b.exs.length) { // boş süpersetler atlanır
      const R = Math.max(1, +b.rounds || 1)
      for (let r = 0; r < R; r++) b.exs.forEach((e, j) =>
        steps.push({ ex: e, si: r, of: R, rest: j === b.exs.length - 1 ? b.rest : 0, label: `${n}${String.fromCharCode(97 + j)}`, ss: { round: r + 1, rounds: R, tag: b.tag } }))
    } else n--
  })
  return steps
}

let audioCtx
// iOS: ses bağlamı yalnız kullanıcı dokunuşunda açılabilir
function primeAudio() {
  try { audioCtx ??= new (window.AudioContext || window.webkitAudioContext)(); if (audioCtx.state === 'suspended') audioCtx.resume() } catch {}
}
function beep() {
  try {
    if (!audioCtx) return navigator.vibrate?.([120, 60, 120])
    ;[0, 0.18].forEach((t) => {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain()
      o.frequency.value = 880; o.connect(g); g.connect(audioCtx.destination)
      g.gain.setValueAtTime(0.0001, audioCtx.currentTime + t)
      g.gain.exponentialRampToValueAtTime(0.25, audioCtx.currentTime + t + 0.02)
      g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + t + 0.15)
      o.start(audioCtx.currentTime + t); o.stop(audioCtx.currentTime + t + 0.16)
    })
    navigator.vibrate?.([120, 60, 120])
  } catch {}
}

export default function Session() {
  const { toast, db, update, session, setSession } = useApp()
  const prog = db.programs.find((p) => p.id === session.pid)
  const date = session.date
  const steps = React.useMemo(() => (prog ? buildSteps(prog) : []), [prog])
  React.useEffect(() => { if (!prog) setSession(null) }, [prog]) // eslint-disable-line
  const L = db.log[date] || {}
  const isDone = (s) => L.exDone?.[s.ex.id] || L.sets?.[s.ex.id]?.[s.si]?.done
  const [idx, setIdx] = React.useState(() => Math.max(0, steps.findIndex((s) => !isDone(s))) )
  const [rest, setRest] = React.useState(null) // {end,total}
  const [timer, setTimer] = React.useState(null) // time-based set countdown
  // başlangıç zamanı günlüğe yazılır; kapatıp açınca süre sıfırlanmaz
  const [mountAt] = React.useState(() => Date.now())
  React.useEffect(() => { if (!L.startedAt && !L.duration) update((d) => { dayLog(d, date).startedAt ??= mountAt }) }, []) // eslint-disable-line
  const start = L.startedAt || mountAt
  const [now, setNow] = React.useState(Date.now())
  const min = !!session.minimized
  const paused = !!L.pausedAt
  const setMin = (v) => setSession((s) => (s ? { ...s, minimized: v } : s))
  const [finished, setFinished] = React.useState(steps.length > 0 && steps.every(isDone))
  const step = steps[idx]

  const fast = !paused && !min && !!(rest || timer)
  React.useEffect(() => { const t = setInterval(() => setNow(Date.now()), fast ? 250 : 1000); return () => clearInterval(t) }, [fast])
  React.useEffect(() => { // ekran kapanmasın; sekmeye dönünce kilidi yeniden al
    let lock
    const req = () => navigator.wakeLock?.request('screen').then((l) => (lock = l)).catch(() => {})
    const vis = () => { if (document.visibilityState === 'visible') { req(); setNow(Date.now()) } }
    req(); document.addEventListener('visibilitychange', vis)
    return () => { document.removeEventListener('visibilitychange', vis); lock?.release?.() }
  }, [])
  React.useEffect(() => { if (min) return; document.body.style.overflow = 'hidden'; return () => { document.body.style.overflow = '' } }, [min])
  // küçültülünce tam ekran görünüm odak almasın
  const fullRef = React.useRef(null)
  const firstOpen = React.useRef(!session.minimized)
  React.useEffect(() => { if (min) firstOpen.current = false }, [min])
  React.useEffect(() => { const el = fullRef.current; if (!el) return; if (min) el.setAttribute('inert', ''); else el.removeAttribute('inert') }, [min])

  // duraklatılınca geri sayımlar kalan süreyi saklar (left), devam edince yeniden kurulur
  const restLeft = rest ? Math.max(0, Math.ceil((rest.left ?? rest.end - now) / 1000)) : 0
  const timeLeft = timer ? Math.max(0, Math.ceil((timer.left ?? timer.end - now) / 1000)) : 0
  React.useEffect(() => { if (rest && rest.left == null && restLeft === 0) { beep(); setRest(null) } }, [rest, restLeft])
  React.useEffect(() => { if (timer && timer.left == null && timeLeft === 0) { beep(); setTimer(null) } }, [timer, timeLeft])
  const pause = () => {
    haptic(); const t = Date.now()
    update((d) => { const D = dayLog(d, date); if (!D.pausedAt) D.pausedAt = t })
    setRest((r) => (r && r.left == null ? { ...r, left: Math.max(0, r.end - t) } : r))
    setTimer((x) => (x && x.left == null ? { ...x, left: Math.max(0, x.end - t) } : x))
  }
  const resume = () => {
    primeAudio(); haptic(); const t = Date.now()
    update((d) => { const D = dayLog(d, date); if (D.pausedAt) { D.pausedMs = (D.pausedMs || 0) + Math.max(0, t - D.pausedAt); delete D.pausedAt } })
    setRest((r) => (r && r.left != null ? { ...r, end: t + r.left, left: undefined } : r))
    setTimer((x) => (x && x.left != null ? { ...x, end: t + x.left, left: undefined } : x))
    setNow(t)
  }

  const prev = step ? lastLifted(db, step.ex.id, date) : null
  const sug = React.useMemo(() => (step ? suggestKg(db, step.ex, date) : null), [step?.ex.id, date, db.programs]) // eslint-disable-line
  const prs = React.useMemo(() => (finished ? prsOn(db, date) : []), [finished, db.log, db.programs, date]) // eslint-disable-line
  const logged = step ? L.sets?.[step.ex.id]?.[step.si] || {} : {}
  const [kg, setKg] = React.useState(0)
  const [reps, setReps] = React.useState(0)
  React.useEffect(() => {
    if (!step) return
    const prevSet = L.sets?.[step.ex.id]?.[step.si - 1]
    setKg(num(logged.kg) || num(prevSet?.kg) || num(step.ex.kg) || num(prev?.kg) || 0)
    setReps(num(logged.reps) || step.ex.reps)
    setTimer(null)
  }, [idx]) // eslint-disable-line

  // önce ileri, sonra baştan (atlanan setler) ara
  const nextIdx = (from) => { for (let k = 1; k < steps.length; k++) { const i = (from + k) % steps.length; if (!isDone(steps[i])) return i } return -1 }
  const firstUndone = () => steps.findIndex((s) => !isDone(s))
  const [pop, setPop] = React.useState(0)
  React.useEffect(() => { if (!pop) return; const t = setTimeout(() => setPop(0), 520); return () => clearTimeout(t) }, [pop])
  const complete = () => {
    primeAudio()
    // GM-08: önceki en iyiyi geçen set → konfeti + "Yeni rekor!" (günde hareket başına bir kez)
    const key = norm(step.ex.name)
    const isPr = step.ex.unit === 'tekrar' && !(L.prShown || []).includes(key) && beatsPrevBest(db, step.ex.name, date, kg, reps)
    update((d) => {
      const D = dayLog(d, date); const S = (D.sets ??= {}); const arr = (S[step.ex.id] ??= [])
      arr[step.si] = { ...(arr[step.si] || {}), kg: step.ex.unit === 'tekrar' && kg ? kg : arr[step.si]?.kg, reps, done: true }
      if (isPr) (D.prShown ??= []).push(key)
      if (D.exDone?.[step.ex.id] === false) delete D.exDone[step.ex.id] // elle kaldırılan işaret, set girilince yeniden sayılsın
    })
    haptic(true); setPop((x) => x + 1)
    if (isPr) { burst(); toast(`Yeni rekor! ${step.ex.name}`) }
    const n = nextIdx(idx)
    if (n === -1) { setFinished(true); return }
    if (step.rest > 0) setRest({ end: Date.now() + step.rest * 1000, total: step.rest })
    setIdx(n)
  }
  const pausedFor = (L.pausedMs || 0) + (L.pausedAt ? Math.max(0, now - L.pausedAt) : 0)
  const elapsed = L.duration ?? Math.max(0, Math.floor((now - start - pausedFor) / 1000))
  // bitiş ekranı açılınca büyük konfeti (bir kez)
  const celebrated = React.useRef(false)
  React.useEffect(() => { if (finished && !celebrated.current && steps.length) { celebrated.current = true; burst({ count: 140, y: 0.3 }) } }, [finished]) // eslint-disable-line
  const finish = () => { update((d) => { completeWorkout(d, date, prog.id); const D = dayLog(d, date); D.duration ??= elapsed; delete D.pausedAt }); setSession(null) }

  const doneCount = steps.filter(isDone).length
  // hacim: yalnız tekrar birimli hareketler; tekrar boşsa hedef tekrar
  const volume = steps.reduce((a, st) => {
    if (st.ex.unit !== 'tekrar') return a
    const s = L.sets?.[st.ex.id]?.[st.si]
    if (!s?.done) return a
    return a + Math.max(0, num(s.kg)) * (Math.max(0, num(s.reps)) || st.ex.reps || 0)
  }, 0)
  const ni = step ? nextIdx(idx) : -1
  const upcoming = ni >= 0 && ni !== idx ? steps[ni] : null

  if (!prog) return null
  const miniSub = finished ? 'Bitti · kaydetmeyi unutma' : rest ? `Dinlenme · ${mmss(restLeft)}` : step ? `${step.ex.name} · Set ${step.si + 1}/${step.of}` : ''
  return (
    <>
    <div ref={fullRef} className={cn('bg-background fixed inset-0 z-40 flex origin-bottom flex-col pt-safe transition-[translate,scale,opacity,border-radius] duration-500 ease-[cubic-bezier(.32,.72,0,1)] motion-reduce:transition-none',
      firstOpen.current && !min && 'modal-up',
      min && 'pointer-events-none translate-y-[calc(100%-180px)] scale-x-[.9] scale-y-[.86] overflow-hidden rounded-[28px] opacity-0')} role="dialog" aria-label="Antrenman modu" aria-hidden={min || undefined}>
      <div className="px-gutter flex items-center justify-between gap-2 py-3">
        <Button variant="ghost" size="icon" className="size-11" onClick={() => { haptic(); setMin(true) }} aria-label="Küçült"><IconChevronDown /></Button>
        <div className="min-w-0 flex-1 text-center">
          <div className="truncate text-sm font-medium">{prog.name}</div>
          <div className="text-muted-foreground text-xs tabular">{mmss(elapsed)}{paused && ' · duraklatıldı'} · {doneCount}/{steps.length} set</div>
        </div>
        {!finished && steps.length > 0 && (paused
          ? <Button variant="ghost" size="icon" className="size-11" onClick={resume} aria-label="Devam et"><IconPlayerPlayFilled className="size-5" /></Button>
          : <Button variant="ghost" size="icon" className="size-11" onClick={pause} aria-label="Duraklat"><IconPlayerPauseFilled className="size-5" /></Button>)}
        <Button variant="ghost" className="h-11 px-3" onClick={() => setFinished(true)} disabled={!steps.length}>Bitir</Button>
      </div>
      <Progress className="rounded-none" value={(doneCount / (steps.length || 1)) * 100} />
      {pop > 0 && (
        <div key={pop} aria-hidden className="pointer-events-none fixed inset-x-0 top-1/3 z-50 grid place-items-center motion-reduce:hidden">
          <div className="bg-success grid size-20 animate-[pop_.38s_cubic-bezier(.34,1.56,.64,1)_both] place-items-center rounded-full text-white shadow-lg"><IconCheck className="size-10" stroke={3} /></div>
        </div>
      )}

      {!steps.length ? (
        <div className="px-gutter flex flex-1 flex-col items-center justify-center gap-4 text-center">
          <div className="text-lg font-semibold">Bu programda hareket yok</div>
          <Button variant="outline" onClick={() => setSession(null)}>Kapat</Button>
        </div>
      ) : finished ? (
        <div className="px-gutter flex flex-1 flex-col items-center justify-center gap-6 text-center">
          <IconTrophy className="text-primary size-12" stroke={1.5} />
          <div><div className="text-2xl font-semibold">Antrenman bitti</div><div className="text-muted-foreground mt-1">{prog.name}</div></div>
          <div className="grid w-full max-w-sm grid-cols-3 border rounded-lg divide-x">
            {[['Süre', mmss(elapsed)], ['Set', `${doneCount}/${steps.length}`], ['Hacim', `${fmt(volume)} kg`]].map(([l, v]) => (
              <div key={l} className="p-3"><div className="text-muted-foreground text-xs">{l}</div><div className="mt-1 font-semibold tabular">{v}</div></div>
            ))}
          </div>
          {prs.length > 0 && (
            <div className="grid w-full max-w-sm gap-2 text-left">
              {prs.map((p, i) => (
                <div key={i} className="bg-primary/10 animate-[rise_.45s_cubic-bezier(.32,.72,0,1)_both] flex items-center gap-3 rounded-lg px-4 py-3" style={{ animationDelay: `${i * 80}ms` }}>
                  <IconTrophy className="text-primary size-6 shrink-0" stroke={1.75} />
                  <div className="min-w-0 flex-1"><div className="text-primary text-xs font-semibold uppercase tracking-wider">Yeni rekor</div><div className="truncate font-medium">{p.name}</div></div>
                  <div className="text-right font-semibold tabular">{fmt1(p.kg)} kg × {p.reps}</div>
                </div>
              ))}
            </div>
          )}
          <div className="grid w-full max-w-sm gap-2">
            <Button size="lg" onClick={finish}><IconCheck />Kaydet ve kapat</Button>
            {doneCount < steps.length && <Button variant="ghost" onClick={() => { const f = firstUndone(); if (f >= 0) setIdx(f); setFinished(false) }}>Antrenmana dön</Button>}
          </div>
        </div>
      ) : paused ? (
        <div className="px-gutter flex flex-1 flex-col items-center justify-center gap-6 text-center">
          <div className="bg-primary/12 text-primary grid size-20 place-items-center rounded-full"><IconPlayerPauseFilled className="size-9" /></div>
          <div><div className="text-2xl font-semibold">Duraklatıldı</div><div className="text-muted-foreground mt-1 tabular">{mmss(elapsed)} · {doneCount}/{steps.length} set</div></div>
          <div className="grid w-full max-w-sm gap-2">
            <Button size="lg" className="h-14 text-base" onClick={resume}><IconPlayerPlayFilled className="size-5" />Devam et</Button>
            <Button variant="outline" size="lg" onClick={() => { haptic(); setMin(true) }}><IconChevronDown />Küçült, sonra dönerim</Button>
            <Button variant="ghost" className="text-muted-foreground" onClick={() => setSession(null)}>Antrenman ekranını kapat</Button>
          </div>
        </div>
      ) : rest ? (
        <div className="px-gutter flex flex-1 flex-col items-center justify-center gap-8">
          <div className="text-muted-foreground text-sm font-medium uppercase tracking-wider">Dinlenme</div>
          <Ring value={Math.max(0, (rest.left ?? rest.end - now) / 1000) / rest.total} size={220} stroke={8} linear><span className="text-6xl font-semibold tabular">{mmss(restLeft)}</span></Ring>
          <div className="flex gap-2">
            <Button variant="outline" size="lg" onClick={() => setRest({ ...rest, end: rest.end + 15000, total: rest.total + 15 })}><IconPlus />15 sn</Button>
            <Button size="lg" onClick={() => { primeAudio(); setRest(null) }}><IconPlayerSkipForward />Atla</Button>
          </div>
          {step && <div className="text-center"><div className="text-muted-foreground text-xs">Sıradaki</div><div className="font-medium">{step.ex.name} · Set {step.si + 1}</div></div>}
        </div>
      ) : step ? (
        <div className="px-gutter flex flex-1 flex-col gap-6 overflow-y-auto pb-4 pt-6">
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge variant="outline" className="tabular">{step.label}</Badge>
            {step.ss && <Badge variant="secondary">Süperset · tur {step.ss.round}/{step.ss.rounds}</Badge>}
            {step.ss?.tag === 'warm' && <Badge variant="soft">Isınma</Badge>}
            {step.ss?.tag === 'cool' && <Badge variant="outline">Soğuma</Badge>}
            {step.ex.muscle && !(step.ss?.tag && ['ısınma', 'soğuma'].includes(step.ex.muscle.trim().toLocaleLowerCase('tr-TR'))) && <span className="text-muted-foreground text-xs">{step.ex.muscle}</span>}
          </div>
          <ExerciseMedia name={step.ex.name} className="max-h-48 aspect-auto h-44" />
          <div>
            <h2 className="text-3xl font-semibold leading-tight tracking-tight text-balance">{step.ex.name}</h2>
            <div className="text-muted-foreground mt-1 tabular">Set {step.si + 1} / {step.of} · hedef {step.ex.reps} {step.ex.unit}</div>
            {prev && <div className="text-muted-foreground mt-1 text-sm tabular">Son seferde {prev.kg} kg × {prev.reps || step.ex.reps}</div>}
            {step.ex.note && <div className="text-muted-foreground mt-1 text-sm italic">{step.ex.note}</div>}
          </div>

          {step.ex.unit === 'tekrar' ? (
            <div className="grid gap-4">
              <div className="grid gap-2">
                <div className="flex items-center justify-between gap-2">
                  <div className="text-muted-foreground text-xs font-medium">Kilo</div>
                  {sug && sug.kg !== kg && (
                    <button type="button" onClick={() => { haptic(); setKg(sug.kg) }} className="press bg-primary/10 text-primary -my-2 flex h-11 items-center gap-1.5 rounded-full px-3 text-xs font-semibold tabular">
                      <IconSparkles className="size-3.5" />Öneri: {fmt1(sug.kg)} kg
                    </button>
                  )}
                </div>
                <Stepper value={kg} onChange={setKg} step={2.5} suffix=" kg" />
              </div>
              <div className="grid gap-2"><div className="text-muted-foreground text-xs font-medium">Tekrar</div><Stepper value={reps} onChange={setReps} step={1} /></div>
            </div>
          ) : step.ex.unit === 'sn' ? (
            <div className="flex flex-col items-center gap-4">
              <Ring value={timer ? Math.max(0, (timer.left ?? timer.end - now) / 1000) / step.ex.reps : 1} size={160} stroke={6} linear><span className="text-4xl font-semibold tabular">{mmss(timer ? timeLeft : step.ex.reps)}</span></Ring>
              {!timer && <Button variant="outline" onClick={() => { primeAudio(); setTimer({ end: Date.now() + step.ex.reps * 1000 }) }}><IconPlayerPlayFilled />Süreyi başlat</Button>}
            </div>
          ) : (
            <div className="text-muted-foreground border border-dashed p-4 text-center text-sm rounded-lg">{step.ex.reps} dakika · bitirince işaretle</div>
          )}

          <div className="mt-auto grid gap-3">
            {upcoming && <div className="text-muted-foreground text-center text-xs">Sıradaki: <span className="text-foreground">{upcoming.ex.name}</span>{step.rest > 0 && ` · önce ${step.rest} sn dinlenme`}</div>}
            <Button size="lg" className="h-14 text-base" onClick={complete}><IconCheck className="size-5" />Seti tamamla</Button>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="ghost" onClick={() => setIdx(Math.max(0, idx - 1))} disabled={idx === 0}><IconChevronLeft />Önceki</Button>
              <Button variant="ghost" onClick={() => { const n = idx + 1 < steps.length ? idx + 1 : idx; setIdx(n) }} disabled={idx >= steps.length - 1}>Atla<IconPlayerSkipForward /></Button>
            </div>
          </div>
        </div>
      ) : null}
      <div className="pb-safe" />
    </div>
    {/* Mini oynatıcı: tab bar'ın üstünde; dokununca büyür */}
    <div className={cn('fixed inset-x-0 z-[35] flex justify-center px-gutter bottom-[calc(max(10px,env(safe-area-inset-bottom,0px)-12px)+70px)] transition-[translate,scale,opacity] duration-500 ease-[cubic-bezier(.32,.72,0,1)] motion-reduce:transition-none',
      min ? 'translate-y-0 scale-100 opacity-100 delay-150' : 'pointer-events-none translate-y-6 scale-95 opacity-0')} aria-hidden={!min || undefined}>
      <div className="glass flex h-16 w-full max-w-[420px] items-center gap-3 rounded-[22px] py-2 pl-2 pr-1.5">
        <button type="button" tabIndex={min ? 0 : -1} onClick={() => { haptic(); setMin(false) }} className="flex min-w-0 flex-1 items-center gap-3 text-left" aria-label={`Antrenmanı aç: ${prog.name}`}>
          <Ring value={doneCount / (steps.length || 1)} size={44} stroke={4}><IconBarbell className="text-primary size-5" /></Ring>
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-semibold">{prog.name}</span>
            <span className="text-muted-foreground block truncate text-xs tabular">{paused ? 'Duraklatıldı · ' : ''}{mmss(elapsed)} · {miniSub}</span>
          </span>
        </button>
        {!finished && steps.length > 0 && (
          <Button variant="ghost" size="icon" tabIndex={min ? 0 : -1} className="size-11 shrink-0 rounded-full" onClick={paused ? resume : pause} aria-label={paused ? 'Devam et' : 'Duraklat'}>
            {paused ? <IconPlayerPlayFilled className="size-5" /> : <IconPlayerPauseFilled className="size-5" />}
          </Button>
        )}
        <Button variant="ghost" size="icon" tabIndex={min ? 0 : -1} className="text-muted-foreground size-11 shrink-0 rounded-full" onClick={() => setSession(null)} aria-label="Antrenman ekranını kapat"><IconX className="size-5" /></Button>
      </div>
    </div>
    </>
  )
}
