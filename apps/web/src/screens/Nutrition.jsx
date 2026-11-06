import * as React from 'react'
import {
  IconPencil, IconCheck, IconPlus, IconTrash, IconSearch, IconBarcode, IconChevronLeft, IconChevronRight,
  IconWorld, IconPhoto, IconChefHat, IconToolsKitchen2, IconWriting, IconLoader2, IconCamera, IconX, IconCopy, IconBookmark,
  IconTemplate, IconShare2, IconFileImport, IconTag,
} from '@tabler/icons-react'
import { get as idbGet, set as idbSet } from 'idb-keyval'
import { Button, Card, Badge, Sheet, Input, Textarea, Field, Segmented, NativeSelect, Empty, SectionTitle } from '@/components/ui'
import { Header, MacroRow, Stepper, Ring, AnimatedNumber } from '@/components/common'
import { useApp, nutrition, dayLog, recipeTotals, saveImage, useImage, deleteImage, MEALS, mealsOf, defaultMeal, recentFoods, entryFrom, entriesOf } from '@/lib/store'
import { searchLocal, searchOnline, lookupBarcode, macrosFor, splitText, parseLine, resolveLine, gramsFor } from '@/lib/search'
import { DAYS, DAYS_LONG, fmt, fmt1, num, uid, cn, haptic, todayKey, keyOf, longDate, shortDate, dowOf, norm } from '@/lib/utils'

// Silinen varlığı kapanış animasyonu boyunca göstermek için son değeri tutar; dışarıda silinirse sheet'i kapatır
function useLast(x, onClose) {
  const last = React.useRef(x)
  const closing = React.useRef(false)
  if (x) last.current = x
  React.useEffect(() => { if (!x && !closing.current) onClose?.() }, [x]) // eslint-disable-line
  return [x || last.current, closing]
}
const pos = (v) => { const n = num(v); return n > 0 ? n : 0 }
const MAX_G = 10000
const okG = (g) => g > 0 && g <= MAX_G
const sameName = (a, b) => String(a || '').trim().toLocaleLowerCase('tr') === String(b || '').trim().toLocaleLowerCase('tr')

const shift = (key, n) => { const [y, m, d] = key.split('-').map(Number); return keyOf(new Date(y, m - 1, d + n)) }
const dayName = (key) => key === todayKey() ? 'Bugün' : key === shift(todayKey(), -1) ? 'Dün' : DAYS_LONG[dowOf(key)]

export default function Nutrition() {
  const [view, setView] = React.useState('day')
  const [date, setDate] = React.useState(todayKey())
  return (
    <div className="grid gap-4">
      <Header eyebrow="Beslenme" title={view === 'day' ? 'Günlük' : view === 'foods' ? 'Besinlerim' : 'Tarif defteri'} />
      <Segmented value={view} onChange={setView} options={[['day', 'Günlük'], ['foods', 'Besinlerim'], ['recipes', 'Tarifler']]} />
      <div key={view} className="screen-enter grid gap-4">
        {view === 'day' ? <Diary date={date} setDate={setDate} /> : view === 'foods' ? <MyFoods /> : <Recipes />}
      </div>
    </div>
  )
}

/* ================= Günlük (yediklerin) ================= */
export function NutritionSummary({ N, T, compact }) {
  const left = T.kcal - N.eat.kcal
  return (
    <div className="grid gap-4">
      <div className="flex items-center gap-4">
        {!compact && <Ring value={N.eat.kcal / (T.kcal || 1)} size={72} stroke={6}>
          <div className="text-center leading-none"><div className="text-base font-semibold tabular"><AnimatedNumber value={N.eat.kcal} /></div><div className="text-muted-foreground mt-0.5 text-[10px]">kcal</div></div>
        </Ring>}
        <div className="min-w-0">
          <div className={cn('text-2xl font-semibold tracking-tight tabular', left < 0 && 'text-destructive')}><AnimatedNumber value={Math.abs(left)} /> kcal</div>
          <div className="text-muted-foreground text-sm">{left >= 0 ? 'kaldı' : 'hedefin üstünde'} · hedef {fmt(T.kcal)}</div>
        </div>
      </div>
      <MacroRow eat={N.eat} plan={T} />
    </div>
  )
}

function Diary({ date, setDate }) {
  const { withUndo, db, open } = useApp()
  const N = nutrition(db, date)
  const yest = nutrition(db, shift(date, -1))
  const copyMeal = (k) => { haptic(); withUndo('Dünkü öğün eklendi', (d) => { const E = (dayLog(d, date).entries ??= []); yest.byMeal[k].forEach((e) => E.push({ ...e, id: uid(), meal: k })) }, 'add') }
  const [tplFor, setTplFor] = React.useState(null) // { meal, label, items }
  return (
    <>
      <div className="flex items-center justify-between gap-2">
        <Button variant="outline" size="icon" className="size-11" onClick={() => setDate(shift(date, -1))} aria-label="Önceki gün"><IconChevronLeft /></Button>
        <button className="text-center" onClick={() => setDate(todayKey())}>
          <div className="font-semibold">{dayName(date)}</div><div className="text-muted-foreground text-xs">{longDate(date)}</div>
        </button>
        <Button variant="outline" size="icon" className="size-11" onClick={() => setDate(shift(date, 1))} disabled={date >= todayKey()} aria-label="Sonraki gün"><IconChevronRight /></Button>
      </div>

      <Card className="p-4"><NutritionSummary N={N} T={db.targets} /></Card>

      <WeeklyTrend date={date} setDate={setDate} />

      <div className="grid grid-cols-2 gap-2">
        <Button onClick={() => open('addFood', { target: { type: 'log', date } })}><IconPlus />Yediğini ekle</Button>
        <Button variant="outline" onClick={() => open('cheat', { date })}><IconWriting />Yazarak gir</Button>
      </div>

      {MEALS.filter(([k]) => mealsOf(db).some((m) => m[0] === k) || N.byMeal[k].length).map(([k, label]) => {
        const list = N.byMeal[k]
        const sum = list.reduce((a, e) => { a.kcal += e.kcal; a.p += e.p; return a }, { kcal: 0, p: 0 })
        return (
          <Card key={k} className="overflow-hidden">
            <div className={cn('flex items-center justify-between gap-2 pl-4 pr-1.5', list.length || yest.byMeal[k].length ? 'pt-1.5 pb-1' : 'py-1.5')}>
              <div className="min-w-0"><h3 className="font-semibold">{label}</h3><div className="text-muted-foreground text-xs tabular">{list.length > 0 ? `${fmt(sum.kcal)} kcal · P ${fmt(sum.p)} g` : 'Boş'}</div></div>
              <div className="flex shrink-0 items-center">
                {list.length > 0 && <Button variant="ghost" size="icon" className="text-muted-foreground size-11" onClick={() => setTplFor({ meal: k, label, items: list })} aria-label={`${label.replace(' öğün', '')} öğününü şablon olarak kaydet`}><IconTemplate /></Button>}
                <Button variant="ghost" size="icon" className="size-11" onClick={() => open('addFood', { target: { type: 'log', date, meal: k } })} aria-label={`${label.replace(' öğün', '')} öğününe ekle`}><IconPlus /></Button>
              </div>
            </div>
            {list.length > 0 ? (
              <div className="divide-y border-t">
                {list.map((e) => (
                  <button key={e.id} className="flex w-full items-center gap-3 px-4 py-2.5 text-left active:bg-accent" onClick={() => open('entry', { date, id: e.id })}>
                    <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{e.name}</div><div className="text-muted-foreground text-xs tabular">P {fmt1(e.p)} · K {fmt1(e.c)} · Y {fmt1(e.f)} g</div></div>
                    <span className="text-sm tabular">{fmt(e.kcal)}<span className="text-muted-foreground text-xs"> kcal</span></span>
                  </button>
                ))}
              </div>
            ) : yest.byMeal[k].length > 0 ? (
              <div className="px-4 pb-3"><Button variant="secondary" size="sm" onClick={() => copyMeal(k)}><IconCopy />Dünkünü ekle · {fmt(yest.byMeal[k].reduce((a, e) => a + e.kcal, 0))} kcal</Button></div>
            ) : null}
          </Card>
        )
      })}
      {tplFor && <SaveTemplateSheet {...tplFor} onClose={() => setTplFor(null)} />}
    </>
  )
}

