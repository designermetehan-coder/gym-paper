import * as React from 'react'
import { IconPlayerPlayFilled, IconChevronRight, IconDroplet, IconWalk, IconScale, IconCircleCheckFilled, IconMoon, IconMinus, IconPlus, IconWriting, IconPencil, IconX, IconCircle, IconCloud, IconToolsKitchen2, IconBarbell, IconConfetti, IconFlame, IconSnowflake, IconTrophy, IconShare, IconArrowUpRight, IconArrowDownRight } from '@tabler/icons-react'
import { Button, Card, Checkbox, Progress, Input, Badge, Sheet } from '@/components/ui'
import { Header, MacroRow, Ring, AnimatedNumber } from '@/components/common'
import { useApp, programFor, workoutProgress, allEx, nutrition, dayLog, goalState } from '@/lib/store'
import { NutritionSummary } from '@/screens/Nutrition'
import { DAYS_LONG, DAYS, todayKey, dowOf as dowIdx, longDate, shortDate, fmt, fmt1, cn, haptic } from '@/lib/utils'
import { streak as streakOf, streakCalendar, weekScoreDelta, pendingGoals } from '@/lib/gamify'
import { burst } from '@/components/confetti'

// Gün değişince (gece yarısı, uygulamaya dönüş) ekranı yeniler
export function useTodayKey() {
  const [k, setK] = React.useState(todayKey)
  React.useEffect(() => {
    const sync = () => setK((x) => (x === todayKey() ? x : todayKey()))
    let t
    const arm = () => { const n = new Date(); const next = new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 0, 0, 1); t = setTimeout(() => { sync(); arm() }, next - n) }
    arm()
    const vis = () => document.visibilityState === 'visible' && sync()
    document.addEventListener('visibilitychange', vis); window.addEventListener('focus', sync)
    return () => { clearTimeout(t); document.removeEventListener('visibilitychange', vis); window.removeEventListener('focus', sync) }
  }, [])
  return k
}
// İkincil eylemler: tonal (TE-05) — kartta tek dolu turuncu buton kalır
const TONAL = 'bg-primary/12 text-[oklch(0.5_0.19_40)] font-semibold shadow-none active:bg-primary/20 dark:text-primary'
const parseSteps = (v) => Math.min(200000, parseInt(String(v).replace(/\D/g, ''), 10) || 0)

