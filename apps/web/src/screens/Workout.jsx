import * as React from 'react'
import { IconBarbell,
  IconPlayerPlayFilled, IconPencil, IconCheck, IconCalendarWeek, IconArrowUp, IconArrowDown, IconTrash, IconPlus, IconBrandYoutube,
  IconExternalLink, IconCircleCheckFilled, IconChevronRight, IconSwitchHorizontal, IconChevronLeft, IconTrophy, IconFlame, IconTrendingUp, IconTrendingDown, IconSparkles,
  IconMenu, IconChartBar, IconTemplate, IconWand, IconDeviceFloppy,
} from '@tabler/icons-react'
import { Button, Card, Badge, Progress, Sheet, Input, Textarea, Field, Segmented, NativeSelect, Empty, SectionTitle, Checkbox } from '@/components/ui'
import { Header, DayStrip, ExerciseMedia, ExerciseThumb, Stepper } from '@/components/common'
import { mediaFor } from '@/lib/media'
import { useApp, programFor, assignedProgram, workoutProgress, allEx, findEx, exDoneCount, lastLifted, dayLog, completeWorkout, uncompleteWorkout, toggleExDone, assignDay, setScheduleFrom, scheduleAt, freezePast, nextOnOrAfter } from '@/lib/store'
import { DAYS_LONG, todayIdx, weekDate, longDate, shortDate, fmt, fmt1, num, uid, cn, haptic, todayKey, norm, dowOf } from '@/lib/utils'
import { weeks, streakWeeks, prList, historyOf, isPR, suggestKg, strengthLevels, levelOfExercise, beatsPrevBest, LEVELS } from '@/lib/progress'
import { burst } from '@/components/confetti'
import { EXERCISES, MUSCLES, trName, searchText } from '@/lib/exercises'
import { PROGRAM_TEMPLATES, shortOf } from '@/lib/program'
const cloneProg = (p) => ({ ...JSON.parse(JSON.stringify(p)), id: uid(), blocks: p.blocks.map((b) => (b.kind === 'single' ? { ...b, id: uid(), ex: { ...b.ex, id: uid() } } : { ...b, id: uid(), exs: b.exs.map((e) => ({ ...e, id: uid() })) })) })
import { IconSearch } from '@tabler/icons-react'

const meta = (e) => `${e.sets} set · ${e.reps} ${e.unit}${num(e.kg) > 0 ? ` · ${fmt1(num(e.kg))} kg` : ''}${e.rest ? ` · ${e.rest} sn` : ''}`
const ytSearch = (q) => `https://www.youtube.com/results?search_query=${encodeURIComponent(q + ' exercise form')}`
const safeUrl = (u) => (/^https?:\/\//i.test(String(u || '').trim()) ? String(u).trim() : null)
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, Math.round(num(v))))
// görünür boyutu küçük ikon butonlarına 44 px dokunma alanı
const HIT = "relative after:absolute after:-inset-1 after:content-['']"
const live = (db) => db.programs.filter((p) => !p.temp && !p.archived)
const blockHidden = (b, edit) => b.kind === 'superset' && !b.exs.length && !edit

/* ---------- Sürükle-bırak sıralama (işaretçi olayları; dokunma + fare + klavye) ---------- */
function useDragList(count, onMove, scope = 'block') {
  const [st, setSt] = React.useState(null) // {from, to, dy, h}
  const items = React.useRef([])
  const drag = React.useRef(null)
  const setRef = (i) => (el) => { items.current[i] = el }
  const scroller = () => document.querySelector('.app-scroll')
  const targetFor = (d, y) => {
    const { from, rects } = d
    let to = from
    const c = rects[from].top + (rects[from].height / 2) + y
    for (let k = 0; k < rects.length; k++) {
      if (k === from || !rects[k]) continue
      const mid = rects[k].top + rects[k].height / 2
      if (k < from && c < mid) { to = Math.min(to, k) }
      if (k > from && c > mid) { to = Math.max(to, k) }
    }
    return to
  }
  const onPointerDown = (i) => (e) => {
    if (e.button !== undefined && e.button !== 0) return
    e.preventDefault(); e.stopPropagation()
    const el = e.currentTarget; try { el.setPointerCapture(e.pointerId) } catch {}
    const sc = scroller()
    const rects = items.current.slice(0, count).map((n) => n?.getBoundingClientRect())
    const gap = rects[1] && rects[0] ? Math.max(0, rects[1].top - rects[0].bottom) : 12
    drag.current = { from: i, startY: e.clientY, y: e.clientY, rects, gap, sc, sc0: sc?.scrollTop || 0, raf: 0 }
    haptic()
    setSt({ from: i, to: i, dy: 0, h: rects[i].height + gap })
    const loop = () => {
      const d = drag.current; if (!d) return
      const H = innerHeight, edge = 110
      const v = d.y < edge ? -Math.ceil((edge - d.y) / 8) : d.y > H - edge - 80 ? Math.ceil((d.y - (H - edge - 80)) / 8) : 0
      if (v && d.sc) d.sc.scrollTop += v
      const dy = d.y - d.startY + ((d.sc?.scrollTop || 0) - d.sc0)
      const to = targetFor(d, dy)
      setSt((p) => (p && (p.dy !== dy || p.to !== to) ? { ...p, dy, to } : p))
      d.raf = requestAnimationFrame(loop)
    }
    drag.current.raf = requestAnimationFrame(loop)
  }
  const onPointerMove = (e) => { if (drag.current) drag.current.y = e.clientY }
  const end = () => {
    const d = drag.current; if (!d) return
    cancelAnimationFrame(d.raf); drag.current = null
    setSt((p) => { if (p && p.to !== p.from) { onMove(p.from, p.to); haptic(true) } return null })
  }
  const handleProps = (i, label) => ({
    onPointerDown: onPointerDown(i), onPointerMove, onPointerUp: end, onPointerCancel: end, onClick: (e) => e.stopPropagation(),
    onKeyDown: (e) => {
      if (e.key === 'ArrowUp' && i > 0) { e.preventDefault(); onMove(i, i - 1); requestAnimationFrame(() => items.current[i - 1]?.querySelector('[data-handle]')?.focus()) }
      if (e.key === 'ArrowDown' && i < count - 1) { e.preventDefault(); onMove(i, i + 1); requestAnimationFrame(() => items.current[i + 1]?.querySelector('[data-handle]')?.focus()) }
    },
    'aria-label': `${label} — sürükleyerek ya da ok tuşlarıyla taşı`, 'data-handle': scope, tabIndex: 0, role: 'button',
  })
  const itemStyle = (i) => {
    if (!st) return undefined
    const { from, to, dy, h } = st
    if (i === from) return { transform: `translateY(${dy}px) scale(1.02)`, zIndex: 5, position: 'relative', boxShadow: '0 18px 40px -12px rgb(0 0 0 / .35)', transition: 'box-shadow .2s, scale .2s' }
    let off = 0
    if (from < to && i > from && i <= to) off = -h
    if (to < from && i >= to && i < from) off = h
    return { transform: `translateY(${off}px)`, transition: 'transform .22s cubic-bezier(.32,.72,0,1)' }
  }
  return { setRef, handleProps, itemStyle, dragging: !!st }
}

const Handle = (props) => (
  <span {...props} className="text-muted-foreground -ml-2 grid size-11 shrink-0 cursor-grab touch-none select-none place-items-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing">
    <IconMenu className="size-5" />
  </span>
)

function ExRow({ e, label, edit, dc, onOpen, onDel, handle, onCheck }) {
  const full = dc >= e.sets
  return (
    <div role="button" tabIndex={0} className={cn('flex w-full items-center gap-3 py-3 text-left active:bg-accent transition-colors', edit ? 'pl-2 pr-2' : 'px-4')}
      onClick={onOpen} onKeyDown={(ev) => (ev.key === 'Enter' || ev.key === ' ') && ev.target === ev.currentTarget && (ev.preventDefault(), onOpen())}>
      {edit && handle ? <Handle {...handle} /> : <span className="text-muted-foreground w-6 shrink-0 text-xs tabular">{label}</span>}
      <ExerciseThumb name={e.name} className={edit ? 'size-11' : undefined} />
      <div className="min-w-0 flex-1">
        <div className={cn('font-medium leading-snug', edit && 'truncate', full && !edit && 'text-muted-foreground')}>{e.name}</div>
        <div className="text-muted-foreground truncate text-xs tabular">{meta(e)}</div>
        {e.note && !edit && <div className="text-muted-foreground mt-0.5 text-xs italic">{e.note}</div>}
      </div>
      {edit ? (
        <>
          {onDel && <Button variant="ghost" size="icon" className="text-destructive size-11 shrink-0" onClick={(ev) => { ev.stopPropagation(); onDel() }} aria-label={`${e.name} sil`}><IconTrash className="size-5" /></Button>}
          <IconChevronRight className="text-muted-foreground size-4 shrink-0" />
        </>
      ) : (
        <button type="button" role="checkbox" aria-checked={full} disabled={!onCheck} aria-label={`${e.name} yapıldı`}
          className="-my-2 -mr-2 grid size-11 shrink-0 place-items-center rounded-full outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
          onClick={(ev) => { ev.stopPropagation(); onCheck?.() }} onKeyDown={(ev) => ev.stopPropagation()}>
          <Checkbox checked={full} className="size-6 rounded-lg data-[state=checked]:border-success data-[state=checked]:bg-success dark:data-[state=checked]:bg-success data-[state=checked]:text-white [&_svg]:size-4" />
        </button>
      )}
    </div>
  )
}