/* ---- Haftalık / aylık trend: günlükte tek satır, ayrıntı sheet'te ---- */
function useTrend(range) {
  const { db } = useApp()
  const T = db.targets
  return React.useMemo(() => {
    const today = todayKey()
    const days = Array.from({ length: range }, (_, i) => shift(today, i - range + 1))
    const rows = days.map((k) => { const n = nutrition(db, k); return { k, kcal: n.eat.kcal, p: n.eat.p, logged: n.entries.length > 0 } })
    const logged = rows.filter((r) => r.logged)
    const avg = logged.length ? logged.reduce((a, r) => a + r.kcal, 0) / logged.length : 0
    const pOk = logged.filter((r) => r.p >= 0.9 * (T.p || 0)).length
    const w = db.measures.filter((m) => m.kg > 0 && m.date >= days[0] && m.date <= today).sort((a, b) => (a.date < b.date ? -1 : 1))
    return { rows, logged: logged.length, avg, pOk, pPct: logged.length ? pOk / logged.length : 0, w }
  }, [db, range, T.p])
}
function WeeklyTrend({ date, setDate }) {
  const { db } = useApp()
  const [open, setOpen] = React.useState(false)
  const data = useTrend(7)
  const T = db.targets
  const max = Math.max(T.kcal * 1.25, ...data.rows.map((r) => r.kcal), 1)
  return (
    <>
      <button onClick={() => setOpen(true)} className="press bg-card text-card-foreground flex min-h-14 w-full items-center gap-3 rounded-lg border px-4 py-3 text-left dark:border-transparent" aria-label="Son 7 günün ayrıntısını aç">
        <div className="min-w-0 flex-1">
          <div className="text-sm font-semibold">Son 7 gün</div>
          <div className="text-muted-foreground truncate text-xs tabular">{data.logged ? `ort. ${fmt(data.avg)} kcal · protein ${data.pOk}/${data.logged}` : 'Henüz kayıt yok'}</div>
        </div>
        <div className="flex h-8 shrink-0 items-end gap-[3px]" aria-hidden>
          {data.rows.map((r) => <span key={r.k} className={cn('w-[5px] rounded-full', !r.logged ? 'bg-foreground/15' : r.kcal > T.kcal * 1.1 ? 'bg-destructive/60' : r.k === date ? 'bg-primary' : 'bg-primary/45')} style={{ height: r.logged ? `${Math.max(14, Math.min(100, (r.kcal / max) * 100))}%` : '14%' }} />)}
        </div>
        <IconChevronRight className="text-muted-foreground -ml-1 size-5 shrink-0" />
      </button>
      {open && (
        <Sheet onClose={() => setOpen(false)} title="Beslenme trendi" description="Bir güne dokun, o günün kaydına git.">
          {(close) => <TrendBody date={date} onPick={(k) => { setDate(k); close() }} />}
        </Sheet>
      )}
    </>
  )
}
function TrendBody({ date, onPick }) {
  const { db } = useApp()
  const [range, setRange] = React.useState(7)
  const T = db.targets
  const data = useTrend(range)
  const setDate = onPick
  const max = Math.max(T.kcal * 1.25, ...data.rows.map((r) => r.kcal), 1)
  const tgtPct = (T.kcal / max) * 100
  const wd = data.w.length > 1 ? data.w.at(-1).kg - data.w[0].kg : null
  return (
    <div className="grid gap-4">
      <Segmented value={range} onChange={setRange} options={[[7, 'Son 7 gün'], [30, 'Son 30 gün']]} />
      <div className="grid grid-cols-3 gap-2 text-center tabular">
        <div><div className="text-muted-foreground text-xs">Ort. kalori</div><div className="text-base font-semibold">{data.logged ? fmt(data.avg) : '–'}</div></div>
        <div><div className="text-muted-foreground text-xs">Protein hedefi</div><div className="text-base font-semibold">{data.logged ? `%${fmt(data.pPct * 100)}` : '–'}</div></div>
        <div><div className="text-muted-foreground text-xs">Kayıtlı gün</div><div className="text-base font-semibold">{data.logged}/{range}</div></div>
      </div>
      <div className="relative h-36" role="group" aria-label="Günlük kalori grafiği">
        <div className="border-foreground/30 pointer-events-none absolute inset-x-0 border-t border-dashed" style={{ bottom: `${tgtPct}%` }} aria-hidden />
        <div className={cn('flex h-full items-end', range === 7 ? 'gap-2' : 'gap-[2px]')}>
          {data.rows.map((r) => {
            const sel = r.k === date, over = r.kcal > T.kcal * 1.1
            return (
              <button key={r.k} onClick={() => setDate(r.k)} aria-label={`${shortDate(r.k)}: ${fmt(r.kcal)} kcal`} aria-pressed={sel}
                className="group relative flex h-full min-w-0 flex-1 items-end justify-center">
                <span className={cn('block w-full rounded-t-[5px] transition-[height] duration-500', range === 7 ? 'max-w-7' : '', !r.logged ? 'bg-foreground/10' : over ? (sel ? 'bg-destructive' : 'bg-destructive/40') : sel ? 'bg-primary' : 'bg-primary/35')}
                  style={{ height: r.logged ? `${Math.max(4, (r.kcal / max) * 100)}%` : '4px' }} />
                {sel && <span className="bg-foreground absolute -bottom-1.5 size-1 rounded-full" aria-hidden />}
              </button>
            )
          })}
        </div>
      </div>
      {range === 7 && <div className="text-muted-foreground -mt-1 flex text-center text-[11px]">{data.rows.map((r) => <span key={r.k} className={cn('flex-1', r.k === date && 'text-foreground font-semibold')}>{DAYS[dowOf(r.k)]}</span>)}</div>}
      <div className="text-muted-foreground flex items-center justify-between gap-2 text-xs">
        <span className="flex items-center gap-1.5"><span className="border-foreground/40 inline-block w-4 border-t border-dashed" />Hedef {fmt(T.kcal)} kcal</span>
        {wd != null && (
          <span className="flex items-center gap-1.5 tabular">
            <Spark pts={data.w.map((m) => m.kg)} />Kilo {wd > 0 ? '+' : wd < 0 ? '−' : ''}{fmt1(Math.abs(wd))} kg
          </span>
        )}
      </div>
    </div>
  )
}
function Spark({ pts }) {
  const mn = Math.min(...pts), mx = Math.max(...pts), W = 36, H = 14
  const d = pts.map((v, i) => `${(i / (pts.length - 1)) * W},${mx === mn ? H / 2 : H - ((v - mn) / (mx - mn)) * H}`).join(' ')
  return <svg width={W} height={H} viewBox={`-1 -1 ${W + 2} ${H + 2}`} aria-hidden><polyline points={d} fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" /></svg>
}

/* ---- Öğün şablonları ---- */
const snapItem = ({ id, meal, ...e }) => ({ ...e, id: uid() })
function SaveTemplateSheet({ meal, label, items, onClose }) {
  const { toast, update } = useApp()
  const [name, setName] = React.useState(`${label.replace(' öğün', '')} · ${items.length} besin`)
  const kcal = items.reduce((a, e) => a + (+e.kcal || 0), 0)
  const save = (close) => {
    if (!name.trim()) return
    update((d) => { (d.mealTemplates ??= []).unshift({ id: uid(), name: name.trim(), meal, items: items.map(snapItem) }) })
    haptic(); toast('Şablon kaydedildi'); close()
  }
  return (
    <Sheet onClose={onClose} title="Şablon olarak kaydet" description={`${items.length} besin · ${fmt(kcal)} kcal`} footer={(close) => <Button size="lg" onClick={() => save(close)} disabled={!name.trim()}><IconTemplate />Kaydet</Button>}>
      {(close) => (
        <form onSubmit={(e) => { e.preventDefault(); save(close) }}>
          <Field label="Şablon adı" id="tpl-n"><Input id="tpl-n" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></Field>
          <ul className="text-muted-foreground mt-3 grid gap-1 text-sm">{items.map((e) => <li key={e.id} className="truncate">· {e.name}</li>)}</ul>
        </form>
      )}
    </Sheet>
  )
}
// Yeni şablon: boş açılır, içine besin ya da tarif eklenir; boş kapatılırsa silinir
export const newTemplate = (update, open, meal) => { const id = uid(); update((d) => { (d.mealTemplates ??= []).unshift({ id, name: 'Yeni şablon', meal, items: [] }) }); open('tplForm', { id, isNew: true }) }
const tplThumb = (t) => t.items.find((e) => e.image)?.image || null
function Templates({ meal, setMeal, date, onDone }) {
  const { withUndo, db, update, open } = useApp()
  const list = (db.mealTemplates ?? []).filter((t) => t.items.length)
  const add = (t) => {
    haptic()
    withUndo(`${t.name} eklendi`, (d) => { const E = (dayLog(d, date).entries ??= []); t.items.forEach((e) => E.push({ ...e, id: uid(), meal })) }, 'add')
    onDone()
  }
  const del = (t) => withUndo(`${t.name} silindi`, (d) => { const i = (d.mealTemplates ?? []).findIndex((x) => x.id === t.id); if (i >= 0) d.mealTemplates.splice(i, 1) })
  const create = <Button variant="outline" onClick={() => newTemplate(update, open, meal)}><IconPlus />Yeni şablon</Button>
  if (!list.length) return <Empty icon={IconTemplate} title="Henüz şablon yok" action={create}>Besin ve tariflerden bir şablon oluştur ya da günlükteki öğün kartından kaydet; tek dokunuşla eklersin.</Empty>
  return (
    <>
      <MealField value={meal} onChange={setMeal} />
      <Card className="divide-y">
        {list.map((t) => {
          const kcal = t.items.reduce((a, e) => a + (+e.kcal || 0), 0), p = t.items.reduce((a, e) => a + (+e.p || 0), 0)
          const img = tplThumb(t)
          return (
            <div key={t.id} className="flex items-center gap-1 pl-3 pr-1">
              <button className="flex min-h-14 min-w-0 flex-1 items-center gap-3 py-2 text-left active:opacity-70" onClick={() => add(t)}>
                <Thumb id={imgId({ image: img })} url={imgUrl({ image: img })} />
                <span className="flex min-w-0 flex-col"><span className="truncate text-sm font-medium">{t.name}</span>
                <span className="text-muted-foreground truncate text-xs tabular">{t.items.length} kalem · {fmt(kcal)} kcal · P {fmt(p)} g</span></span>
              </button>
              <Button variant="ghost" size="icon" className="text-muted-foreground size-11" onClick={() => open('tplForm', { id: t.id })} aria-label={`${t.name} şablonunu düzenle`}><IconPencil /></Button>
              <Button variant="ghost" size="icon" className="text-muted-foreground size-11" onClick={() => del(t)} aria-label={`${t.name} şablonunu sil`}><IconTrash /></Button>
            </div>
          )
        })}
      </Card>
      {create}
    </>
  )
}