export default function Today() {
  const { toast, db, update, open, setTab, setSession } = useApp()
  const date = useTodayKey(), t = (dowIdx(date))
  const prog = programFor(db, date)
  const wp = prog ? workoutProgress(db, prog, date) : null
  const N = nutrition(db, date)
  const G = goalState(db)
  const L = db.log[date] || {}
  const water = L.water || 0
  const wstep = db.targets.waterStep || 500
  const h = new Date().getHours()
  const greet = h < 12 ? 'Günaydın' : h < 18 ? 'İyi günler' : 'İyi akşamlar'
  const ms = db.measures.filter((m) => m.kg).sort((a, b) => (a.date < b.date ? -1 : 1))
  const last = ms.at(-1), first = ms[0]
  // Tarih, dokunma anında hesaplanır: gece yarısını geçen açık ekran dünkü kayda yazmaz
  const addWater = (delta) => update((d) => { const W = dayLog(d, todayKey()); W.water = Math.max(0, (W.water || 0) + delta) })
  // Adım: karta dokununca sayı yerinde düzenlenir
  const [editSteps, setEditSteps] = React.useState(false)
  const [steps, setSteps] = React.useState('')
  React.useEffect(() => { setEditSteps(false) }, [date])
  const startSteps = () => { setSteps(L.steps ? String(L.steps) : ''); setEditSteps(true) }
  const saveSteps = () => {
    if (!editSteps) return
    const v = parseSteps(steps), k = todayKey()
    if (v !== (db.log[k]?.steps || 0)) update((d) => { dayLog(d, k).steps = v })
    setEditSteps(false)
  }

  return (
    <div className="grid gap-4">
      <Header eyebrow={`${DAYS_LONG[t]} · ${longDate(date)}`} title={db.profile.name ? `${greet}, ${db.profile.name}` : greet} actions={<StreakChip date={date} />} />
      <EveningNudge date={date} />
      <StartChecklist />

      {/* Günün antrenmanı */}
      <Card className="p-4">
        {prog ? (
          <div className="grid gap-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="text-muted-foreground text-xs">Bugünkü antrenman</div>
                <div className="mt-0.5 text-2xl font-semibold tracking-tight">{prog.name}</div>
                <div className="text-muted-foreground text-sm tabular">{allEx(prog).length} hareket · {wp.done}/{wp.tot} set</div>
              </div>
              {wp.complete ? <Badge variant="success"><IconCircleCheckFilled />Tamamlandı</Badge> : <Badge variant="outline" className="tabular">%{Math.round(wp.pct * 100)}</Badge>}
            </div>
            <Progress value={wp.pct * 100} />
            <div className="grid grid-cols-[1fr_auto] gap-2">
              {allEx(prog).length ? (
                <Button size="lg" onClick={() => setSession({ pid: prog.id, date })}>
                  <IconPlayerPlayFilled className="size-4" />{wp.done ? 'Devam et' : 'Başlat'}
                </Button>
              ) : <Button size="lg" variant="secondary" onClick={() => setTab('workout')}>Hareketleri ekle</Button>}
              <Button size="lg" variant="outline" onClick={() => setTab('workout')}>Liste<IconChevronRight /></Button>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-3">
            <div className="bg-muted grid size-10 place-items-center rounded-md"><IconMoon className="size-5" /></div>
            <div className="flex-1"><div className="font-medium">Dinlenme günü</div><div className="text-muted-foreground text-sm">Program atanmadı.</div></div>
            <Button variant="outline" className="h-11" onClick={() => setTab('workout')}>Program seç</Button>
          </div>
        )}
      </Card>

      {/* Beslenme */}
      <Card className="grid gap-4 p-4">
        <div className="flex items-center justify-between">
          <div className="text-muted-foreground text-xs">Bugün yediklerin · {N.entries.length} kayıt</div>
          <Button variant="ghost" className="-my-1.5 -mr-2 h-11" onClick={() => setTab('food')}>Günlük<IconChevronRight /></Button>
        </div>
        <NutritionSummary N={N} T={db.targets} compact />
        <div className="grid grid-cols-2 gap-2">
          <Button className={cn('h-11', TONAL)} variant="ghost" onClick={() => open('addFood', { target: { type: 'log', date: todayKey() } })}><IconPlus />Yediğini ekle</Button>
          <Button className="h-11" variant="outline" onClick={() => open('cheat', { date: todayKey() })}><IconWriting />Yazarak gir</Button>
        </div>
      </Card>

      {/* Su · Adım · Kilo */}
      <div className="grid grid-cols-2 gap-3">
        <Card className="p-4">
          <div className="text-muted-foreground flex items-center gap-1.5 text-xs"><IconDroplet className="size-3.5" />Su</div>
          <div className="mt-1 text-xl font-semibold tabular"><AnimatedNumber value={water / 1000} format={(n) => fmt1(n)} /><span className="text-muted-foreground text-xs font-normal"> / {fmt1(db.targets.water / 1000)} L</span></div>
          <Progress className="mt-2" value={(water / db.targets.water) * 100} />
          <div className="mt-3 grid grid-cols-2 gap-2">
            <Button variant="outline" className="h-11" onClick={() => addWater(-wstep)} disabled={water <= 0} aria-label={`${wstep} ml çıkar`}><IconMinus /></Button>
            <Button variant="outline" className="h-11" onClick={() => { haptic(); addWater(wstep) }} aria-label={`${wstep} ml ekle`}><IconPlus /></Button>
          </div>
        </Card>
        <Card className="relative p-4">
          {editSteps ? (
            <form onSubmit={(e) => { e.preventDefault(); saveSteps() }}>
              <label htmlFor="steps-in" className="text-muted-foreground flex items-center gap-1.5 text-xs"><IconWalk className="size-3.5" />Adım</label>
              <input id="steps-in" autoFocus inputMode="numeric" pattern="[0-9]*" enterKeyHint="done" autoComplete="off" placeholder="0"
                className="border-primary mt-0.5 h-8 w-full rounded-none border-b-2 bg-transparent p-0 font-semibold tabular placeholder:text-muted-foreground/50" style={{ fontSize: 20, lineHeight: "28px", outline: "none" }}
                value={steps} onChange={(e) => setSteps(e.target.value.replace(/\D/g, '').slice(0, 6))} onBlur={saveSteps}
                onKeyDown={(e) => { if (e.key === 'Escape') { e.preventDefault(); setEditSteps(false) } }} aria-label="Bugünkü adım" />
              <Progress className="mt-2" value={(parseSteps(steps) / db.targets.steps) * 100} />
              <p className="text-muted-foreground mt-3 text-xs">Hedef {fmt(db.targets.steps)} · bitince klavyeden Bitti</p>
            </form>
          ) : (
            <button type="button" onClick={startSteps} aria-label="Adım sayısını gir" className="press block w-full text-left">
              <div className="text-muted-foreground flex items-center gap-1.5 text-xs"><IconWalk className="size-3.5" />Adım<IconPencil className="text-muted-foreground/70 ml-auto size-3.5" aria-hidden /></div>
              <div className="mt-1 text-xl font-semibold tabular">{fmt(L.steps || 0)}<span className="text-muted-foreground text-xs font-normal"> / {fmt(db.targets.steps)}</span></div>
              <Progress className="mt-2" value={((L.steps || 0) / db.targets.steps) * 100} />
              <p className="text-muted-foreground mt-3 text-xs">{L.steps ? 'Düzenlemek için dokun' : 'Girmek için dokun'}</p>
            </button>
          )}
        </Card>
      </div>
      {G.cur == null ? (
        <Card className="flex items-center gap-3 p-4">
          <div className="min-w-0 flex-1">
            <div className="text-muted-foreground flex items-center gap-1.5 text-xs"><IconScale className="size-3.5" />Kilo</div>
            <div className="mt-1 text-sm">İlerlemeni görmek için kilonu gir.</div>
          </div>
          <Button variant="outline" className="h-11 shrink-0" onClick={() => open('measure', { quick: true })}><IconPlus />Kilonu gir</Button>
        </Card>
      ) : (
      <button type="button" className="press w-full text-left" onClick={() => open('measure', { quick: true })} aria-label={`Kilo ${fmt1(G.cur)} kg. Yeni kilo gir`}>
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-muted-foreground flex items-center gap-1.5 text-xs"><IconScale className="size-3.5" />Kilo</div>
            <div className="mt-1 text-xl font-semibold tabular">{fmt1(G.cur)}<span className="text-muted-foreground text-xs font-normal"> kg</span></div>
          </div>
          <div className="text-right text-xs tabular">
            {G.lost > 0 && <div className="text-success font-medium">↓ {fmt1(G.lost)} kg toplam</div>}
            {G.lost < 0 && <div className="text-muted-foreground font-medium">↑ {fmt1(-G.lost)} kg toplam</div>}
            {G.active != null && <div className="text-muted-foreground">{G.done ? 'Tüm hedeflere ulaştın' : `${fmt1(G.active)} kg hedefine ${fmt1(G.left)} kg`}</div>}
          </div>
        </div>
        {G.active != null && !G.done && <Progress className="mt-3" value={G.pct * 100} />}
      </Card>
      </button>
      )}
      <WeekScoreCard date={date} />
      <GoalCelebration />
    </div>
  )
}