/* ---------------- İlerleme ---------------- */
const fmtVol = (v) => (v >= 10000 ? `${fmt1(v / 1000)} t` : `${fmt(v)} kg`)
const weekLabel = (wk) => (wk === 0 ? 'Bu hafta' : wk === -1 ? 'Geçen hafta' : wk === 1 ? 'Gelecek hafta' : wk < 0 ? `${-wk} hafta önce` : `${wk} hafta sonra`)

function MiniLine({ values, className }) {
  if (values.length < 2) return null
  const W = 300, H = 72, P = 6
  const lo = Math.min(...values), hi = Math.max(...values), span = hi - lo || 1
  const pts = values.map((v, i) => [P + (i * (W - 2 * P)) / (values.length - 1), H - P - ((v - lo) / span) * (H - 2 * P)])
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className={cn('h-[72px] w-full text-primary', className)} role="img" aria-label="Tahmini maksimum kilo grafiği">
      <polyline points={pts.map((p) => p.join(',')).join(' ')} fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
      {pts.map(([x, y], i) => <circle key={i} cx={x} cy={y} r={i === pts.length - 1 ? 4 : 2.5} fill="currentColor" />)}
    </svg>
  )
}

function VolumeBars({ W }) {
  const max = Math.max(1, ...W.map((w) => w.vol))
  return (
    <div className="grid grid-cols-8 items-end gap-1.5" role="img" aria-label="Son 8 haftanın hacmi">
      {W.map((w, i) => (
        <div key={w.start} className="flex flex-col items-center gap-1">
          <div className="text-muted-foreground text-[11px] tabular">{w.vol ? fmt1(w.vol / 1000) : ''}</div>
          <div className="relative h-28 w-full border-b">
            <div className={cn('absolute inset-x-0 bottom-0 rounded-t-md transition-all duration-500', i === W.length - 1 ? 'bg-primary' : 'bg-foreground/25')} style={{ height: w.vol ? `max(4px, ${(w.vol / max) * 100}%)` : 0 }} />
          </div>
          <div className="text-muted-foreground text-[11px] tabular">{shortDate(w.start).split(' ')[0]}</div>
        </div>
      ))}
    </div>
  )
}

/* ---------------- Güç seviyesi (GM-06) ---------------- */
const LEVEL_TONE = ['bg-muted text-foreground', 'bg-chart-2/15 text-foreground', 'bg-primary/12 text-foreground', 'bg-primary/25 text-foreground', 'bg-primary text-primary-foreground']
export const LevelChip = ({ idx, className }) => (
  <span className={cn('inline-flex h-6 shrink-0 items-center rounded-full px-2.5 text-xs font-semibold', LEVEL_TONE[idx] || LEVEL_TONE[0], className)}>{LEVELS[idx]}</span>
)
function StrengthSection() {
  const { db, update, open } = useApp()
  const S = React.useMemo(() => strengthLevels(db), [db.log, db.programs, db.measures, db.profile]) // eslint-disable-line
  const setSex = (sex) => { haptic(); update((d) => { d.profile.sex = sex }) }
  return (
    <div className="grid gap-2">
      <SectionTitle action={db.profile?.sex && <span className="text-muted-foreground text-xs">{S.bw ? `${fmt1(S.bw)} kg` : ''}</span>}>Güç seviyesi</SectionTitle>
      <div className="grid gap-1.5">
        <div className="text-muted-foreground text-xs">Güç standardı</div>
        <Segmented value={db.profile?.sex || null} onChange={setSex} options={[['m', 'Erkek'], ['f', 'Kadın']]} />
      </div>
      {S.need === 'sex' ? (
        <p className="text-muted-foreground text-sm">Seviyeni hesaplamak için hangi standarda göre ölçeceğini seç.</p>
      ) : S.need === 'bw' && !S.rows.length ? (
        <Empty icon={IconBarbell} title="Kilonu gir" action={<Button variant="outline" onClick={() => open('measure', { quick: true })}>Kilo gir</Button>}>Güç seviyesi, kaldırdığın kilonun vücut ağırlığına oranıyla hesaplanır.</Empty>
      ) : S.rows.length ? (
        <Card className="divide-y overflow-hidden">
          {S.rows.map((r) => (
            <div key={r.lift.id} className="grid gap-2 px-4 py-3">
              <div className="flex items-center gap-3">
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium">{r.lift.name}</div>
                  <div className="text-muted-foreground text-xs tabular">{r.unit === 'kg' ? `≈ ${fmt1(r.value)} kg maks. · ${fmt1(r.ratio)}× vücut ağırlığı` : `En çok ${r.value} tekrar`}</div>
                </div>
                <LevelChip idx={r.idx} />
              </div>
              <Progress value={r.pct * 100} />
              <div className="text-muted-foreground text-xs tabular">{r.nextLabel ? `${r.nextLabel} için ${r.unit === 'kg' ? `+${fmt1(r.toNext)} kg` : `+${r.toNext} tekrar`}` : 'En üst seviyedesin'}</div>
            </div>
          ))}
        </Card>
      ) : (
        <Empty icon={IconBarbell} title="Henüz ana hareket kaydı yok">Bench press, squat, deadlift, overhead press, barbell row ya da barfiks setlerini tamamladığında seviyen burada görünür.</Empty>
      )}
      <p className="text-muted-foreground text-xs">Tahmini maks. (Epley) / vücut ağırlığı; eşikler Strength Level ortalamalarından yuvarlandı. Dumbbell ve makine varyantları sayılmaz.</p>
    </div>
  )
}

function ProgressSheet({ onClose }) {
  const { db } = useApp()
  const W = React.useMemo(() => weeks(db, 8), [db.log, db.programs]) // eslint-disable-line
  const prs = React.useMemo(() => prList(db).slice(0, 10), [db.log, db.programs]) // eslint-disable-line
  const streak = React.useMemo(() => streakWeeks(db), [db.log, db.programs]) // eslint-disable-line
  return (
    <Sheet onClose={onClose} title="İlerleme" description="Hacim yalnız tekrar bazlı hareketlerin tamamlanan setlerinden (kilo × tekrar) hesaplanır." full>
      <div className="grid grid-cols-3 gap-2">
        {[['Bu hafta', fmtVol(W[7].vol)], ['Antrenman', `${W[7].workouts} gün`], ['Seri', `${streak} hafta`]].map(([l, v]) => (
          <div key={l} className="bg-muted/60 rounded-lg p-3"><div className="text-muted-foreground text-xs">{l}</div><div className="mt-0.5 font-semibold tabular">{v}</div></div>
        ))}
      </div>
      <div className="grid gap-2">
        <SectionTitle>Haftalık hacim (ton)</SectionTitle>
        <VolumeBars W={W} />
      </div>
      <div className="grid gap-2">
        <SectionTitle>Son rekorlar</SectionTitle>
        {prs.length ? (
          <Card className="divide-y overflow-hidden">
            {prs.map((p, i) => (
              <div key={i} className="flex items-center gap-3 px-4 py-3">
                <IconTrophy className="text-primary size-5 shrink-0" stroke={1.75} />
                <div className="min-w-0 flex-1"><div className="truncate font-medium">{p.name}</div><div className="text-muted-foreground text-xs tabular">{longDate(p.date)}</div></div>
                <div className="text-right"><div className="font-semibold tabular">{fmt1(p.kg)} kg × {p.reps}</div><div className="text-muted-foreground text-xs tabular">≈ {fmt1(p.e1rm)} kg maks.</div></div>
              </div>
            ))}
          </Card>
        ) : <Empty icon={IconTrophy} title="Henüz rekor yok">Bir hareketi ikinci kez yapıp öncekini geçtiğinde burada görünür.</Empty>}
      </div>
      <StrengthSection />
    </Sheet>
  )
}

function WeekNav({ wk, setWk }) {
  return (
    <div className="-my-1 flex items-center justify-between gap-2">
      <Button variant="ghost" size="icon" className="size-11" onClick={() => setWk(wk - 1)} aria-label="Önceki hafta"><IconChevronLeft /></Button>
      <div className="text-center">
        <div className="text-sm font-medium">{weekLabel(wk)}</div>
        <div className="text-muted-foreground text-xs tabular">{shortDate(weekDate(0, wk))} – {shortDate(weekDate(6, wk))}</div>
      </div>
      <div className="flex items-center">
        {wk !== 0 && <Button variant="ghost" className="h-11 px-3 text-sm" onClick={() => setWk(0)}>Bugün</Button>}
        <Button variant="ghost" size="icon" className="size-11" onClick={() => setWk(wk + 1)} aria-label="Sonraki hafta"><IconChevronRight /></Button>
      </div>
    </div>
  )
}