/* Şablon düzenleyici: ad, öğün, içindekiler (besin ya da görselli tarif) */
export function TemplateForm({ onClose, id, isNew }) {
  const { withUndo, db, update, open } = useApp()
  const [t, closing] = useLast((db.mealTemplates ?? []).find((x) => x.id === id), onClose)
  if (!t) return null
  const set = (k, v) => update((d) => { const x = d.mealTemplates?.find((y) => y.id === id); if (x) x[k] = v })
  const dropIfEmpty = () => { if (!t.items.length) update((d) => { const i = (d.mealTemplates ?? []).findIndex((x) => x.id === id); if (i >= 0) d.mealTemplates.splice(i, 1) }) }
  const close2 = () => { if (!closing.current) { if (isNew) dropIfEmpty(); else if (!t.name.trim()) set('name', 'Şablon') } onClose() }
  const kcal = t.items.reduce((a, e) => a + (+e.kcal || 0), 0), p = t.items.reduce((a, e) => a + (+e.p || 0), 0)
  const delItem = (i) => update((d) => { const x = d.mealTemplates?.find((y) => y.id === id); if (x && i < x.items.length) x.items.splice(i, 1) })
  return (
    <Sheet onClose={close2} title={isNew ? 'Yeni şablon' : 'Şablonu düzenle'} description={`${t.items.length} kalem · ${fmt(kcal)} kcal · P ${fmt(p)} g`} full footer={(close) => <>
      <Button size="lg" onClick={close}><IconCheck />Bitti</Button>
      {!isNew && <Button variant="ghost" className="text-destructive" onClick={() => { closing.current = true; withUndo(`${t.name} silindi`, (d) => { const i = (d.mealTemplates ?? []).findIndex((x) => x.id === id); if (i >= 0) d.mealTemplates.splice(i, 1) }); close() }}>Şablonu sil</Button>}
    </>}>
      <Field label="Şablon adı" id="tf-n"><Input id="tf-n" value={t.name} onChange={(e) => set('name', e.target.value)} onFocus={(e) => isNew && t.name === 'Yeni şablon' && e.target.select()} maxLength={60} /></Field>
      <MealField value={t.meal || defaultMeal(db)} onChange={(v) => v !== t.meal && set('meal', v)} />
      <SectionTitle action={<Button variant="ghost" size="sm" onClick={() => open('addFood', { target: { type: 'template', tid: id } })}><IconPlus />Ekle</Button>}>İçindekiler</SectionTitle>
      <Card className="divide-y">
        {t.items.map((e, i) => (
          <div key={e.id || i} className="flex items-center gap-3 py-1.5 pl-3 pr-1">
            <Thumb id={imgId(e)} url={imgUrl(e)} />
            <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{e.name}</div><div className="text-muted-foreground text-xs tabular">{fmt(e.kcal)} kcal · P {fmt1(e.p)} · K {fmt1(e.c)} · Y {fmt1(e.f)} g</div></div>
            <Button variant="ghost" size="icon" className="text-muted-foreground size-11" onClick={() => delItem(i)} aria-label={`${e.name} kaldır`}><IconTrash /></Button>
          </div>
        ))}
        {!t.items.length && <button className="text-muted-foreground w-full px-4 py-3 text-left text-sm" onClick={() => open('addFood', { target: { type: 'template', tid: id } })}>Besin ya da tarif ekle. Tarifler görselleriyle eklenir.</button>}
      </Card>
    </Sheet>
  )
}

export function EntrySheet({ onClose, date, id }) {
  const { withUndo, toast, db, update } = useApp()
  const live = entriesOf(db, date).find((x) => x.id === id)
  const [e, closing] = useLast(live, onClose)
  const [g, setG] = React.useState(e?.g != null ? String(Math.round(e.g * 10) / 10).replace('.', ',') : '')
  const [meal, setMeal] = React.useState(e?.meal || 'ara')
  if (!e) return null
  const gv = num(g)
  const gOk = !e.per100 || okG(gv)
  const x = e.per100 ? macrosFor(e.per100, gOk ? gv : 0) : e
  const save = (close) => {
    if (!gOk) return
    update((d) => {
      const L = dayLog(d, date)
      const t = (L.entries || []).find((y) => y.id === id) || (L.extras || []).find((y) => y.id === id)
      if (!t) return
      t.meal = meal
      if (e.per100 && gv !== e.g) { Object.assign(t, macrosFor(e.per100, gv), { g: gv, name: `${fmt1(gv)} g ${e.foodName || e.name}` }) }
    })
    closing.current = true; close()
  }
  const remove = (close) => {
    closing.current = true
    withUndo(`${e.foodName || e.name} silindi`, (d) => {
      const L = dayLog(d, date)
      for (const k of ['entries', 'extras']) { const i = (L[k] || []).findIndex((y) => y.id === id); if (i >= 0) L[k].splice(i, 1) }
    })
    close()
  }
  const saved = db.myFoods.some((f) => sameName(f.name, e.foodName || e.name))
  return (
    <Sheet onClose={onClose} title={e.foodName || e.name} footer={(close) => <>
      <Button size="lg" onClick={() => save(close)} disabled={!gOk}>Kaydet</Button>
      <Button variant="ghost" className="text-destructive" onClick={() => remove(close)}><IconTrash />Sil</Button>
    </>}>
      <MealField value={meal} onChange={setMeal} />
      {e.per100 && <Field label="Gram" id="en-g" hint={!gOk ? `0'dan büyük, en fazla ${fmt(MAX_G)} g olmalı.` : undefined}><Input id="en-g" inputMode="decimal" value={g} aria-invalid={!gOk} onChange={(ev) => setG(ev.target.value.replace(/[^\d.,]/g, ''))} /></Field>}
      <div className="bg-muted grid grid-cols-4 gap-2 p-3 text-center text-xs rounded-md tabular">
        {[['kcal', x.kcal], ['Protein', x.p], ['Karb.', x.c], ['Yağ', x.f]].map(([l, v]) => <div key={l}><div className="text-muted-foreground">{l}</div><div className="mt-0.5 text-base font-semibold">{fmt1(v)}</div></div>)}
      </div>
      {e.per100 && !saved && (
        <Button variant="outline" onClick={() => { update((d) => { if (!d.myFoods.some((f) => sameName(f.name, e.foodName || e.name))) d.myFoods.unshift({ id: uid(), name: e.foodName || e.name, per100: e.per100, portions: e.portions || {}, image: e.image || null, source: 'mine' }) }); toast('Besinlerime kaydedildi') }}><IconBookmark />Besinlerime kaydet</Button>
      )}
    </Sheet>
  )
}

/* ================= Besin ekleme (arama · internet · barkod) ================= */
function Thumb({ id, url, className }) {
  const local = useImage(id)
  const src = local || url
  return src ? <img src={src} alt="" className={cn('size-10 shrink-0 object-cover rounded-md', className)} /> : <div className={cn('bg-muted grid size-10 shrink-0 place-items-center rounded-md', className)}><IconToolsKitchen2 className="text-muted-foreground size-4" stroke={1.5} /></div>
}
const imgId = (f) => (f.image?.startsWith?.('img-') ? f.image : null)
const imgUrl = (f) => (f.image?.startsWith?.('http') ? f.image : null)