/* ---------- İlk kullanım rehberi ---------- */
function StartChecklist() {
  const { db, update, open, setTab } = useApp()
  const O = db.onboarding || {}
  const logs = Object.values(db.log || {})
  const items = [
    ['meal', 'İlk öğününü ekle', 'Yediklerini kaydet, kalori ve makro takibi başlasın.', IconToolsKitchen2, logs.some((L) => (L.entries || []).length || (L.extras || []).length), () => open('addFood', { target: { type: 'log', date: todayKey() } })],
    ['workout', 'İlk antrenmanını tamamla', 'Programından bir antrenman bitir ya da yaptım olarak işaretle.', IconBarbell, logs.some((L) => L.workoutDone), () => setTab('workout')],
    ['cloud', 'Bulut yedeğini aç', 'Telefon değişse de verilerin kaybolmasın.', IconCloud, !!db.cloud, () => open('cloud')],
  ]
  const done = items.filter((x) => x[4]).length
  const all = done === items.length
  // hepsi bittiğinde kutlama bir kez görünür, sonra gizlenir
  React.useEffect(() => {
    if (!all || O.dismissed) return
    const t = setTimeout(() => update((d) => { d.onboarding = { ...(d.onboarding || {}), dismissed: true, completedAt: Date.now() } }), 6000)
    return () => clearTimeout(t)
  }, [all, O.dismissed]) // eslint-disable-line
  if (O.dismissed) return null
  return (
    <Card className="grid gap-3 p-4" aria-labelledby="start-h">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 id="start-h" className="font-semibold">{all ? 'Hazırsın!' : 'Başlangıç'}</h2>
          <div className="text-muted-foreground text-sm tabular">{all ? 'Ballı seninle. Bu kart birazdan kaybolacak.' : `${done}/${items.length} adım tamam`}</div>
        </div>
        <Button variant="ghost" size="icon" className="-mr-2 -mt-1.5 size-11 shrink-0" aria-label="Başlangıç kartını kapat" onClick={() => update((d) => { d.onboarding = { ...(d.onboarding || {}), dismissed: true } })}><IconX /></Button>
      </div>
      <Progress value={(done / items.length) * 100} />
      {all ? (
        <div className="flex items-center gap-3 py-1"><IconConfetti className="text-primary size-7" stroke={1.5} /><div className="text-sm">İlk öğün, ilk antrenman ve yedek tamam. Şimdi sırada süreklilik var.</div></div>
      ) : (
        <ul className="-mx-2 grid">
          {items.map(([k, title, sub, I, ok, act]) => (
            <li key={k}>
              <button type="button" disabled={ok} onClick={act} className="press flex min-h-14 w-full items-center gap-3 rounded-xl px-2 py-2 text-left enabled:active:bg-accent disabled:opacity-100">
                {ok ? <IconCircleCheckFilled className="text-success size-6 shrink-0" /> : <IconCircle className="text-muted-foreground size-6 shrink-0" stroke={1.5} />}
                <span className="min-w-0 flex-1"><span className={cn('block text-sm font-medium', ok && 'text-muted-foreground line-through')}>{title}</span>{!ok && <span className="text-muted-foreground block text-xs">{sub}</span>}</span>
                {!ok && <I className="text-muted-foreground size-5 shrink-0" stroke={1.5} />}
                {!ok && <IconChevronRight className="text-muted-foreground size-4 shrink-0" />}
              </button>
            </li>
          ))}
        </ul>
      )}
    </Card>
  )
}