// Süperset kartı: tüm kenarda ince renkli çerçeve (ısınma turuncu, soğuma mavi, normal nötr)
const tagBorder = (b) => (b.tag === 'warm' ? 'border-[1.5px] border-primary dark:border-primary' : b.tag === 'cool' ? 'border-[1.5px] border-chart-2 dark:border-chart-2' : 'border-[1.5px] border-foreground/70 dark:border-foreground/60')

// Süperset içindeki hareketler (düzenleme modunda kendi içinde sürüklenir)
function SupersetExs({ b, no, edit, rowProps, pid }) {
  const { update, withUndo } = useApp()
  const move = (from, to) => update((d) => { freezePast(d, pid); const B = d.programs.find((x) => x.id === pid)?.blocks.find((x) => x.id === b.id); if (!B) return; const [e] = B.exs.splice(from, 1); B.exs.splice(to, 0, e) })
  const del = (e) => withUndo(`${e.name} silindi`, (d) => { freezePast(d, pid); const B = d.programs.find((x) => x.id === pid)?.blocks.find((x) => x.id === b.id); const k = B?.exs.findIndex((x) => x.id === e.id); if (k >= 0) B.exs.splice(k, 1) })
  const D = useDragList(b.exs.length, move, 'inner')
  return (
    <div className="divide-y">
      {b.exs.map((e, k) => (
        <div key={e.id} ref={D.setRef(k)} style={D.itemStyle(k)} className="bg-card">
          <ExRow {...rowProps(e)} label={no + String.fromCharCode(97 + k)} handle={edit && b.exs.length > 1 ? D.handleProps(k, e.name) : null} onDel={edit ? () => del(e) : null} />
        </div>
      ))}
    </div>
  )
}

function BlockList({ prog, edit, rowProps }) {
  const { update, withUndo, open } = useApp()
  const pid = prog.id
  const move = (from, to) => update((d) => { freezePast(d, pid); const p = d.programs.find((x) => x.id === pid); if (!p) return; const [b] = p.blocks.splice(from, 1); p.blocks.splice(to, 0, b) })
  const delB = (b) => withUndo(`${b.kind === 'single' ? b.ex.name : 'Süperset'} silindi`, (d) => { freezePast(d, pid); const p = d.programs.find((x) => x.id === pid); const k = p?.blocks.findIndex((x) => x.id === b.id); if (k >= 0) p.blocks.splice(k, 1) })
  const D = useDragList(prog.blocks.length, move)
  let n = 0
  return (
    <div className="grid gap-3">
      {prog.blocks.map((b, bi) => {
        if (blockHidden(b, edit)) return null
        n++; const no = n
        const style = D.itemStyle(bi)
        if (b.kind === 'single') return (
          <div key={b.id} ref={D.setRef(bi)} style={style}>
            <Card className="overflow-hidden"><ExRow {...rowProps(b.ex)} label={'#' + no} handle={edit ? D.handleProps(bi, b.ex.name) : null} onDel={edit ? () => delB(b) : null} /></Card>
          </div>
        )
        return (
          <div key={b.id} ref={D.setRef(bi)} style={style}>
            <Card className={cn('overflow-hidden', tagBorder(b))}>
              <div className={cn('flex items-center gap-1.5 pt-3', edit ? 'pl-2 pr-2' : 'px-4')}>
                {edit && <Handle {...D.handleProps(bi, 'Süperset')} />}
                <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
                  <Badge variant="secondary">Süperset</Badge>
                  {b.tag === 'warm' && <Badge variant="soft">Isınma</Badge>}
                  {b.tag === 'cool' && <Badge variant="outline">Soğuma</Badge>}
                  <span className="text-muted-foreground text-xs tabular">{b.rounds} tur · {b.rest} sn dinlenme</span>
                </div>
                {edit && (
                  <div className="flex shrink-0">
                    <Button variant="ghost" size="icon" className="size-11" onClick={() => open('blockForm', { pid, bid: b.id })} aria-label="Süperseti düzenle"><IconPencil className="size-5" /></Button>
                    <Button variant="ghost" size="icon" className="text-destructive size-11" onClick={() => delB(b)} aria-label="Süperseti sil"><IconTrash className="size-5" /></Button>
                  </div>
                )}
              </div>
              {b.note && <p className="text-muted-foreground px-4 pt-2 text-xs">{b.note}</p>}
              {!b.exs.length && <p className="text-muted-foreground px-4 pt-2 text-xs">Henüz hareket yok. Aşağıdan ekle.</p>}
              <SupersetExs b={b} no={no} edit={edit} rowProps={rowProps} pid={pid} />
              {edit && <div className="px-4 pb-3"><Button variant="secondary" className="h-11" onClick={() => open('exPicker', { pid, bid: b.id })}><IconPlus />Süperset'e hareket</Button></div>}
              {!edit && <div className="pb-1" />}
            </Card>
          </div>
        )
      })}
    </div>
  )
}

// Boş günde "Hareket ekle" → hazır plan ya da kendi planı; varsayılan olarak her hafta aynı gün tekrar eder
const RepeatToggle = ({ date, value, onChange }) => date < todayKey() ? null : (
  <button type="button" className="flex min-h-11 items-center gap-2.5 text-left text-sm" onClick={() => onChange(!value)} aria-pressed={value}>
    <Checkbox checked={value} />Her {DAYS_LONG[dowOf(date)].toLocaleLowerCase('tr')} tekrarla
  </button>
)
function DayPlanSheet({ onClose, date }) {
  const { open } = useApp()
  const [repeat, setRepeat] = React.useState(date >= todayKey())
  const Opt = ({ icon: I, title, desc, onClick }) => (
    <button type="button" onClick={onClick} className="press bg-card flex w-full items-center gap-4 rounded-lg border p-4 text-left dark:border-transparent">
      <span className="bg-primary/12 text-primary grid size-12 shrink-0 place-items-center rounded-full"><I className="size-6" /></span>
      <span className="min-w-0 flex-1"><span className="block font-semibold">{title}</span><span className="text-muted-foreground block text-sm">{desc}</span></span>
      <IconChevronRight className="text-muted-foreground size-4 shrink-0" />
    </button>
  )
  return (
    <Sheet onClose={onClose} title="Hareket ekle" description={`${longDate(date)} için`}>
      {(close) => (
        <div className="grid gap-3">
          <Opt icon={IconTemplate} title="Hazır plan yükle" desc="Kayıtlı antrenmanların ya da hazır programlardan seç." onClick={() => { close(); setTimeout(() => open('pickProgram', { date, mode: 'load', repeat }), 380) }} />
          <Opt icon={IconWand} title="Kendi planını oluştur" desc="Hareketleri tek tek seç; plan ancak hareket eklersen kaydedilir." onClick={() => { close(); setTimeout(() => open('exPicker', { newFor: { date, repeat } }), 380) }} />
          <RepeatToggle date={date} value={repeat} onChange={setRepeat} />
        </div>
      )}
    </Sheet>
  )
}

// Bu güne özel (geçici) planı adlandırıp kalıcı şablona çevirir
function SaveTemplateCard({ prog }) {
  const { update, toast } = useApp()
  const [name, setName] = React.useState(prog.name === 'Bugünün planı' ? '' : prog.name)
  const save = () => {
    const nm = name.trim(); if (!nm) return
    update((d) => { const p = d.programs.find((x) => x.id === prog.id); if (!p) return; p.name = nm; delete p.temp; if (!d.cycle.includes(p.id)) d.cycle.push(p.id) })
    haptic(true); toast(`“${nm}” şablon olarak kaydedildi`)
  }
  return (
    <Card className="grid gap-3 p-4">
      <div className="flex items-center gap-2 font-medium"><IconDeviceFloppy className="text-primary size-5" />Bunu şablon olarak kaydet</div>
      <p className="text-muted-foreground -mt-1 text-sm">Kaydedersen başka günlere de atayabilirsin.</p>
      <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); save() }}>
        <Input placeholder="Şablon adı (ör. Kol + Karın)" value={name} onChange={(e) => setName(e.target.value)} aria-label="Şablon adı" maxLength={40} />
        <Button type="submit" disabled={!name.trim() || !allEx(prog).length} className="shrink-0">Kaydet</Button>
      </form>
      {!allEx(prog).length && <p className="text-muted-foreground text-xs">Kaydetmek için önce en az bir hareket ekle.</p>}
    </Card>
  )
}