// Tarif, porsiyon birimli bir besin gibi eklenir (görseliyle)
export function recipeFood(r) {
  const t = recipeTotals(r)
  if (!(t.grams > 0) || !r.items.length) return null
  const k = 100 / t.grams
  return { id: 'rc-' + r.id, name: r.name || 'Adsız tarif', per100: { kcal: t.total.kcal * k, p: t.total.p * k, c: t.total.c * k, f: t.total.f * k }, portions: { porsiyon: t.grams / Math.max(1, r.servings || 1) }, image: r.image || null, source: 'recipe' }
}
function RecipePick({ onPick }) {
  const { db } = useApp()
  const list = db.recipes.map((r) => [r, recipeFood(r)]).filter(([, f]) => f)
  if (!list.length) return <Empty icon={IconChefHat} title="Eklenebilir tarif yok">Tarifler sekmesinde malzemeleriyle bir tarif oluştur; görseliyle birlikte buradan eklersin.</Empty>
  return (
    <Card className="divide-y">
      {list.map(([r, f]) => (
        <button key={r.id} className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent" onClick={() => onPick(f)}>
          <Thumb id={imgId(r)} url={imgUrl(r)} className="size-14" />
          <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{f.name}</div><div className="text-muted-foreground text-xs tabular">1 porsiyon · {fmt(macrosFor(f.per100, f.portions.porsiyon).kcal)} kcal · P {fmt1(macrosFor(f.per100, f.portions.porsiyon).p)}</div></div>
          <IconChevronRight className="text-muted-foreground size-4 shrink-0" />
        </button>
      ))}
    </Card>
  )
}

function applyPick(d, target, food, g, label, meal) {
  if (target.type === 'log') (dayLog(d, target.date).entries ??= []).push(entryFrom(food, g, meal, label))
  else if (target.type === 'recipe') d.recipes.find((r) => r.id === target.rid).items.push({ id: uid(), name: food.name, g, per100: food.per100 })
  else if (target.type === 'template') d.mealTemplates?.find((t) => t.id === target.tid)?.items.push(snapItem(entryFrom(food, g, null, label)))
  if (food.source === 'off' && !d.myFoods.some((f) => f.id === food.id || sameName(f.name, food.name))) d.myFoods.unshift({ ...food, source: 'mine' })
}

export function AddFoodSheet({ onClose, target }) {
  const { withUndo, toast, db, update } = useApp()
  const [mode, setMode] = React.useState('search')
  const [q, setQ] = React.useState('')
  const [online, setOnline] = React.useState({ state: 'idle', items: [] })
  const [pick, setPick] = React.useState(null)
  const [label, setLabel] = React.useState(null) // barkod bulunamadı → etiketten kaydet
  const [meal, setMeal] = React.useState(target.meal || defaultMeal(db))
  const recent = React.useMemo(() => recentFoods(db), [db])
  const local = q.trim() ? searchLocal(q, db.myFoods) : db.myFoods
  const req = React.useRef(null)
  React.useEffect(() => () => req.current?.abort(), [])
  const goOnline = async () => {
    req.current?.abort()
    const ac = new AbortController(); req.current = ac
    const term = q.trim()
    setOnline({ state: 'loading', items: [], q: term })
    try {
      const items = await searchOnline(term, ac.signal)
      if (req.current === ac) setOnline({ state: 'done', items, q: term })
    } catch (e) { if (req.current === ac && !ac.signal.aborted) setOnline({ state: 'error', items: [], msg: e.message, q: term }) }
  }
  const title = target.type === 'recipe' ? 'Malzeme ekle' : target.type === 'myfood' ? 'Besinlerime ekle' : target.type === 'template' ? 'Şablona ekle' : 'Yediğini ekle'
  return (
    <Sheet onClose={onClose} title={pick ? pick.name : label != null ? 'Etiketten kaydet' : title} full>
      {(close) => label != null && !pick ? (
        <LabelForm code={label} onBack={() => setLabel(null)} onSaved={(food) => {
          if (target.type === 'myfood') { toast('Besinlerime kaydedildi'); haptic(); close() } else { setLabel(null); setPick(food) }
        }} />
      ) : pick ? (
        <Amount food={pick} target={target} meal={meal} setMeal={setMeal} onBack={() => setPick(null)} onDone={(g, label) => {
          if (target.type === 'myfood') {
            const exists = db.myFoods.some((f) => f.id === pick.id || sameName(f.name, pick.name))
            if (!exists) update((d) => { d.myFoods.unshift({ ...pick, id: pick.source === 'off' ? pick.id : uid(), source: 'mine', mine: undefined, lastG: undefined }) })
            toast(exists ? 'Zaten Besinlerim’de' : 'Besinlerime kaydedildi')
          } else withUndo(target.type === 'recipe' ? 'Malzeme eklendi' : target.type === 'template' ? 'Şablona eklendi' : `${MEALS.find((m) => m[0] === meal)?.[1]?.replace(' öğün', '')} öğününe eklendi`, (d) => applyPick(d, target, pick, g, label, meal), 'add')
          haptic(); close()
        }} />
      ) : (
        <>
          <Segmented value={mode} onChange={setMode} options={[['search', <><IconSearch className="size-4" />Ara</>], ['barcode', <><IconBarcode className="size-4" />Barkod</>],
            ...(target.type === 'log' || target.type === 'template' ? [['rcp', <><IconChefHat className="size-4" />Tarif</>]] : []),
            ...(target.type === 'log' ? [['tpl', <><IconTemplate className="size-4" />Şablon</>]] : [])]} />
          {mode === 'tpl' ? <Templates meal={meal} setMeal={setMeal} date={target.date} onDone={close} /> : mode === 'rcp' ? <RecipePick onPick={setPick} /> : mode === 'search' ? (
            <>
              <div className="relative">
                <IconSearch className="text-muted-foreground absolute left-3 top-1/2 size-4 -translate-y-1/2" />
                <Input className="pl-9" placeholder="Besin ara: tavuk, yulaf, pizza…" value={q} onChange={(e) => { setQ(e.target.value); setOnline({ state: 'idle', items: [] }) }} />
              </div>
              {!q.trim() && recent.length > 0 && (
                <>
                  <SectionTitle>Son eklenenler</SectionTitle>
                  <Card className="divide-y">
                    {recent.map((f) => (
                      <button key={f.id} className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent" onClick={() => setPick(f)}>
                        <Thumb id={imgId(f)} url={imgUrl(f)} />
                        <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{f.name}</div><div className="text-muted-foreground text-xs tabular">son: {fmt(f.lastG)} g · {fmt(macrosFor(f.per100, f.lastG).kcal)} kcal</div></div>
                      </button>
                    ))}
                  </Card>
                </>
              )}
              {!q.trim() && local.length > 0 && <SectionTitle>Besinlerim</SectionTitle>}
              {!q.trim() && !local.length && !recent.length && <p className="text-muted-foreground px-1 text-sm">Yediğin besinin adını yaz. Listede yoksa internette ararız ya da barkodunu okutursun.</p>}
              {(q.trim() || local.length > 0) && <Card className="divide-y">
                {local.map((f) => (
                  <button key={f.id} className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent" onClick={() => setPick(f)}>
                    <Thumb id={imgId(f)} url={imgUrl(f)} />
                    <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{f.name}</div><div className="text-muted-foreground text-xs tabular">100 g · {fmt(f.per100.kcal)} kcal · P {fmt1(f.per100.p)}</div></div>
                    {f.mine && q && <Badge variant="soft">Benim</Badge>}
                  </button>
                ))}
                {local.length === 0 && <div className="text-muted-foreground px-4 py-3 text-sm">Listede yok. İnternette arayabilirsin.</div>}
              </Card>}
              {q.trim().length > 1 && (
                online.state === 'idle' ? <Button variant="outline" onClick={goOnline}><IconWorld />İnternette ara: “{q.trim()}”</Button>
                : online.state === 'loading' ? <div className="text-muted-foreground flex items-center justify-center gap-2 py-3 text-sm"><IconLoader2 className="size-4 animate-spin" />Open Food Facts'te aranıyor</div>
                : online.state === 'error' ? (
                  <div className="grid gap-2">
                    <p className="text-destructive text-sm">{online.msg || 'İnternet araması yapılamadı.'}</p>
                    <Button variant="outline" onClick={goOnline}><IconWorld />Tekrar dene</Button>
                  </div>
                )
                : (
                  <>
                    <SectionTitle>İnternetten · Open Food Facts</SectionTitle>
                    <Card className="divide-y">
                      {online.items.length === 0 && <div className="text-muted-foreground px-4 py-3 text-sm">Sonuç yok. Farklı bir kelime dene ya da besini elle ekle.</div>}
                      {online.items.map((f) => (
                        <button key={f.id} className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent" onClick={() => setPick(f)}>
                          <Thumb url={f.image} />
                          <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{f.name}</div><div className="text-muted-foreground text-xs tabular">100 g · {fmt(f.per100.kcal)} kcal · P {fmt1(f.per100.p)}</div></div>
                        </button>
                      ))}
                    </Card>
                  </>
                )
              )}
            </>
          ) : <Scanner onFound={setPick} onManual={setLabel} />}
        </>
      )}
    </Sheet>
  )
}