/* ---------- GM-02 Seri ---------- */
function useStreak(date) {
  const { db, update } = useApp()
  const S = React.useMemo(() => streakOf(db, date), [db.log, db.streak, db.targets, date]) // eslint-disable-line
  // köprülenmesi gereken boş gün varsa dondurmayı kalıcı yaz (yalnız Bugün açıldığında)
  const pend = JSON.stringify(S.pending)
  React.useEffect(() => {
    if (pend === '{}') return
    update((d) => { d.streak = { ...(d.streak || {}), freezes: { ...(d.streak?.freezes || {}), ...JSON.parse(pend) } } })
  }, [pend]) // eslint-disable-line
  return S
}
function StreakChip({ date }) {
  const S = useStreak(date)
  const [show, setShow] = React.useState(false)
  return (
    <>
      <button type="button" onClick={() => { haptic(); setShow(true) }} aria-label={`Seri ${S.count} gün${S.freezeReady ? ', dondurma hazır' : ''}. Ayrıntılar`}
        className={cn('press glass flex h-11 items-center gap-1.5 rounded-full pl-3 pr-3.5 text-sm font-semibold tabular', !S.activeToday && S.count > 0 && 'opacity-80')}>
        <IconFlame className={cn('size-5', S.count > 0 ? 'text-primary' : 'text-muted-foreground')} stroke={1.8} />
        {S.count}
        {S.freezeReady && <IconSnowflake className="size-4 text-sky-500" stroke={1.8} aria-hidden />}
      </button>
      {show && <StreakSheet date={date} S={S} onClose={() => setShow(false)} />}
    </>
  )
}
function StreakSheet({ date, S, onClose }) {
  const { db } = useApp()
  const cal = streakCalendar(db, date, 35)
  const lead = (dowIdx(cal[0].k) + 7) % 7
  return (
    <Sheet onClose={onClose} title={`${S.count} günlük seri`} description="Yemek kaydı, tamamlanan antrenman ya da adım hedefi günü seriye sayar.">
      <div className="grid grid-cols-7 gap-1.5 text-center">
        {DAYS.map((d) => <div key={d} className="text-muted-foreground text-[11px] font-medium">{d}</div>)}
        {Array.from({ length: lead }, (_, i) => <div key={'b' + i} />)}
        {cal.map((c) => (
          <div key={c.k} className="grid place-items-center py-0.5" title={shortDate(c.k)}>
            <div className={cn('grid size-9 place-items-center rounded-full text-xs tabular',
              c.active ? 'bg-primary text-primary-foreground font-semibold' : c.frozen ? 'bg-sky-500/15 text-sky-600 dark:text-sky-400' : 'bg-foreground/[0.06] text-muted-foreground',
              c.k === date && 'ring-foreground/40 ring-2')}>
              {c.frozen ? <IconSnowflake className="size-4" aria-label="Dondurma" /> : +c.k.slice(8)}
            </div>
          </div>
        ))}
      </div>
      <div className="text-muted-foreground flex flex-wrap gap-x-4 gap-y-1 text-xs">
        <span className="flex items-center gap-1.5"><span className="bg-primary size-2.5 rounded-full" />Aktif gün</span>
        <span className="flex items-center gap-1.5"><span className="size-2.5 rounded-full bg-sky-500/60" />Dondurma</span>
      </div>
      <Card className="flex items-start gap-3 p-4">
        <IconSnowflake className="mt-0.5 size-5 shrink-0 text-sky-500" stroke={1.6} />
        <div className="text-sm"><div className="font-medium">{S.freezeReady ? 'Bu haftanın dondurması hazır' : 'Bu haftanın dondurması kullanıldı'}</div>
          <div className="text-muted-foreground">Her hafta bir boş günün seriyi bozmaz; hastalık ya da tatil olur, dert etme.</div></div>
      </Card>
    </Sheet>
  )
}