export default function Workout() {
  const { toast, db, update, open, session, setSession } = useApp()
  const [day, setDay] = React.useState(todayIdx())
  const [wk, setWkRaw] = React.useState(0) // hafta kaydırma: 0 bu hafta, -1 geçen hafta
  const setWk = (w) => { setWkRaw(w); if (w === 0) setDay(todayIdx()) }
  const [edit, setEdit] = React.useState(false)
  const [sheet, setSheet] = React.useState(null) // 'progress' | 'plan'
  const date = weekDate(day, wk)
  const future = date > todayKey()
  const prog = programFor(db, date)
  const empty = !prog ? assignedProgram(db, date) : null // atanmış ama hareketsiz program: dinlenme görünür, hareket ona eklenir
  const wp = prog ? workoutProgress(db, prog, date) : null
  const pid = prog?.id
  React.useEffect(() => { if (!prog) setEdit(false) }, [pid]) // eslint-disable-line
  const labelOf = (i) => shortOf(programFor(db, weekDate(i, wk)))
  // gün şeridi: tamamlandı · planlı ama yapılmadı · off
  const statusOf = (i) => { const d = weekDate(i, wk); const p = programFor(db, d); return !p ? 'rest' : workoutProgress(db, p, d).complete ? 'done' : 'todo' }
  const exOpen = (e) => () => open(edit ? 'exForm' : 'exercise', { pid, eid: e.id, date })
  const check = (e) => () => { haptic(true); update((d) => toggleExDone(d, date, pid, e)) }
  const rowProps = (e) => ({ e, edit, dc: exDoneCount(db, e, date), onOpen: exOpen(e), onCheck: future ? null : check(e) })
  const running = session && session.pid === pid && session.date === date

  return (
    <div className="grid gap-4">
      <Header
        eyebrow={`${DAYS_LONG[day]} · ${longDate(date)}`}
        title={prog ? prog.name : 'Dinlenme'}
        sub={prog ? `${allEx(prog).length} hareket · ${wp.done}/${wp.tot} set` : 'Bu güne program atanmadı'}
        actions={edit && prog ? (
          <Button variant="ghost" className="h-11 px-3 font-semibold text-primary" onClick={() => setEdit(false)}>Bitti</Button>
        ) : <>
          <Button variant="outline" size="icon" className={HIT} onClick={() => setSheet('progress')} aria-label="İlerleme"><IconChartBar /></Button>
          <Button variant="outline" size="icon" className={HIT} onClick={() => open('programs')} aria-label="Programlar ve günler"><IconCalendarWeek /></Button>
          {prog && <Button variant="outline" size="icon" className={HIT} onClick={() => setEdit(true)} aria-label="Düzenle"><IconPencil /></Button>}
        </>}
      />

      <div className="grid gap-2">
        <WeekNav wk={wk} setWk={setWk} />
        <DayStrip value={day} onChange={setDay} todayIndex={wk === 0 ? todayIdx() : -1} label={labelOf} status={statusOf} />
      </div>

      {prog && !edit && wp.tot > 0 && (
        <div className="grid gap-3">
          {future && <p className="text-muted-foreground text-center text-xs">Bu gün henüz gelmedi; planı görebilirsin.</p>}
          <div className="grid grid-cols-[1fr_auto] gap-2">
            <Button size="lg" onClick={() => setSession({ pid: prog.id, date, minimized: false })} disabled={!wp.tot || future}><IconPlayerPlayFilled className="size-4" />{running ? 'Antrenmana dön' : wp.done ? 'Antrenmana devam et' : 'Antrenmanı başlat'}</Button>
            <Button size="lg" variant="outline" onClick={() => open('pickProgram', { date })} aria-label="Bu güne farklı program"><IconSwitchHorizontal /></Button>
          </div>
        </div>
      )}

      {!prog ? (
        <Empty icon={IconCalendarWeek} title="Dinlenme günü" action={<Button onClick={() => (empty ? open('exPicker', { pid: empty.id }) : setSheet('plan'))}><IconPlus />Hareket ekle</Button>}>
          Bu güne antrenman eklemek için hazır bir plan yükle ya da kendi planını oluştur. Eklediğin plan her hafta aynı günde tekrar eder.
        </Empty>
      ) : !wp.tot && !edit ? (
        <Empty icon={IconPlus} title="Bu program boş" action={<Button onClick={() => { setEdit(true); open('exPicker', { pid }) }}><IconPlus />Hareket ekle</Button>}>Hareketleri kendin ekleyebilirsin.</Empty>
      ) : (
        <BlockList prog={prog} edit={edit} rowProps={rowProps} />
      )}

      {prog && edit && (
        <div className="grid grid-cols-2 gap-2">
          <Button className="h-11" onClick={() => open('exPicker', { pid })}><IconPlus />Hareket</Button>
          <Button variant="outline" className="h-11" onClick={() => open('blockForm', { pid })}><IconPlus />Süperset</Button>
        </div>
      )}
      {prog?.temp && <SaveTemplateCard key={prog.id} prog={prog} />}

      {prog && !edit && !future && wp.tot > 0 && (wp.complete ? (
        <Button variant="ghost" className="text-muted-foreground h-11" onClick={() => { haptic(); update((d) => uncompleteWorkout(d, date, prog.id)); toast('Tamamlandı işareti kaldırıldı') }}>Tamamlandı işaretini kaldır</Button>
      ) : (
        <Button variant="outline" className="h-11" onClick={() => { haptic(true); update((d) => completeWorkout(d, date, prog.id)); toast('Antrenman tamamlandı') }}><IconCheck />Antrenmanı yaptım olarak işaretle</Button>
      ))}
      {sheet === 'progress' && <ProgressSheet onClose={() => setSheet(null)} />}
      {sheet === 'plan' && <DayPlanSheet date={date} onClose={() => setSheet(null)} />}
    </div>
  )
}