function Amount({ food, target, onBack, onDone, meal, setMeal }) {
  const P = food.portions || {}
  const units = [['g', 1], ...Object.entries(P)]
  const [unit, setUnit] = React.useState(food.lastG ? 'g' : units[1]?.[0] || 'g')
  const [qty, setQty] = React.useState(String(food.lastG ? Math.round(food.lastG) : units[1] ? 1 : 100))
  const g = (unit === 'g' ? 1 : P[unit] || 0) * num(qty)
  const valid = okG(g)
  const x = macrosFor(food.per100, valid ? g : 0)
  const label = unit === 'g' ? `${fmt1(g)} g ${food.name}` : `${fmt1(num(qty))} ${unit} ${food.name}`
  return (
    <>
      <div className="flex items-center gap-3">
        <Thumb id={food.image?.startsWith?.('img-') ? food.image : null} url={food.image?.startsWith?.('http') ? food.image : null} className="size-14" />
        <div className="text-muted-foreground text-sm tabular">100 g: {fmt(food.per100.kcal)} kcal · P {fmt1(food.per100.p)} · K {fmt1(food.per100.c)} · Y {fmt1(food.per100.f)}{food.source === 'off' && <div className="text-xs">Kaynak: Open Food Facts</div>}</div>
      </div>
      {target.type === 'log' && <MealField value={meal} onChange={setMeal} />}
      {target.type !== 'myfood' && (
        <>
          <Field label="Birim">
            <div className="no-scrollbar flex gap-1.5 overflow-x-auto">
              {units.map(([u]) => <Button key={u} variant={unit === u ? 'default' : 'outline'} className="h-11 shrink-0" onClick={() => { setUnit(u); setQty(String(u === 'g' ? Math.round(valid ? g : 100) : 1)) }}>{u}{u !== 'g' && <span className="opacity-60 tabular">{fmt1(P[u])} g</span>}</Button>)}
            </div>
          </Field>
          <Field label={unit === 'g' ? 'Gram' : 'Adet / miktar'} id="amt" hint={!valid && qty !== '' ? `0'dan büyük, en fazla ${fmt(MAX_G)} g olmalı.` : undefined}><Input id="amt" inputMode="decimal" value={qty} aria-invalid={!valid} onChange={(e) => setQty(e.target.value.replace(/[^\d.,]/g, ''))} /></Field>
          <div className="bg-muted grid grid-cols-4 gap-2 p-3 text-center text-xs rounded-md tabular">
            {[['kcal', x.kcal], ['Protein', x.p], ['Karb.', x.c], ['Yağ', x.f]].map(([l, v]) => <div key={l}><div className="text-muted-foreground">{l}</div><div className="mt-0.5 text-base font-semibold">{fmt1(v)}</div></div>)}
          </div>
        </>
      )}
      <div className="grid gap-2">
        <Button size="lg" onClick={() => onDone(g, label)} disabled={target.type !== 'myfood' && !valid}><IconPlus />{target.type === 'myfood' ? 'Besinlerime kaydet' : 'Ekle'}</Button>
        <Button variant="ghost" onClick={onBack}>Geri</Button>
      </div>
    </>
  )
}

function Scanner({ onFound, onManual }) {
  const { db } = useApp()
  const mine = React.useRef(db.myFoods); mine.current = db.myFoods
  const video = React.useRef(null)
  const [state, setState] = React.useState('starting')
  const [code, setCode] = React.useState('')
  const [last, setLast] = React.useState('')
  const [run, setRun] = React.useState(0)
  const alive = React.useRef(true)
  React.useEffect(() => () => { alive.current = false }, [])
  const lookup = React.useCallback(async (raw) => {
    const c = String(raw).replace(/\D/g, '')
    setLast(c)
    // önce Besinlerim'de (çevrimdışı da çalışır)
    const local = mine.current.find((f) => f.barcode && String(f.barcode) === c)
    if (local) { onFound(local); return }
    setState('looking')
    try { const f = await lookupBarcode(c); if (alive.current) onFound(f) }
    catch (e) { if (alive.current) setState('error:' + (e?.message || 'Ürün bulunamadı')) }
  }, [onFound])
  React.useEffect(() => {
    let controls, stopped = false, found = false
    setState('starting')
    ;(async () => {
      try {
        const { BrowserMultiFormatReader } = await import('@zxing/browser')
        if (stopped) return
        const reader = new BrowserMultiFormatReader()
        const c = await reader.decodeFromConstraints({ video: { facingMode: 'environment' } }, video.current, (res) => {
          if (res && !found && !stopped) { found = true; controls?.stop(); navigator.vibrate?.(30); haptic(); lookup(res.getText()) }
        })
        controls = c
        if (stopped || found) { c.stop(); return } // sheet kamera açılmadan kapandıysa kamerayı kapat
        setState('scanning')
      } catch { if (!stopped) setState('nocamera') }
    })()
    return () => { stopped = true; controls?.stop() }
  }, [lookup, run])
  return (
    <div className="grid gap-3">
      <div className="relative aspect-[4/3] overflow-hidden bg-black rounded-lg">
        <video ref={video} className="size-full object-cover" playsInline muted />
        <div className="pointer-events-none absolute inset-x-8 top-1/2 h-0.5 -translate-y-1/2 bg-primary/80" />
        {state !== 'scanning' && <div className="absolute inset-0 grid place-items-center p-6 text-center text-sm text-white/80">
          {state === 'starting' ? 'Kamera açılıyor…' : state === 'looking' ? 'Ürün aranıyor…' : state === 'nocamera' ? 'Kameraya erişilemedi. Uygulamayı ana ekrandan açıp kamera izni ver ya da barkodu elle yaz.' : (
            <div className="grid justify-items-center gap-3"><span>{state.slice(6)}</span><Button variant="secondary" size="sm" className="pointer-events-auto h-11" onClick={() => setRun((n) => n + 1)}>Tekrar tara</Button></div>
          )}
        </div>}
      </div>
      <div className="flex gap-2">
        <Input inputMode="numeric" placeholder="Barkodu elle yaz" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} onKeyDown={(e) => e.key === 'Enter' && code && lookup(code)} />
        <Button onClick={() => code && lookup(code)} disabled={!code || state === 'looking'}>Bul</Button>
      </div>
      {state.startsWith('error:') && last && (
        <Button variant="outline" onClick={() => onManual(last)}><IconTag />Etiketten kaydet</Button>
      )}
      <p className="text-muted-foreground text-xs">Önce Besinlerim'e, sonra Open Food Facts'e bakılır. Bulunamazsa ürünü paketteki etiketten bir kez kaydet; sonraki okutmada hemen gelir.</p>
    </div>
  )
}

/* Barkodu bilinmeyen ürünü etiketteki 100 g değerleriyle kaydet */
function LabelForm({ code, onBack, onSaved }) {
  const { update, db } = useApp()
  const [f, setF] = React.useState({ name: '', kcal: '', p: '', c: '', f: '', portion: '' })
  const s = (k) => (e) => setF((x) => ({ ...x, [k]: k === 'name' ? e.target.value : e.target.value.replace(/[^\d.,]/g, '') }))
  const macroOk = num(f.p) <= 100 && num(f.c) <= 100 && num(f.f) <= 100 && num(f.p) + num(f.c) + num(f.f) <= 100
  const ok = f.name.trim() && f.kcal !== '' && num(f.kcal) >= 0 && num(f.kcal) <= 900 && macroOk
  const save = () => {
    if (!ok) return
    const food = { id: uid(), name: f.name.trim(), per100: { kcal: pos(f.kcal), p: pos(f.p), c: pos(f.c), f: pos(f.f) }, portions: pos(f.portion) > 0 ? { porsiyon: pos(f.portion) } : {}, image: null, barcode: code, source: 'mine' }
    const same = db.myFoods.find((x) => norm(x.name) === norm(food.name))
    if (same) { update((d) => { const x = d.myFoods.find((y) => y.id === same.id); if (x) x.barcode = code }); haptic(); onSaved({ ...same, barcode: code }); return }
    update((d) => { d.myFoods.unshift(food) })
    haptic(); onSaved(food)
  }
  return (
    <form className="grid gap-4" onSubmit={(e) => { e.preventDefault(); save() }}>
      <div className="text-muted-foreground flex items-center gap-2 text-sm"><IconBarcode className="size-4" />Barkod <span className="text-foreground tabular">{code}</span></div>
      <Field label="Ürün adı" id="lb-n"><Input id="lb-n" value={f.name} onChange={s('name')} placeholder="ör. Sütaş Yoğurt" autoFocus /></Field>
      <Field label="Etiketteki 100 g değerleri" hint={macroOk ? "Ondalık için virgül kullanabilirsin." : <span className="text-destructive">Protein, karb. ve yağ 100 g içinde toplam 100 g’ı geçemez.</span>}>
        <div className="grid grid-cols-4 gap-2">
          {[['kcal', 'kcal'], ['p', 'Protein'], ['c', 'Karb.'], ['f', 'Yağ']].map(([k, l]) => (
            <div key={k} className="grid gap-1"><span className="text-muted-foreground text-xs">{l}</span><Input inputMode="decimal" value={f[k]} onChange={s(k)} aria-label={l} /></div>
          ))}
        </div>
      </Field>
      <Field label="Porsiyon (g) · isteğe bağlı" id="lb-p"><Input id="lb-p" inputMode="decimal" value={f.portion} onChange={s('portion')} placeholder="ör. 150" /></Field>
      <div className="grid gap-2">
        <Button size="lg" type="submit" disabled={!ok}><IconBookmark />Kaydet ve devam et</Button>
        <Button variant="ghost" type="button" onClick={onBack}>Geri</Button>
      </div>
    </form>
  )
}