/* ---------- GM-08 Akşam hatırlatması (uygulama içi) ---------- */
function EveningNudge({ date }) {
  const { db, open, setTab } = useApp()
  const S = useStreakPure(date)
  const [hide, setHide] = React.useState(false)
  if (hide || new Date().getHours() < 19 || S.activeToday || S.count < 1) return null
  return (
    <Card className="glass grid gap-3 border-primary/30 p-4" role="status">
      <div className="flex items-start gap-3">
        <IconFlame className="text-primary mt-0.5 size-6 shrink-0" stroke={1.7} />
        <div className="min-w-0 flex-1"><div className="font-semibold">Serin {S.count} gün</div><div className="text-muted-foreground text-sm">Bugün bir kayıt ekle, seri devam etsin.</div></div>
        <Button variant="ghost" size="icon" className="-mr-2 -mt-1.5 size-11 shrink-0" aria-label="Hatırlatmayı kapat" onClick={() => setHide(true)}><IconX /></Button>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Button className="h-11" onClick={() => open('addFood', { target: { type: 'log', date: todayKey() } })}><IconPlus />Yediğini ekle</Button>
        <Button className={cn('h-11', TONAL)} variant="ghost" onClick={() => setTab('workout')}><IconBarbell />Antrenman</Button>
      </div>
    </Card>
  )
}
function useStreakPure(date) { const { db } = useApp(); return React.useMemo(() => streakOf(db, date), [db.log, db.streak, db.targets, date]) } // eslint-disable-line