/* ---------------- Sheets ---------------- */
export function ExerciseSheet({ onClose, pid, eid, date }) {
  const { withUndo, toast, db, update: upd } = useApp()
  const future = date > todayKey()
  const update = React.useCallback((fn) => { if (!future) upd(fn) }, [future, upd]) // gelecek güne kayıt girilmez
  const e = findEx(db, pid, eid)
  const [tkg, setTkg] = React.useState(num(e?.kg) > 0 ? String(e.kg).replace('.', ',') : '')
  React.useEffect(() => { if (!e) onClose?.() }, [!e]) // eslint-disable-line
  if (!e) return null
  const L = db.log[date] || {}
  const S = L.sets?.[eid] || []
  const done = !!L.exDone?.[eid]
  const prev = lastLifted(db, eid, date)
  const sug = React.useMemo(() => suggestKg(db, e, date), [db.log, db.programs, e.name, e.reps, e.sets, date]) // eslint-disable-line
  const hist = React.useMemo(() => (e.unit === 'tekrar' ? historyOf(db, e.name) : []), [db.log, db.programs, e.name, e.unit]) // eslint-disable-line
  const pr = React.useMemo(() => hist.length > 1 && isPR(db, e.name, date), [hist, date]) // eslint-disable-line
  const fillSug = () => { haptic(); update((d) => { const SS = (dayLog(d, date).sets ??= {}); const arr = (SS[eid] ??= []); for (let i = 0; i < e.sets; i++) if (!num(arr[i]?.kg)) arr[i] = { ...(arr[i] || {}), kg: String(sug.kg) } }) }
  // negatif ve metin girişini engelle: kg ondalıklı, tekrar tam sayı
  const clean = (k, v) => {
    if (k === 'kg') { const t = String(v).replace(/[^\d.,]/g, '').replace(/([.,].*)[.,]/g, '$1'); return num(t) > 999 ? '999' : t }
    if (k === 'reps') { const t = String(v).replace(/\D/g, '').slice(0, 3); return t }
    return v
  }
  const setVal = (i, k, v) => update((d) => { const D = dayLog(d, date); const SS = (D.sets ??= {}); const arr = (SS[eid] ??= []); arr[i] = { ...(arr[i] || {}), [k]: clean(k, v) }; if (k === 'done' && D.exDone?.[eid] === false) delete D.exDone[eid] })
  // Plan değerleri (set, tekrar, hedef kilo, dinlenme) programa yazılır; gelecek günlerde de düzenlenebilir, geçmiş günler korunur
  const ssB = db.programs.find((p) => p.id === pid)?.blocks.find((b) => b.kind === 'superset' && b.exs.some((x) => x.id === eid))
  const setSets = (n) => { haptic(); upd((d) => { freezePast(d, pid); const p = d.programs.find((x) => x.id === pid); if (!p) return
    for (const b of p.blocks) {
      if (b.kind === 'single' && b.ex.id === eid) b.ex.sets = n
      if (b.kind === 'superset' && b.exs.some((x) => x.id === eid)) { b.rounds = n; b.exs.forEach((x) => { x.sets = n }) }
    } }) }
  // Tekrar ve dinlenme de plana yazılır (süpersette dinlenme = tur arası dinlenme)
  const setPlan = (k, n) => { haptic(); upd((d) => { const x = findEx(d, pid, eid); if (!x) return
    const p = d.programs.find((y) => y.id === pid); const sb = p?.blocks.find((b) => b.kind === 'superset' && b.exs.some((y) => y.id === eid))
    const cur = k === 'rest' && sb ? sb.rest : x[k]; if (num(cur) === n) return
    freezePast(d, pid); const p2 = d.programs.find((y) => y.id === pid); const sb2 = p2?.blocks.find((b) => b.kind === 'superset' && b.exs.some((y) => y.id === eid))
    if (k === 'rest' && sb2) sb2.rest = n; else findEx(d, pid, eid)[k] = n }) }
  const restNow = ssB ? num(ssB.rest) : num(e.rest)
  const saveKg = (raw) => { const t = clean('kg', raw); setTkg(t); upd((d) => { const x = findEx(d, pid, eid); if (x && String(x.kg ?? '') !== String(num(t) || '')) { freezePast(d, pid); const y = findEx(d, pid, eid); if (num(t) > 0) y.kg = num(t); else delete y.kg } }) }
  const lvl = React.useMemo(() => (e.unit === 'tekrar' ? levelOfExercise(db, e.name) : null), [db.log, db.programs, db.measures, db.profile, e.name]) // eslint-disable-line
  const toggle = (i) => {
    const on = !S[i]?.done
    haptic(on)
    // GM-08: önceki en iyiyi geçen set → konfeti + "Yeni rekor!" (günde hareket başına bir kez)
    if (on && e.unit === 'tekrar' && !future) {
      const s = S[i] || {}, kg = num(s.kg), reps = num(s.reps) || num(e.reps)
      const seen = db.log[date]?.prShown || []
      if (!seen.includes(norm(e.name)) && beatsPrevBest(db, e.name, date, kg, reps)) {
        update((d) => { const D = dayLog(d, date); (D.prShown ??= []).push(norm(e.name)) })
        burst(); toast(`Yeni rekor! ${e.name}`)
      }
    }
    setVal(i, 'done', on)
  }
  const markAll = () => { haptic(); update((d) => { const X = (dayLog(d, date).exDone ??= {}); X[eid] = !X[eid] }) }
  return (
    <Sheet onClose={onClose} title={e.name} description={[e.muscle, meta(e)].filter(Boolean).join(' · ')}
      footer={future ? <p className="text-muted-foreground py-2 text-center text-sm">Bu gün henüz gelmedi; plan değerlerini şimdiden ayarlayabilirsin, set kaydı o gün açılır.</p> : <Button size="lg" variant={done ? 'outline' : 'default'} onClick={markAll}>{done ? 'İşareti kaldır' : <><IconCheck />Hareketi yaptım</>}</Button>}>
      <ExerciseMedia name={e.name} />
      <a href={safeUrl(e.video) || ytSearch(e.name)} target="_blank" rel="noopener noreferrer" className="press flex min-h-11 items-center gap-2.5 text-sm">
        <IconBrandYoutube className="text-destructive size-5 shrink-0" stroke={1.5} />
        <span className="flex-1 font-medium">{safeUrl(e.video) ? 'Hareket videosunu aç' : 'YouTube\'da form videosu izle'}</span>
        <IconExternalLink className="text-muted-foreground size-4" />
      </a>
      {prev && <div className="text-muted-foreground text-sm">Son seferde <span className="text-foreground font-medium tabular">{prev.kg} kg × {prev.reps || e.reps}</span> · {longDate(prev.date)}</div>}
      {sug && (
        <button type="button" onClick={fillSug} className="press bg-primary/10 flex min-h-11 items-center gap-2.5 rounded-full px-4 text-left text-sm">
          <IconSparkles className="text-primary size-4 shrink-0" />
          <span className="flex-1"><span className="font-semibold tabular">Öneri: {fmt1(sug.kg)} kg</span><span className="text-muted-foreground"> · {sug.up ? 'geçen sefer hedefi tamamladın' : 'geçen seferki kiloyla devam'}</span></span>
          <span className="text-primary text-xs font-semibold">Doldur</span>
        </button>
      )}
      <div className="grid grid-cols-2 gap-3">
        <Field label={ssB ? 'Tur (süperset)' : 'Set sayısı'}><Stepper value={e.sets} onChange={(v) => setSets(Math.min(20, Math.max(1, v)))} min={1} /></Field>
        {e.unit === 'tekrar' && <Field label="Hedef kilo" id="ex-tkg"><div className="relative"><Input id="ex-tkg" className="pr-9 text-center" inputMode="decimal" placeholder="–" value={tkg} onChange={(ev) => saveKg(ev.target.value)} /><span className="text-muted-foreground absolute right-3 top-1/2 -translate-y-1/2 text-xs">kg</span></div></Field>}
        <Field label={e.unit === 'tekrar' ? 'Tekrar' : e.unit === 'sn' ? 'Süre (sn)' : 'Süre (dk)'}><Stepper value={num(e.reps)} onChange={(v) => setPlan('reps', Math.min(999, Math.max(1, v)))} min={1} /></Field>
        <Field label={ssB ? 'Tur arası dinlenme' : 'Dinlenme'}><Stepper value={restNow} step={15} suffix=" sn" onChange={(v) => setPlan('rest', Math.min(900, Math.max(0, v)))} min={0} /></Field>
      </div>
      <div className="grid gap-2">
        <div className="text-muted-foreground grid grid-cols-[2rem_1fr_1fr_2.75rem] gap-2 text-xs font-medium"><span>Set</span><span className="text-center">Kg</span><span className="text-center capitalize">{e.unit}</span><span /></div>
        {Array.from({ length: e.sets }, (_, i) => {
          const s = S[i] || {}; const ok = s.done || done
          return (
            <div key={i} className="grid grid-cols-[2rem_1fr_1fr_2.75rem] items-center gap-2">
              <span className="text-muted-foreground text-sm tabular">{i + 1}</span>
              <Input className="text-center" inputMode="decimal" disabled={future} placeholder={num(e.kg) > 0 ? fmt1(num(e.kg)) : prev ? String(prev.kg) : '–'} value={s.kg ?? ''} onChange={(ev) => setVal(i, 'kg', ev.target.value)} aria-label={`Set ${i + 1} kilo`} />
              <Input className="text-center" inputMode="numeric" disabled={future} placeholder={String(e.reps)} value={s.reps ?? ''} onChange={(ev) => setVal(i, 'reps', ev.target.value)} aria-label={`Set ${i + 1} ${e.unit}`} />
              <Button size="icon" variant={ok ? 'default' : 'outline'} className={cn(HIT, ok && 'bg-success text-white done-pulse')} disabled={future} onClick={() => toggle(i)} aria-label={`Set ${i + 1} tamam`}><IconCheck className="size-5" /></Button>
            </div>
          )
        })}
      </div>
      {hist.length > 0 && (
        <div className="grid gap-2">
          <div className="flex items-center gap-2">
            <div className="text-muted-foreground text-xs font-medium uppercase tracking-wider">Geçmiş</div>
            {pr && <Badge className="gap-1"><IconTrophy className="size-3.5" />Yeni rekor</Badge>}
            {lvl && <LevelChip idx={lvl.idx} className="ml-auto" />}
          </div>
          {hist.length > 1 && (
            <div className="bg-muted/50 rounded-lg px-3 pt-2 pb-1">
              <div className="text-muted-foreground flex justify-between text-xs tabular"><span>Tahmini maks. (e1RM)</span><span className="text-foreground font-medium">{fmt1(hist.at(-1).best.e1rm)} kg</span></div>
              <MiniLine values={hist.slice(-12).map((h) => h.best.e1rm)} />
            </div>
          )}
          <div className="divide-y rounded-lg border dark:border-transparent dark:bg-muted/40">
            {hist.slice(-5).reverse().map((h) => (
              <div key={h.date} className="flex items-center justify-between px-3 py-2.5 text-sm">
                <span className="text-muted-foreground tabular">{longDate(h.date)}</span>
                <span className="font-medium tabular">{fmt1(h.best.kg)} kg × {h.best.reps}<span className="text-muted-foreground font-normal"> · {h.sets.length} set</span></span>
              </div>
            ))}
          </div>
        </div>
      )}
      {(e.desc || mediaFor(e.name)?.tr) && <div className="grid gap-1"><div className="text-muted-foreground text-xs font-medium uppercase tracking-wider">Nasıl yapılır</div><p className="text-sm leading-relaxed">{e.desc || mediaFor(e.name).tr}</p></div>}
      {e.note && <p className="text-muted-foreground text-sm">{e.note}</p>}
    </Sheet>
  )
}