/* ================= Yazarak gir (cheat) ================= */
export function CheatSheet({ onClose, date }) {
  const { withUndo, toast, db, update } = useApp()
  const [text, setText] = React.useState('')
  const [rows, setRows] = React.useState(null)
  const [busy, setBusy] = React.useState(null)
  const [meal, setMeal] = React.useState(defaultMeal(db))
  const calc = () => setRows(splitText(text).map(parseLine).map((p) => resolveLine(p, db.myFoods)))
  const setRow = (id, patch) => setRows((r) => r.map((x) => (x.id === id ? { ...x, ...patch } : x)))
  const findOnline = async (row) => {
    setBusy(row.id)
    try { const items = await searchOnline(row.name); if (items[0]) setRow(row.id, { food: items[0], cands: items.slice(0, 6), g: gramsFor(row, items[0]), gs: undefined, err: null }); else setRow(row.id, { miss: true, err: null }) }
    catch (e) { setRow(row.id, { err: e?.message || 'İnternete bağlanılamadı.' }) }
    setBusy(null)
  }
  const ok = (rows || []).filter((r) => r.food && okG(num(r.g)))
  const tot = ok.reduce((a, r) => { const x = macrosFor(r.food.per100, num(r.g)); a.kcal += x.kcal; a.p += x.p; a.c += x.c; a.f += x.f; return a }, { kcal: 0, p: 0, c: 0, f: 0 })
  const save = (close) => {
    withUndo(`${fmt(tot.kcal)} kcal eklendi`, (d) => { const E = (dayLog(d, date).entries ??= []); ok.forEach((r) => E.push(entryFrom(r.food, num(r.g), meal, r.raw))) }, 'add')
    haptic(); close()
  }
  return (
    <Sheet onClose={onClose} title="Yazarak gir" description="Her satıra bir besin yaz. Örn. 2 yumurta, 1,5 dilim ekmek." full
      footer={rows ? (close) => <Button size="lg" onClick={() => save(close)} disabled={!ok.length}>{fmt(tot.kcal)} kcal kaydet</Button> : undefined}>
      <Textarea className="min-h-24" placeholder={'2 dilim pizza\n1 kutu kola\nyarım porsiyon patates kızartması'} value={text} onChange={(e) => { setText(e.target.value); setRows(null) }} />
      <MealField value={meal} onChange={setMeal} />
      {!rows && <Button onClick={calc} disabled={!text.trim()}>Hesapla</Button>}
      {rows && (
        <>
          <div className="bg-muted grid grid-cols-4 gap-2 p-3 text-center text-xs rounded-md tabular">
            {[['kcal', tot.kcal], ['Protein', tot.p], ['Karb.', tot.c], ['Yağ', tot.f]].map(([l, v]) => <div key={l}><div className="text-muted-foreground">{l}</div><div className="mt-0.5 text-base font-semibold">{fmt(v)}</div></div>)}
          </div>
          <div className="grid gap-2">
            {rows.map((r) => (
              <Card key={r.id} className="grid gap-2 p-3">
                <div className="flex items-center justify-between gap-2"><span className="min-w-0 break-words text-sm font-medium">{r.raw}</span>{r.food && <span className="text-muted-foreground shrink-0 text-xs tabular">{fmt(macrosFor(r.food.per100, num(r.g)).kcal)} kcal</span>}</div>
                {r.food ? (
                  <div className="grid grid-cols-[1fr_6rem] gap-2">
                    <NativeSelect value={r.food.id} onChange={(e) => { const f = r.cands.find((c) => c.id === e.target.value); setRow(r.id, { food: f, g: gramsFor(r, f), gs: undefined }) }} aria-label="Eşleşen besin">
                      {r.cands.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                    </NativeSelect>
                    <div className="relative"><Input className="pr-7 text-right" inputMode="decimal" aria-invalid={!okG(num(r.g))} value={r.gs ?? String(Math.round(num(r.g) * 10) / 10).replace('.', ',')} onChange={(e) => { const v = e.target.value.replace(/[^\d.,]/g, ''); setRow(r.id, { gs: v, g: num(v) }) }} aria-label="Gram" /><span className="text-muted-foreground absolute right-2.5 top-1/2 -translate-y-1/2 text-xs">g</span></div>
                  </div>
                ) : (
                  <div className="flex items-center justify-between gap-2">
                    <span className={cn('text-xs', r.err ? 'text-destructive' : 'text-muted-foreground')}>{r.err ? r.err : r.miss ? 'İnternette de bulunamadı.' : 'Listede eşleşme yok.'}</span>
                    {!r.miss && <Button size="sm" variant="outline" onClick={() => findOnline(r)} disabled={busy === r.id}>{busy === r.id ? <IconLoader2 className="animate-spin" /> : <IconWorld />}{r.err ? 'Tekrar dene' : 'İnternette ara'}</Button>}
                  </div>
                )}
              </Card>
            ))}
          </div>
          <p className="text-muted-foreground text-xs">Değerler ortalama porsiyonlara göre tahmindir; besini ya da gramı değiştirerek düzeltebilirsin. Sık yediğin bir şeyse sonra Besinlerim'e kaydedebilirsin.</p>
        </>
      )}
    </Sheet>
  )
}

/* ================= Besinlerim ================= */
function MyFoods() {
  const { db, open } = useApp()
  const [q, setQ] = React.useState('')
  const list = db.myFoods.filter((f) => !q || f.name.toLocaleLowerCase('tr').includes(q.toLocaleLowerCase('tr')))
  return (
    <>
      <div className="grid grid-cols-2 gap-2">
        <Button onClick={() => open('foodEdit', {})}><IconPlus />Yeni besin</Button>
        <Button variant="outline" onClick={() => open('addFood', { target: { type: 'myfood' } })}><IconWorld />Ara / barkod</Button>
      </div>
      <Input placeholder="Besinlerimde ara" value={q} onChange={(e) => setQ(e.target.value)} />
      <ShareBar kind="foods" />
      {list.length === 0 ? <Empty icon={IconToolsKitchen2} title="Henüz besin yok">Sık yediğin besinleri ekle; menüye eklerken en üstte çıkarlar.</Empty> : (
        <Card className="divide-y">
          {list.map((f) => (
            <button key={f.id} className="flex w-full items-center gap-3 px-3 py-2.5 text-left active:bg-accent" onClick={() => open('foodEdit', { id: f.id })}>
              <Thumb id={imgId(f)} url={imgUrl(f)} />
              <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{f.name}</div><div className="text-muted-foreground text-xs tabular">100 g · {fmt(f.per100.kcal)} kcal · P {fmt1(f.per100.p)} · K {fmt1(f.per100.c)} · Y {fmt1(f.per100.f)}</div></div>
              <IconChevronRight className="text-muted-foreground size-4" />
            </button>
          ))}
        </Card>
      )}
    </>
  )
}

function ImagePicker({ value, onChange }) {
  const url = useImage(value?.startsWith?.('img-') ? value : null) || (value?.startsWith?.('http') ? value : null)
  const ref = React.useRef(null)
  return (
    <div className="flex items-center gap-3">
      {url ? <img src={url} alt="" className="size-20 object-cover rounded-md" /> : <div className="bg-muted grid size-20 place-items-center rounded-md"><IconPhoto className="text-muted-foreground size-6" stroke={1.5} /></div>}
      <div className="grid gap-2">
        <Button variant="outline" size="sm" onClick={() => ref.current?.click()}><IconCamera />{url ? 'Görseli değiştir' : 'Görsel ekle'}</Button>
        {url && <Button variant="ghost" size="sm" onClick={() => onChange(null)}><IconX />Kaldır</Button>}
      </div>
      <input ref={ref} type="file" accept="image/*" className="hidden" onChange={async (e) => { const f = e.target.files?.[0]; if (f) onChange(await saveImage(f, 800)); e.target.value = '' }} />
    </div>
  )
}

export function FoodEditSheet({ onClose, id }) {
  const { withUndo, toast, db, update } = useApp()
  const [cur, closing] = useLast(id ? db.myFoods.find((f) => f.id === id) : null, id ? onClose : null)
  const [f, setF] = React.useState(() => cur
    ? { name: cur.name, ...cur.per100, image: cur.image, portions: Object.entries(cur.portions || {}).map(([u, g]) => `${u} = ${g}`).join('\n') }
    : { name: '', kcal: '', p: '', c: '', f: '', image: null, portions: '' })
  const s = (k) => (v) => setF((x) => ({ ...x, [k]: v }))
  const save = (close) => {
    if (!f.name.trim()) return
    const portions = Object.fromEntries(f.portions.split('\n').map((l) => l.split('=').map((x) => x.trim())).filter(([u, g]) => u && num(g) > 0).map(([u, g]) => [u, num(g)]))
    const v = { name: f.name.trim(), per100: { kcal: pos(f.kcal), p: pos(f.p), c: pos(f.c), f: pos(f.f) }, portions, image: f.image, source: 'mine' }
    update((d) => { const t = cur && d.myFoods.find((x) => x.id === id); if (t) Object.assign(t, v); else d.myFoods.unshift({ id: uid(), ...v }) })
    if (cur?.image && cur.image !== f.image) deleteImage(cur.image)
    closing.current = true; close()
  }
  return (
    <Sheet onClose={onClose} title={cur ? 'Besini düzenle' : 'Yeni besin'} full footer={(close) => <>
      <Button size="lg" onClick={() => save(close)} disabled={!f.name.trim()}>Kaydet</Button>
      {cur && <Button variant="ghost" className="text-destructive" onClick={() => { closing.current = true; const img = cur.image; withUndo(`${cur.name} silindi`, (d) => { const i = d.myFoods.findIndex((x) => x.id === id); if (i >= 0) d.myFoods.splice(i, 1) }, 'delete', () => deleteImage(img)); close() }}>Besinlerimden sil</Button>}
    </>}>
      <ImagePicker value={f.image} onChange={s('image')} />
      <Field label="Ad" id="fe-n"><Input id="fe-n" value={f.name} onChange={(e) => s('name')(e.target.value)} placeholder="ör. Annemin mercimek köftesi" /></Field>
      <Field label="100 g başına değerler">
        <div className="grid grid-cols-4 gap-2">
          {[['kcal', 'kcal'], ['p', 'Protein'], ['c', 'Karb.'], ['f', 'Yağ']].map(([k, l]) => (
            <div key={k} className="grid gap-1"><span className="text-muted-foreground text-xs">{l}</span><Input inputMode="decimal" value={f[k]} onChange={(e) => s(k)(e.target.value.replace(/[^\d.,]/g, ''))} aria-label={l} /></div>
          ))}
        </div>
      </Field>
      <Field label="Porsiyonlar" id="fe-p" hint="Her satıra birim = gram. Örn: adet = 55, dilim = 30"><Textarea id="fe-p" value={f.portions} onChange={(e) => s('portions')(e.target.value)} placeholder={'adet = 55\nporsiyon = 200'} /></Field>
    </Sheet>
  )
}

/* ================= Paylaşım (aile) ================= */
const blobToDataUrl = (b) => new Promise((r) => { const fr = new FileReader(); fr.onload = () => r(fr.result); fr.onerror = () => r(null); fr.readAsDataURL(b) })
function ShareBar({ kind }) {
  const { withUndo, toast, db } = useApp()
  const ref = React.useRef(null)
  const [busy, setBusy] = React.useState(false)
  const items = kind === 'foods' ? db.myFoods : db.recipes.filter((r) => r.name && r.items.length)
  const share = async () => {
    if (!items.length || busy) return
    setBusy(true)
    try {
      const foods = kind === 'foods' ? db.myFoods : [], recipes = kind === 'recipes' ? items : []
      const imgs = {}
      for (const id of [...foods, ...recipes].map((x) => x.image).filter((x) => x?.startsWith?.('img-'))) { const b = await idbGet(id).catch(() => null); if (b) { const u = await blobToDataUrl(b); if (u) imgs[id] = u } }
      const strip = ({ lastG, mine, ...x }) => x
      const text = JSON.stringify({ app: 'balli-share', v: 1, sharedAt: new Date().toISOString(), foods: foods.map(strip), recipes, imgs })
      const file = new File([text], 'balli-paylasim.json', { type: 'application/json' })
      if (navigator.canShare?.({ files: [file] })) {
        try { await navigator.share({ files: [file], title: 'Ballı paylaşımı' }) } catch (e) { if (e?.name !== 'AbortError') throw e }
      } else {
        const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = file.name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000)
        toast('Paylaşım dosyası indirildi')
      }
    } catch { toast('Paylaşılamadı') } finally { setBusy(false) }
  }
  const importIt = async (file) => {
    try {
      let j; try { j = JSON.parse(await file.text()) } catch { throw new Error('Dosya okunamadı.') }
      if (j?.app !== 'balli-share' || (!Array.isArray(j.foods) && !Array.isArray(j.recipes))) throw new Error('Bu bir Ballı paylaşım dosyası değil.')
      if (!Array.isArray(j.foods)) j.foods = []
      if (!Array.isArray(j.recipes)) j.recipes = []
      const haveF = new Set(db.myFoods.map((f) => norm(f.name))), haveR = new Set(db.recipes.map((r) => norm(r.name)))
      const imgMap = {}
      const img = async (id) => {
        if (!id || !/^img-[a-z0-9]+$/i.test(id)) return null
        if (imgMap[id] !== undefined) return imgMap[id]
        const u = j.imgs?.[id]
        if (typeof u !== 'string' || !u.startsWith('data:image/')) return (imgMap[id] = null)
        try { const b = await (await fetch(u)).blob(); const nid = 'img-' + uid(); await idbSet(nid, b); return (imgMap[id] = nid) } catch { return (imgMap[id] = null) }
      }
      const fin = (v) => (Number.isFinite(+v) && +v >= 0 ? +v : 0)
      const cap = (v, m) => Math.min(m, fin(v))
      const per = (p) => ({ kcal: cap(p?.kcal, 900), p: cap(p?.p, 100), c: cap(p?.c, 100), f: cap(p?.f, 100) })
      const foods = [], recipes = []
      for (const f of j.foods || []) {
        const n = String(f?.name || '').trim(); if (!n || haveF.has(norm(n)) || !f.per100 || !Number.isFinite(+f.per100.kcal)) continue
        haveF.add(norm(n))
        foods.push({ id: uid(), name: n.slice(0, 120), per100: per(f.per100), portions: Object.fromEntries(Object.entries(f.portions || {}).filter(([, g]) => fin(g) > 0).map(([u, g]) => [String(u).slice(0, 30), fin(g)])), image: await img(f.image), ...(f.barcode ? { barcode: String(f.barcode).replace(/\D/g, '') } : {}), source: 'mine' })
      }
      for (const r of j.recipes || []) {
        const n = String(r?.name || '').trim(); if (!n || haveR.has(norm(n)) || !Array.isArray(r.items)) continue
        haveR.add(norm(n))
        recipes.push({ id: uid(), name: n.slice(0, 120), servings: Math.min(50, Math.max(1, Math.round(fin(r.servings)) || 1)), note: String(r.note || '').slice(0, 2000), image: await img(r.image), items: r.items.filter((i) => i?.name).slice(0, 60).map((i) => ({ id: uid(), name: String(i.name).slice(0, 120), g: cap(i.g, 10000), per100: per(i.per100) })) })
      }
      if (!foods.length && !recipes.length) { toast('Yeni bir şey yok, hepsi zaten sende'); return }
      const msg = [foods.length && `${foods.length} besin`, recipes.length && `${recipes.length} tarif`].filter(Boolean).join(', ') + ' eklendi'
      withUndo(msg, (d) => { d.myFoods.unshift(...foods); d.recipes.unshift(...recipes) }, 'add')
    } catch (e) { toast(/iterable|undefined|null|of /.test(e.message || '') ? 'Dosya okunamadı.' : e.message || 'İçe alınamadı', { kind: 'error' }) }
  }
  return (
    <div className="grid grid-cols-2 gap-2">
      <Button variant="outline" onClick={share} disabled={!items.length || busy}>{busy ? <IconLoader2 className="animate-spin" /> : <IconShare2 />}{kind === 'foods' ? 'Besinleri paylaş' : 'Tarifleri paylaş'}</Button>
      <Button variant="outline" onClick={() => ref.current?.click()}><IconFileImport />İçe al</Button>
      <input ref={ref} type="file" accept="application/json,.json" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) importIt(f); e.target.value = '' }} aria-label="Paylaşım dosyası seç" />
    </div>
  )
}