/* ---------- GM-04 Haftalık skor ---------- */
function WeekScoreCard({ date }) {
  const { db } = useApp()
  const W = React.useMemo(() => weekScoreDelta(db, date), [db.log, db.targets, db.schedule, db.planMode, date]) // eslint-disable-line
  const [show, setShow] = React.useState(false)
  const d = dowIdx(date), recap = d === 6 || d === 0
  return (
    <>
      <button type="button" className="press w-full text-left" onClick={() => setShow(true)} aria-label={`Haftalık skor ${W.score}. Ayrıntılar`}>
        <Card className={cn('flex items-center gap-4 p-4', recap && 'border-primary/40')}>
          <ScoreDial value={W.score} />
          <div className="min-w-0 flex-1">
            <div className="text-muted-foreground text-xs">{recap ? 'Haftanın özeti' : 'Son 7 gün'}</div>
            <div className="font-semibold">Haftalık skor</div>
            <div className="text-muted-foreground flex items-center gap-1 text-xs tabular">
              {W.delta > 0 ? <IconArrowUpRight className="text-success size-4" /> : W.delta < 0 ? <IconArrowDownRight className="size-4" /> : null}
              {W.delta === 0 ? 'Geçen haftayla aynı' : `Geçen hafta ${W.prev}`}
            </div>
          </div>
          <IconChevronRight className="text-muted-foreground size-4 shrink-0" />
        </Card>
      </button>
      {show && (
        <Sheet onClose={() => setShow(false)} title={`Haftalık skor: ${W.score}`} description={`${shortDate(W.from)} – ${shortDate(W.to)} · geçen hafta ${W.prev}`}>
          <div className="grid gap-4">
            {W.parts.map((p) => (
              <div key={p.key} className="grid gap-1.5">
                <div className="flex items-center justify-between text-sm"><span className="font-medium">{p.label} <span className="text-muted-foreground text-xs font-normal">· %{p.w}</span></span><span className="text-muted-foreground tabular">{p.detail}</span></div>
                <Progress value={p.v == null ? 0 : p.v * 100} />
              </div>
            ))}
            <p className="text-muted-foreground text-xs">Antrenman planlanan günlere, protein hedefin %90'ına, su ve adım günlük hedeflerine göre hesaplanır. Plan yoksa antrenman payı diğerlerine dağıtılır.</p>
          </div>
        </Sheet>
      )}
    </>
  )
}
function ScoreDial({ value, size = 56 }) {
  const sw = 6, r = (size - sw) / 2, C = 2 * Math.PI * r
  return (
    <div className="relative grid shrink-0 place-items-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90" aria-hidden>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--muted)" strokeWidth={sw} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--primary)" strokeWidth={sw} strokeLinecap="round" strokeDasharray={C} strokeDashoffset={C * (1 - value / 100)} style={{ transition: 'stroke-dashoffset .8s' }} />
      </svg>
      <div className="absolute text-base font-semibold tabular">{value}</div>
    </div>
  )
}