export function ExForm({ onClose, pid, eid, bid, preset }) {
  const { withUndo, toast, db, update } = useApp()
  const cur = eid ? findEx(db, pid, eid) : null
  const prog = db.programs.find((x) => x.id === pid)
  // süpersetteki hareketin set sayısı = tur sayısı
  const ssBlock = prog?.blocks.find((b) => b.kind === 'superset' && (b.id === bid || (eid && b.exs.some((e) => e.id === eid))))
  const gone = (eid && !cur) || !prog
  React.useEffect(() => { if (gone) onClose?.() }, [gone]) // eslint-disable-line
  const [f, setF] = React.useState(cur ? { ...cur, kg: num(cur.kg) > 0 ? String(cur.kg).replace('.', ',') : '' } : { name: preset || '', sets: 3, reps: 12, kg: '', unit: 'tekrar', rest: 60, muscle: '', desc: '', note: '', video: '' })
  const s = (k) => (v) => setF((x) => ({ ...x, [k]: v }))
  if (gone) return null
  const save = (close) => {
    if (!f.name.trim()) return
    const { kg, ...rest } = f
    const v = { ...rest, name: f.name.trim(), sets: ssBlock ? Math.max(1, num(ssBlock.rounds) || 1) : clamp(f.sets, 1, 20), reps: clamp(f.reps, 1, 999), rest: clamp(f.rest, 0, 900), ...(f.unit === 'tekrar' && num(kg) > 0 ? { kg: Math.min(999, num(kg)) } : {}) }
    update((d) => {
      freezePast(d, pid)
      const p = d.programs.find((x) => x.id === pid)
      if (!p) return
      if (eid) p.blocks.forEach((b) => { if (b.kind === 'single' && b.ex.id === eid) b.ex = { ...v, id: eid }; if (b.kind === 'superset') { const k = b.exs.findIndex((e) => e.id === eid); if (k >= 0) b.exs[k] = { ...v, id: eid } } })
      else if (bid) p.blocks.find((b) => b.id === bid)?.exs.push({ ...v, id: uid() })
      else p.blocks.push({ id: uid(), kind: 'single', ex: { ...v, id: uid() } })
      if (!eid) { d.customExercises ??= []; if (!d.customExercises.some((x) => norm(x.name) === norm(v.name))) d.customExercises.push({ name: v.name, muscle: v.muscle, unit: v.unit, sets: v.sets, reps: v.reps, rest: v.rest }) }
    })
    close()
  }
  const remove = (close) => {
    close()
    withUndo(`${cur.name} silindi`, (d) => {
      freezePast(d, pid)
      const p = d.programs.find((x) => x.id === pid); if (!p) return
      for (let i = p.blocks.length - 1; i >= 0; i--) {
        const b = p.blocks[i]
        if (b.kind === 'single') { if (b.ex.id === eid) p.blocks.splice(i, 1) }
        else { const k = b.exs.findIndex((e) => e.id === eid); if (k >= 0) { b.exs.splice(k, 1); if (!b.exs.length) p.blocks.splice(i, 1) } }
      }
    })
  }
  return (
    <Sheet onClose={onClose} title={eid ? 'Hareketi düzenle' : 'Yeni hareket'} footer={(close) => <>
      <Button size="lg" onClick={() => save(close)} disabled={!f.name.trim()}>Kaydet</Button>
      {eid && <Button variant="ghost" className="text-destructive" onClick={() => remove(close)}>Hareketi sil</Button>}
    </>}>
      <Field label="Hareket adı" id="ex-name"><Input id="ex-name" value={f.name} onChange={(e) => s('name')(e.target.value)} placeholder="ör. Incline Dumbbell Press" /></Field>
      <Field label="Birim"><Segmented value={f.unit} onChange={s('unit')} options={[['tekrar', 'Tekrar'], ['sn', 'Saniye'], ['dk', 'Dakika']]} /></Field>
      <div className={cn('grid gap-3', ssBlock ? 'grid-cols-2' : 'grid-cols-3')}>
        {!ssBlock && <Field label="Set" id="ex-s"><Input id="ex-s" inputMode="numeric" value={f.sets} onChange={(e) => s('sets')(e.target.value.replace(/\D/g, ''))} /></Field>}
        <Field label={f.unit === 'tekrar' ? 'Tekrar' : f.unit === 'sn' ? 'Saniye' : 'Dakika'} id="ex-r"><Input id="ex-r" inputMode="numeric" value={f.reps} onChange={(e) => s('reps')(e.target.value.replace(/\D/g, ''))} /></Field>
        <Field label="Dinlenme (sn)" id="ex-rest"><Input id="ex-rest" inputMode="numeric" value={f.rest} onChange={(e) => s('rest')(e.target.value.replace(/\D/g, ''))} /></Field>
      </div>
      {ssBlock && <p className="text-muted-foreground -mt-2 text-xs">Süpersette set sayısı tur sayısıdır ({ssBlock.rounds} tur).</p>}
      {f.unit === 'tekrar' && <Field label="Hedef kilo (kg)" id="ex-kg" hint="Set girerken öneri olarak görünür."><Input id="ex-kg" inputMode="decimal" value={f.kg} onChange={(e) => s('kg')(e.target.value.replace(/[^\d.,]/g, ''))} placeholder="ör. 20" /></Field>}
      <Field label="Kas grubu" id="ex-m"><Input id="ex-m" value={f.muscle} onChange={(e) => s('muscle')(e.target.value)} placeholder="ör. Göğüs" /></Field>
      <Field label="Açıklama" id="ex-d"><Textarea id="ex-d" value={f.desc} onChange={(e) => s('desc')(e.target.value)} placeholder="Form notları, dikkat edilecekler" /></Field>
      <Field label="Kısa not" id="ex-n" hint="Listede hareket adının altında görünür."><Input id="ex-n" value={f.note} onChange={(e) => s('note')(e.target.value)} placeholder="ör. 110–130 bpm nabız" /></Field>
    </Sheet>
  )
}

export function BlockForm({ onClose, pid, bid }) {
  const { withUndo, toast, db, update } = useApp()
  const cur = bid ? db.programs.find((p) => p.id === pid)?.blocks.find((b) => b.id === bid) : null
  const gone = (bid && !cur) || !db.programs.some((p) => p.id === pid)
  React.useEffect(() => { if (gone) onClose?.() }, [gone]) // eslint-disable-line
  const [f, setF] = React.useState(cur ? { tag: cur.tag, rounds: cur.rounds, rest: cur.rest, note: cur.note } : { tag: null, rounds: 3, rest: 60, note: '' })
  const s = (k) => (v) => setF((x) => ({ ...x, [k]: v }))
  const save = (close) => {
    update((d) => { freezePast(d, pid); const p = d.programs.find((x) => x.id === pid); if (!p) return
      const v = { tag: f.tag, rounds: clamp(f.rounds, 1, 20), rest: clamp(f.rest, 0, 900), note: f.note }
      const b = bid && p.blocks.find((x) => x.id === bid)
      if (b) { Object.assign(b, v); b.exs.forEach((e) => { e.sets = v.rounds }) } else p.blocks.push({ id: uid(), kind: 'superset', exs: [], ...v }) })
    close()
  }
  if (gone) return null
  return (
    <Sheet onClose={onClose} title={bid ? 'Süperseti düzenle' : 'Yeni süperset'} description={bid ? undefined : 'Kaydettikten sonra içine hareket ekle.'} footer={(close) => <Button size="lg" onClick={() => save(close)}>Kaydet</Button>}>
      <Field label="Etiket"><Segmented value={f.tag} onChange={s('tag')} options={[[null, 'Normal'], ['warm', 'Isınma'], ['cool', 'Soğuma']]} /></Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Tur" id="b-r"><Input id="b-r" inputMode="numeric" value={f.rounds} onChange={(e) => s('rounds')(e.target.value.replace(/\D/g, ''))} /></Field>
        <Field label="Tur arası dinlenme (sn)" id="b-rest"><Input id="b-rest" inputMode="numeric" value={f.rest} onChange={(e) => s('rest')(e.target.value.replace(/\D/g, ''))} /></Field>
      </div>
      <Field label="Talimat" id="b-n"><Textarea id="b-n" value={f.note} onChange={(e) => s('note')(e.target.value)} placeholder="ör. Hareketleri arka arkaya yap, tur bitince dinlen" /></Field>
    </Sheet>
  )
}