/* ================= Tarifler ================= */
function Recipes() {
  const { withUndo, toast, db, update, open } = useApp()
  const create = () => { const id = uid(); update((d) => { d.recipes.unshift({ id, name: '', servings: 2, image: null, note: '', items: [] }) }); open('recipeForm', { id, isNew: true }) }
  return (
    <>
      <Button onClick={create}><IconPlus />Yeni tarif</Button>
      <ShareBar kind="recipes" />
      {db.recipes.length === 0 ? <Empty icon={IconChefHat} title="Tarif defterin boş">Malzemeleri gramajıyla gir; porsiyon başı kalori ve makro otomatik hesaplanır.</Empty> : (
        <div className="grid grid-cols-2 gap-3">
          {db.recipes.map((r) => <RecipeCard key={r.id} r={r} onClick={() => open('recipe', { id: r.id })} />)}
        </div>
      )}
    </>
  )
}
function RecipeCard({ r, onClick }) {
  const url = useImage(r.image)
  const t = recipeTotals(r)
  return (
    <button className="press text-left" onClick={onClick}>
      <Card className="overflow-hidden">
        {url ? <img src={url} alt="" className="aspect-[4/3] w-full object-cover" /> : <div className="bg-muted grid aspect-[4/3] place-items-center"><IconChefHat className="text-muted-foreground size-7" stroke={1.25} /></div>}
        <div className="p-3">
          <div className="truncate text-sm font-medium">{r.name || 'Adsız tarif'}</div>
          <div className="text-muted-foreground text-xs tabular">{fmt(t.perServing.kcal)} kcal · P {fmt(t.perServing.p)} g / porsiyon</div>
        </div>
      </Card>
    </button>
  )
}