/* ---------- GM-03 Kilo kademesi kutlaması ---------- */
export function GoalCelebration() {
  const { db, update, sheets, session } = useApp()
  const G = goalState(db)
  const pend = pendingGoals(db, G.cur, G.pts.length > 0)
  const goal = pend[0]
  const busy = (sheets?.length || 0) > 0 || !!session
  React.useEffect(() => { if (goal != null && !busy) { const t = setTimeout(() => burst({ count: 140, power: 1.1 }), 250); return () => clearTimeout(t) } }, [goal, busy])
  if (goal == null || busy) return null
  const done = () => update((d) => { d.celebrated = [...new Set([...(d.celebrated || []), ...pend])] })
  const lost = G.start != null ? G.start - G.cur : 0
  const share = async () => {
    try {
      const blob = await shareCard({ goal, start: G.start, cur: G.cur, name: db.profile?.name })
      const file = new File([blob], `balli-${goal}kg.png`, { type: 'image/png' })
      if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: `${fmt1(goal)} kg hedefine ulaştım` })
      else { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = file.name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000) }
    } catch {}
  }
  return (
    <div className="fixed inset-0 z-[70] grid place-items-center bg-background/80 p-6 backdrop-blur-xl" role="dialog" aria-modal="true" aria-labelledby="goal-h" style={{ animation: 'screen-enter .35s ease-out' }}>
      <div className="grid w-full max-w-sm justify-items-center gap-4 text-center">
        <div className="bg-primary/15 grid size-24 place-items-center rounded-full"><IconTrophy className="text-primary size-12" stroke={1.5} /></div>
        <h2 id="goal-h" className="text-3xl font-semibold tracking-tight text-balance">{fmt1(goal)} kg hedefine ulaştın!</h2>
        <p className="text-muted-foreground tabular">{G.start != null ? `${fmt1(G.start)} → ${fmt1(G.cur)} kg · toplam ${fmt1(lost)} kg` : `Şu an ${fmt1(G.cur)} kg`}</p>
        {G.goals.some((g) => g < goal && G.cur > g) && <p className="text-sm">Sıradaki durak: <span className="font-semibold">{fmt1(Math.max(...G.goals.filter((g) => g < goal && G.cur > g)))} kg</span></p>}
        <div className="mt-2 grid w-full gap-2">
          <Button size="lg" onClick={share}><IconShare />Paylaş</Button>
          <Button size="lg" variant="ghost" onClick={done}>Devam et</Button>
        </div>
      </div>
    </div>
  )
}
async function shareCard({ goal, start, cur, name }) {
  const W = 1080, H = 1350, c = document.createElement('canvas'); c.width = W; c.height = H
  const g = c.getContext('2d')
  const grd = g.createLinearGradient(0, 0, W, H); grd.addColorStop(0, '#1c1917'); grd.addColorStop(1, '#7c2d12'); g.fillStyle = grd; g.fillRect(0, 0, W, H)
  const font = (w, s) => `${w} ${s}px Geist, system-ui, -apple-system, sans-serif`
  g.fillStyle = '#fb923c'; g.font = font(600, 44); g.fillText('BALLI', 96, 150)
  g.fillStyle = '#fff'; g.font = font(700, 150); g.fillText(`${fmt1(goal)} kg`, 96, 560)
  g.font = font(500, 64); g.fillStyle = 'rgba(255,255,255,.85)'; g.fillText('hedefine ulaştım', 96, 660)
  if (start != null) { g.font = font(600, 56); g.fillStyle = '#fdba74'; g.fillText(`${fmt1(start)} → ${fmt1(cur)} kg`, 96, 860); g.font = font(500, 44); g.fillStyle = 'rgba(255,255,255,.7)'; g.fillText(`toplam ${fmt1(start - cur)} kg`, 96, 930) }
  g.font = font(500, 40); g.fillStyle = 'rgba(255,255,255,.6)'; g.fillText(`${name ? name + ' · ' : ''}${longDate(todayKey())}`, 96, H - 120)
  return new Promise((r) => c.toBlob(r, 'image/png'))
}