export function ProgramsSheet({ onClose }) {
  const { withUndo, toast, db, update, open } = useApp()
  const [name, setName] = React.useState('')
  const today = todayKey()
  // her gün için sıradaki tarihteki plan (ör. cumartesi planı yarından başlıyorsa o görünür)
  const week = Object.fromEntries(DAYS_LONG.map((_, i) => { const k = weekDate(i, i < todayIdx() ? 1 : 0); return [i, scheduleAt(db, k)[i]] }))
  const add = () => { if (!name.trim()) return; update((d) => { d.programs.push({ id: uid(), name: name.trim(), blocks: [] }) }); setName('') }
  // Silmek yerine arşivler: geçmiş günler o programı göstermeye devam eder, plan bugünden itibaren boşalır
  const remove = (id) => withUndo(`${db.programs.find((p) => p.id === id)?.name} silindi`, (d) => {
    const p = d.programs.find((x) => x.id === id); if (!p) return
    p.archived = true
    for (let k = 0; k < 7; k++) if (scheduleAt(d, today)[k] === id) setScheduleFrom(d, today, k, null)
  })
  const addTemplate = (t) => {
    const T = t.fn()
    const map = {}
    let added = 0
    withUndo(`${t.name} eklendi`, (d) => {
      T.programs.forEach((p) => {
        const ex = d.programs.find((x) => !x.archived && !x.temp && x.name === p.name)
        if (ex) map[p.id] = ex.id
        else { const c = cloneProg(p); map[p.id] = c.id; d.programs.push(c); added++ }
      })
      for (const k of Object.keys(T.schedule || {})) setScheduleFrom(d, today, +k, T.schedule[k] ? map[T.schedule[k]] || null : null)
    }, 'add')
  }
  return (
    <Sheet onClose={onClose} title="Programlar" description="Hangi gün hangi antrenmanı yapacağını seç." full>
      <p className="text-muted-foreground -mb-2 text-sm">Değişiklik bugünden itibaren her hafta geçerli olur; geçmiş günler olduğu gibi kalır.</p>
      <Card className="divide-y">
        {DAYS_LONG.map((d, i) => (
          <div key={d} className="flex items-center justify-between gap-3 px-4 py-2.5">
            <span className="text-sm font-medium">{d}</span>
            <div className="w-44"><NativeSelect value={week[i] || ''} onChange={(e) => update((x) => setScheduleFrom(x, today, i, e.target.value || null))} aria-label={`${d} programı`}>
              <option value="">Dinlenme</option>{live(db).map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </NativeSelect></div>
          </div>
        ))}
      </Card>
      <SectionTitle>Programlarım</SectionTitle>
      <p className="text-muted-foreground -mt-2 text-xs">Kalemle programın hareketlerini, set, tekrar, kilo ve dinlenmesini düzenlersin; değişiklik o programın atandığı bütün gelecek günlere yansır. Küçük kutu gün kartındaki kısa ad.</p>
      <div className="grid gap-2">
        {live(db).map((p) => (
          <div key={p.id} className="flex items-center gap-2">
            <ProgName p={p} />
            <Input className="w-[5.5rem] shrink-0 px-3 text-center" maxLength={10} placeholder={shortOf({ name: p.name })} value={p.short || ''} onChange={(e) => update((d) => { const x = d.programs.find((y) => y.id === p.id); x.short = e.target.value.slice(0, 10) })} aria-label={`${p.name} kısa adı (gün kartında görünür)`} title="Kısa ad" />
            <Button variant="outline" size="icon" className={cn('shrink-0', HIT)} onClick={() => open('programEdit', { pid: p.id })} aria-label={`${p.name} programını düzenle`}><IconPencil /></Button>
            <Button variant="outline" size="icon" className={cn('shrink-0', HIT)} onClick={() => remove(p.id)} aria-label={`${p.name} programını sil`}><IconTrash /></Button>
          </div>
        ))}
        <div className="flex gap-2">
          <Input placeholder="Yeni program adı" value={name} onChange={(e) => setName(e.target.value)} />
          <Button onClick={add} disabled={!name.trim()}><IconPlus />Ekle</Button>
        </div>
      </div>
      <SectionTitle>Hazır programlar</SectionTitle>
      <div className="grid gap-2">
        <p className="text-muted-foreground -mt-2 text-sm">Seçtiğin hazır program listene eklenir ve haftalık günlere atanır.</p>
        {PROGRAM_TEMPLATES.filter((t) => t.fn).map((t) => (
          <button key={t.key} className="press text-left" onClick={() => addTemplate(t)}>
            <Card className="flex items-center gap-3 p-3"><div className="min-w-0 flex-1"><div className="text-sm font-medium">{t.name} <span className="text-muted-foreground font-normal">· {t.days} gün</span></div><div className="text-muted-foreground text-xs">{t.who}</div></div><IconPlus className="text-muted-foreground size-4" /></Card>
          </button>
        ))}
      </div>
    </Sheet>
  )
}

// Kayıtlı bir programı tek başına düzenler (hareket ekle/sil/sırala, set/tekrar/kilo/dinlenme)
export function ProgramEditSheet({ onClose, pid }) {
  const { db, open } = useApp()
  const prog = db.programs.find((p) => p.id === pid)
  React.useEffect(() => { if (!prog) onClose?.() }, [!prog]) // eslint-disable-line
  if (!prog) return null
  // her gün için sıradaki tarihteki plan (bu hafta geçtiyse gelecek hafta)
  const days = DAYS_LONG.filter((_, k) => scheduleAt(db, nextOnOrAfter(todayKey(), k))[k] === pid)
  const rowProps = (e) => ({ e, edit: true, dc: 0, onOpen: () => open('exForm', { pid, eid: e.id }) })
  return (
    <Sheet onClose={onClose} title="Programı düzenle" description={days.length ? `Her ${days.join(', ').toLocaleLowerCase('tr')} · değişiklikler gelecek haftalara yansır` : 'Henüz bir güne atanmadı'} full>
      <Field label="Program adı"><ProgName p={prog} /></Field>
      {allEx(prog).length || prog.blocks.length ? <BlockList prog={prog} edit rowProps={rowProps} /> : <Empty icon={IconPlus} title="Bu program boş">Aşağıdan hareket ekle.</Empty>}
      <div className="grid grid-cols-2 gap-2">
        <Button className="h-11" onClick={() => open('exPicker', { pid })}><IconPlus />Hareket</Button>
        <Button variant="outline" className="h-11" onClick={() => open('blockForm', { pid })}><IconPlus />Süperset</Button>
      </div>
      <p className="text-muted-foreground text-xs">Harekete dokununca set, tekrar, hedef kilo ve dinlenmeyi değiştirebilirsin. Geçmişte yaptığın antrenmanların kayıtları değişmez.</p>
    </Sheet>
  )
}

// Boş bırakılırsa önceki adı geri koyar
function ProgName({ p }) {
  const { update } = useApp()
  const last = React.useRef(p.name)
  React.useEffect(() => { if (p.name.trim()) last.current = p.name }, [p.name])
  return <Input value={p.name} onChange={(e) => update((d) => { d.programs.find((x) => x.id === p.id).name = e.target.value })}
    onBlur={() => { if (!p.name.trim()) update((d) => { d.programs.find((x) => x.id === p.id).name = last.current || 'Program' }) }} aria-label="Program adı" />
}

export function PickProgramSheet({ onClose, date, mode, repeat: rep0 }) {
  const { toast, db, update, open } = useApp()
  const cur = programFor(db, date)
  const [name, setName] = React.useState('')
  const [repeat, setRepeat] = React.useState(rep0 ?? date >= todayKey())
  const rep = repeat && date >= todayKey()
  const pick = (id, close) => { update((d) => assignDay(d, date, id, rep)); close() }
  const defaults = React.useMemo(() => PROGRAM_TEMPLATES.filter((t) => t.fn).map((t) => ({ t, list: t.fn().programs })), [])
  const pickDefault = (p, close) => {
    const existing = db.programs.find((x) => x.name === p.name && !x.temp && !x.archived)
    if (existing) return pick(existing.id, close)
    const c = cloneProg(p)
    update((d) => { d.programs.push(c); assignDay(d, date, c.id, rep) })
    toast(`${p.name} eklendi`); close()
  }
  // Program, hareket seçilip eklenince oluşur; seçici boş kapatılırsa hiçbir şey kaydedilmez
  const create = (close) => { close(); setTimeout(() => open('exPicker', { newFor: { date, repeat: rep, name: name.trim() } }), 380) }
  return (
    <Sheet onClose={onClose} title={mode === 'load' ? 'Hazır plan yükle' : 'Bu güne antrenman'} description={rep ? `Her ${DAYS_LONG[dowOf(date)].toLocaleLowerCase('tr')} tekrar eder; geçmiş günler değişmez.` : 'Sadece bu tarih için geçerli; haftalık plan değişmez.'} full>
      {(close) => (
        <>
          <RepeatToggle date={date} value={repeat} onChange={setRepeat} />
          {mode !== 'load' && <Card className="grid gap-3 p-4">
            <div className="font-medium">Yeni antrenman oluştur</div>
            <Input placeholder="ör. Kol + Karın" value={name} onChange={(e) => setName(e.target.value)} />
            <Button onClick={() => create(close)}><IconPlus />Hareket seç</Button>
          </Card>}
          <SectionTitle>Kayıtlı antrenmanlar</SectionTitle>
          <Card className="divide-y">
            {db.programs.filter((p) => (!p.temp && !p.archived) || p.id === cur?.id).map((p) => (
              <button key={p.id} className="flex w-full items-center justify-between px-4 py-3 text-left active:bg-accent" onClick={() => pick(p.id, close)}>
                <span><span className="font-medium">{p.name}</span><span className="text-muted-foreground block text-xs">{allEx(p).length} hareket{p.temp && ' · sadece bu gün'}</span></span>
                {cur?.id === p.id ? <IconCheck className="text-primary size-5" /> : <IconChevronRight className="text-muted-foreground size-4" />}
              </button>
            ))}
            <button className="flex w-full items-center justify-between px-4 py-3 text-left active:bg-accent" onClick={() => pick(null, close)}>
              <span className="font-medium">Dinlenme</span>{!cur && <IconCheck className="text-primary size-5" />}
            </button>
          </Card>
          <SectionTitle>Hazır antrenmanlar</SectionTitle>
          <p className="text-muted-foreground -mt-2 text-sm">Seçtiğin gün kayıtlı antrenmanlarına eklenir ve bu güne atanır.</p>
          {defaults.map(({ t, list }) => (
            <div key={t.key} className="grid gap-1.5">
              <div className="text-muted-foreground text-xs font-medium">{t.name}</div>
              <Card className="divide-y">
                {list.map((p, i) => (
                  <button key={i} className="flex w-full items-center justify-between px-4 py-3 text-left active:bg-accent" onClick={() => pickDefault(p, close)}>
                    <span><span className="font-medium">{p.name}</span><span className="text-muted-foreground block text-xs">{allEx(p).length} hareket</span></span>
                    <IconPlus className="text-muted-foreground size-4" />
                  </button>
                ))}
              </Card>
            </div>
          ))}
        </>
      )}
    </Sheet>
  )
}

/* ---------- Çoklu seçimle hareket ekleme ---------- */
function library(db) {
  const map = new Map()
  const put = (e, mine) => { const k = norm(e.name); if (!map.has(k) || mine) map.set(k, { name: e.name, muscle: e.muscle || map.get(k)?.muscle || 'Diğer', unit: e.unit, sets: e.sets, reps: e.reps, rest: e.rest, desc: e.desc || '', note: e.note || '', video: e.video || '', mine: mine || map.get(k)?.mine }) }
  EXERCISES.forEach((e) => put(e, false))
  ;(db.customExercises || []).forEach((e) => put(e, true))
  db.programs.filter((p) => !p.archived).forEach((p) => allEx(p).forEach((e) => { put(e, true); const x = map.get(norm(e.name)); x.progs = [...new Set([...(x.progs || []), p.temp ? 'Bu gün' : p.name])] }))
  return [...map.values()]
}

export function ExercisePicker({ onClose, pid, bid, newFor }) {
  const { withUndo, toast, db, update, open } = useApp()
  const lib = React.useMemo(() => library(db), [db])
  const [q, setQ] = React.useState('')
  const [group, setGroup] = React.useState('all')
  const [sel, setSel] = React.useState([])
  const [superset, setSuperset] = React.useState(false)
  const [custom, setCustom] = React.useState(false)
  const [d, setD] = React.useState({ sets: 3, reps: 12, kg: '', rest: 60 })
  const nq = norm(q)
  const words = nq.split(' ').filter(Boolean)
  const hay = React.useMemo(() => new Map(lib.map((e) => [e.name, norm(searchText(e.name) + ' ' + e.muscle)])), [lib])
  const list = lib.filter((e) => (group === 'all' || (group === 'mine' ? e.mine : e.muscle === group)) && (!words.length || words.every((w) => hay.get(e.name).includes(w))))
  const toggle = (name) => { haptic(); setSel((s) => (s.includes(name) ? s.filter((x) => x !== name) : [...s, name])) }
  const target = React.useMemo(() => pid || uid(), [pid])
  const add = (close) => {
    const picked = sel.map((n) => lib.find((e) => e.name === n)).filter(Boolean).map((e) => ({
      id: uid(), name: e.name, muscle: e.muscle === 'Diğer' ? '' : e.muscle, unit: e.unit, desc: e.desc, note: e.note, video: e.video,
      sets: custom && num(d.sets) ? clamp(d.sets, 1, 20) : e.sets, reps: custom && e.unit === 'tekrar' && num(d.reps) ? clamp(d.reps, 1, 999) : e.reps, rest: custom ? clamp(d.rest, 0, 900) : e.rest,
      ...(custom && e.unit === 'tekrar' && num(d.kg) > 0 ? { kg: Math.min(999, num(d.kg)) } : {}),
    }))
    if (!picked.length) return
    withUndo(`${picked.length} hareket eklendi`, (x) => {
      // Kendi planını oluştur: program ancak hareket eklenince oluşur ve güne atanır
      if (newFor) { const rep = newFor.repeat && newFor.date >= todayKey(); x.programs.push({ id: target, name: newFor.name || `${DAYS_LONG[dowOf(newFor.date)]} antrenmanı`, blocks: [], ...(rep ? {} : { temp: true }) }); assignDay(x, newFor.date, target, rep) }
      else freezePast(x, pid)
      const p = x.programs.find((y) => y.id === target); if (!p) return
      const B = bid && p.blocks.find((b) => b.id === bid)
      if (B) B.exs.push(...picked.map((e) => ({ ...e, sets: Math.max(1, B.rounds || 1) })))
      else if (superset && picked.length > 1) { const rounds = Math.max(...picked.map((e) => e.sets)); p.blocks.push({ id: uid(), kind: 'superset', tag: null, rounds, rest: picked.at(-1).rest || 60, note: '', exs: picked.map((e) => ({ ...e, sets: rounds, rest: 0 })) }) }
      else picked.forEach((e) => p.blocks.push({ id: uid(), kind: 'single', ex: e }))
    }, 'add')
    haptic(); close()
  }
  return (
    <Sheet onClose={onClose} title={bid ? "Süperset'e hareket ekle" : 'Hareket ekle'} description="Birden fazla seçebilirsin; seçim sırasıyla eklenir." full
      footer={(close) => (
        <>
          {sel.length > 0 && (
            <div className="grid gap-2">
              {!bid && sel.length > 1 && (
                <button className="flex items-center gap-2.5 text-left text-sm" onClick={() => setSuperset(!superset)}><Checkbox checked={superset} />Süperset olarak ekle</button>
              )}
              <button className="flex items-center gap-2.5 text-left text-sm" onClick={() => setCustom(!custom)}><Checkbox checked={custom} />Set, tekrar ve kiloyu kendim gireyim</button>
              {custom && (
                <div className="grid grid-cols-4 gap-2">
                  {[['sets', 'Set'], ['reps', 'Tekrar'], ['kg', 'Kilo'], ['rest', 'Dinl. (sn)']].map(([k, l]) => (
                    <div key={k} className="grid gap-1"><span className="text-muted-foreground text-xs">{l}</span><Input className="h-11" inputMode={k === 'kg' ? 'decimal' : 'numeric'} placeholder={k === 'kg' ? '–' : undefined} value={d[k]} onChange={(e) => setD({ ...d, [k]: e.target.value.replace(k === 'kg' ? /[^\d.,]/g : /\D/g, '') })} aria-label={l} /></div>
                  ))}
                </div>
              )}
            </div>
          )}
          <Button size="lg" onClick={() => add(close)} disabled={!sel.length}>
            <IconPlus />{sel.length ? `${sel.length} hareketi ${superset && !bid && sel.length > 1 ? 'süperset olarak ' : ''}ekle` : 'Hareket seç'}
          </Button>
        </>
      )}>
      {(close) => (
        <>
          <div className="relative">
            <IconSearch className="text-muted-foreground absolute left-3 top-1/2 size-4 -translate-y-1/2" />
            <Input className="pl-9" placeholder="Hareket ara (Türkçe ya da İngilizce)" value={q} onChange={(e) => setQ(e.target.value)} />
          </div>
          <div className="no-scrollbar -mx-[max(16px,env(safe-area-inset-left,0px))] flex gap-1.5 overflow-x-auto px-gutter">
            {[['all', 'Tümü'], ['mine', 'Programlarımda'], ...MUSCLES.map((m) => [m, m])].map(([v, l]) => (
              <Button key={v} size="sm" variant={group === v ? 'default' : 'outline'} onClick={() => setGroup(v)}>{l}</Button>
            ))}
          </div>
          <Card className="divide-y">
            {list.map((e) => {
              const i = sel.indexOf(e.name)
              return (
                <button key={e.name} className={cn('flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent', i >= 0 && 'bg-primary/5')} onClick={() => toggle(e.name)}>
                  {i >= 0 ? <span className="bg-primary text-primary-foreground grid size-5 shrink-0 place-items-center rounded-[4px] text-[11px] font-semibold tabular">{i + 1}</span> : <Checkbox checked={false} />}
                  <ExerciseThumb name={e.name} className="size-16" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium">{e.name}</div>
                    {trName(e.name) && <div className="text-muted-foreground truncate text-xs">{trName(e.name)}</div>}
                    <div className="text-muted-foreground text-xs tabular">{e.muscle} · {e.sets} set · {e.reps} {e.unit}</div>
                  </div>
                  {e.mine && <Badge variant="outline" className="max-w-28 truncate">{e.progs?.length ? (e.progs.length > 1 ? `${e.progs[0]} +${e.progs.length - 1}` : e.progs[0]) : 'Özel'}</Badge>}
                </button>
              )
            })}
            {list.length === 0 && <div className="text-muted-foreground px-4 py-3 text-sm">Bu filtrede hareket yok.</div>}
          </Card>
          {!newFor && q.trim() && !lib.some((e) => norm(e.name) === nq) && (
            <Button variant="outline" onClick={() => { close(); open('exForm', { pid, bid, preset: q.trim() }) }}><IconPlus />“{q.trim()}” adında yeni hareket oluştur</Button>
          )}
          {!newFor && !q.trim() && <Button variant="ghost" onClick={() => { close(); open('exForm', { pid, bid }) }}>Listede yok mu? Yeni hareket oluştur</Button>}
        </>
      )}
    </Sheet>
  )
}