export function RecipeSheet({ onClose, id }) {
  const { withUndo, toast, db, update, open } = useApp()
  const [r, closing] = useLast(db.recipes.find((x) => x.id === id), onClose)
  const url = useImage(r?.image)
  const [n, setN] = React.useState(1)
  const [meal, setMeal] = React.useState(defaultMeal(db))
  if (!r) return null
  const t = recipeTotals(r)
  const canAdd = t.grams > 0 && r.items.length > 0
  const per100 = canAdd ? { kcal: (t.total.kcal / t.grams) * 100, p: (t.total.p / t.grams) * 100, c: (t.total.c / t.grams) * 100, f: (t.total.f / t.grams) * 100 } : { kcal: 0, p: 0, c: 0, f: 0 }
  const portionG = t.grams / Math.max(1, r.servings || 1)
  const add = (close) => {
    if (!canAdd) return
    closing.current = true
    withUndo('Bugüne eklendi', (d) => { (dayLog(d, todayKey()).entries ??= []).push(entryFrom({ name: r.name, per100, portions: { porsiyon: portionG }, image: r.image }, portionG * n, meal, `${fmt1(n)} porsiyon ${r.name}`)) }, 'add')
    haptic(); close()
  }
  return (
    <Sheet onClose={onClose} title={r.name || 'Adsız tarif'} description={`${r.servings} porsiyon · porsiyon ${fmt(portionG)} g`} full
      footer={(close) => <Button size="lg" onClick={() => add(close)} disabled={!canAdd}><IconPlus />Bugüne ekle · {fmt(t.perServing.kcal * n)} kcal</Button>}>
      {url && <img src={url} alt="" className="aspect-[4/3] w-full object-cover rounded-lg" />}
      <div className="bg-muted grid grid-cols-4 gap-2 p-3 text-center text-xs rounded-md tabular">
        {[['kcal', t.perServing.kcal], ['Protein', t.perServing.p], ['Karb.', t.perServing.c], ['Yağ', t.perServing.f]].map(([l, v]) => <div key={l}><div className="text-muted-foreground">{l}</div><div className="mt-0.5 text-base font-semibold">{fmt(v)}</div></div>)}
      </div>
      <SectionTitle action={<Button variant="ghost" size="sm" onClick={() => open('recipeForm', { id })}><IconPencil />Düzenle</Button>}>Malzemeler</SectionTitle>
      <Card className="divide-y">
        {r.items.map((i) => <div key={i.id} className="flex justify-between gap-3 px-4 py-2 text-sm"><span className="min-w-0 break-words">{i.name}</span><span className="text-muted-foreground shrink-0 tabular">{fmt1(i.g)} g</span></div>)}
        {!r.items.length && <div className="text-muted-foreground px-4 py-3 text-sm">Malzeme eklenmemiş.</div>}
      </Card>
      {r.items.length > 0 && !canAdd && <p className="text-destructive text-sm">Malzemelerin gramajını gir; toplam 0 g olan tarif eklenemez.</p>}
      {r.note && <p className="text-muted-foreground text-sm">{r.note}</p>}
      <SectionTitle>Bugüne ekle</SectionTitle>
      <MealField value={meal} onChange={setMeal} />
      <Field label="Porsiyon"><Stepper value={n} onChange={setN} step={0.5} min={0.5} /></Field>
    </Sheet>
  )
}

export function RecipeForm({ onClose, id, isNew }) {
  const { withUndo, toast, db, update, open } = useApp()
  const [r, closing] = useLast(db.recipes.find((x) => x.id === id), onClose)
  const [c, setC] = React.useState(false)
  if (!r) return null
  const t = recipeTotals(r)
  const set = (k, v) => update((d) => { const x = d.recipes.find((x) => x.id === id); if (x) x[k] = v })
  const close2 = () => { if (isNew && !r.name.trim() && !r.items.length) update((d) => { const i = d.recipes.findIndex((x) => x.id === id); if (i >= 0) d.recipes.splice(i, 1) }); onClose() }
  return (
    <Sheet onClose={close2} title={isNew ? 'Yeni tarif' : 'Tarifi düzenle'} full footer={(close) => <>
      <Button size="lg" onClick={close}><IconCheck />Bitti</Button>
      {!isNew && (c ? <Button variant="destructive" onClick={() => { closing.current = true; const img = r.image; withUndo(`${r.name || 'Tarif'} silindi`, (d) => { const i = d.recipes.findIndex((x) => x.id === id); if (i >= 0) d.recipes.splice(i, 1) }, 'delete', () => deleteImage(img)); close() }}>Evet, tarifi sil</Button>
        : <Button variant="ghost" className="text-destructive" onClick={() => setC(true)}>Tarifi sil</Button>)}
    </>}>
      <ImagePicker value={r.image} onChange={(v) => { const old = r.image; set('image', v); if (old && old !== v) deleteImage(old) }} />
      <Field label="Tarif adı" id="r-n"><Input id="r-n" value={r.name} onChange={(e) => set('name', e.target.value)} placeholder="ör. Sebzeli fırın kıyma" /></Field>
      <Field label="Kaç porsiyon çıkıyor?"><Stepper value={r.servings} onChange={(v) => set('servings', v)} step={1} min={1} /></Field>
      <SectionTitle action={<Button variant="ghost" size="sm" onClick={() => open('addFood', { target: { type: 'recipe', rid: id } })}><IconPlus />Malzeme</Button>}>Malzemeler</SectionTitle>
      <Card className="divide-y">
        {r.items.map((i) => <IngredientRow key={i.id} i={i} rid={id} />)}
        {!r.items.length && <div className="text-muted-foreground px-4 py-3 text-sm">Malzeme ekle; makrolar otomatik hesaplanır.</div>}
      </Card>
      <div className="text-muted-foreground text-sm tabular">Toplam {fmt1(t.grams)} g · {fmt(t.total.kcal)} kcal · porsiyon başı {fmt(t.perServing.kcal)} kcal, P {fmt(t.perServing.p)} g</div>
      <Field label="Yapılış / not" id="r-note"><Textarea id="r-note" value={r.note} onChange={(e) => set('note', e.target.value)} /></Field>
    </Sheet>
  )
}

function IngredientRow({ i, rid }) {
  const { update } = useApp()
  // ham metni yerelde tut: "12." yazarken 12'ye, boşaltınca 0'a atlamasın
  const [v, setV] = React.useState(() => String(i.g ?? '').replace('.', ','))
  React.useEffect(() => { if (num(v) !== (i.g || 0)) setV(String(i.g ?? '').replace('.', ',')) }, [i.g]) // eslint-disable-line
  const commit = (raw) => update((d) => { const it = d.recipes.find((x) => x.id === rid)?.items.find((x) => x.id === i.id); if (it) it.g = pos(raw) })
  return (
    <div className="flex items-center gap-2 py-1 pl-3 pr-1">
      <span className="min-w-0 flex-1 truncate text-sm">{i.name}</span>
      <div className="relative w-24"><Input className="h-10 pr-7 text-right" inputMode="decimal" value={v} aria-invalid={!(num(v) > 0)} onChange={(e) => { const x = e.target.value.replace(/[^\d.,]/g, ''); setV(x); commit(x) }} aria-label={`${i.name} gram`} /><span className="text-muted-foreground absolute right-2.5 top-1/2 -translate-y-1/2 text-xs">g</span></div>
      <Button variant="ghost" size="icon" className="size-11" onClick={() => update((d) => { const x = d.recipes.find((x) => x.id === rid); const k = x?.items.findIndex((y) => y.id === i.id); if (k >= 0) x.items.splice(k, 1) })} aria-label="Malzemeyi sil"><IconTrash /></Button>
    </div>
  )
}

/* Öğün seçici: tek öğün kullanılıyorsa gizlenir */
function MealField({ value, onChange }) {
  const { db } = useApp()
  const ms = mealsOf(db, value)
  React.useEffect(() => { if (!ms.some(([k]) => k === value)) onChange(ms[0][0]) }, [value]) // eslint-disable-line
  if (ms.length < 2) return null
  return <Field label="Öğün"><Segmented value={value} onChange={onChange} options={ms.map(([k, l]) => [k, l.replace(' öğün', '')])} /></Field>
}
