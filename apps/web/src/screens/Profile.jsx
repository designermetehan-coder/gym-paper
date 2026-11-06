import * as React from 'react'
import { IconPlus, IconPencil, IconDownload, IconUpload, IconRefresh, IconAdjustmentsHorizontal, IconCircleCheckFilled, IconTrash, IconSelector, IconCheck, IconChevronRight, IconRuler, IconUsers, IconAlertTriangle, IconHistory, IconKey, IconMailForward, IconCloud } from '@tabler/icons-react'
import { Button, Card, Badge, Sheet, Input, Field, Segmented, NativeSelect, Empty, SectionTitle } from '@/components/ui'
import { Header } from '@/components/common'
import { GoalCelebration } from '@/screens/Today'
import { PROGRAM_TEMPLATES, templateFor } from '@/lib/program'
import { useApp, exportAll, importAll, goalState, migrate, MEALS } from '@/lib/store'
import { cloudEnabled, signIn, signUp, signOut, pullRemote, requestPasswordReset, updatePassword } from '@/lib/cloud'
import { get as idbGet, set as idbSet } from 'idb-keyval'
import { longDate, shortDate, fmt, fmt1, num, uid, keyOf, cn } from '@/lib/utils'

const MF = [['kg', 'Kilo', 'kg'], ['bel', 'Bel', 'cm'], ['kalca', 'Kalça', 'cm'], ['gogus', 'Göğüs', 'cm'], ['sagkol', 'Sağ kol', 'cm'], ['solkol', 'Sol kol', 'cm'], ['bacak', 'Bacak', 'cm'], ['omuz', 'Omuz', 'cm']]

function getTheme() { try { return JSON.parse(localStorage.getItem('balli-theme') || '"system"') } catch { return 'system' } }
export function applyTheme(t) {
  try { localStorage.setItem('balli-theme', JSON.stringify(t)) } catch {}
  const host = document.documentElement.getAttribute('data-theme')
  const dark = t === 'dark' || (t === 'system' && (host === 'dark' || host === 'light' ? host === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches))
  document.documentElement.classList.toggle('dark', dark)
  document.querySelectorAll('meta[name="theme-color"]').forEach((m) => { m.setAttribute('content', dark ? '#0a0a0a' : '#ffffff'); m.removeAttribute('media') })
}

export default function Profile() {
  const { db, open, profiles } = useApp()
  const [theme, setTheme] = React.useState(getTheme)
  const [all, setAll] = React.useState(false)
  const G = goalState(db)
  const list = [...db.measures].filter((m) => m.date).sort((a, b) => (a.date < b.date ? 1 : -1))
  const [manage, setManage] = React.useState(false)
  const nextGoal = G.done ? ' · tüm hedefler tamam' : G.active != null ? ` · sıradaki hedef ${fmt1(G.active)} kg` : ''
  return (
    <div className="grid gap-4">
      <GoalCelebration />
      <Header eyebrow="Profil" title={db.profile.name || 'Profil'} sub={G.cur != null ? `${fmt1(G.cur)} kg${nextGoal}` : undefined}
        actions={<>
          <Button variant="outline" size="icon" className="size-11" onClick={() => setManage(true)} aria-label="Adını düzenle"><IconPencil /></Button>
          <Button variant="outline" size="icon" className="size-11" onClick={() => open('settings')} aria-label="Günlük hedefler"><IconAdjustmentsHorizontal /></Button>
        </>} />

      {/* Profil ekleme kaldırıldı; birden çok profil zaten varsa geçiş için tek satır kalır */}
      {profiles.list.length > 1 && <Button className="-mt-1 h-11 justify-self-start" variant="ghost" onClick={() => setManage(true)}><IconUsers />Profil değiştir</Button>}

      {manage && <ProfilesSheet onClose={() => setManage(false)} />}
      <SectionTitle action={<Button variant="ghost" className="h-11" onClick={() => open('goals')}><IconPencil />Düzenle</Button>}>Kilo hedefleri</SectionTitle>
      <Card className="grid gap-4 p-4">
        <div className="grid grid-cols-3 gap-3">
          <div><div className="text-muted-foreground text-xs">Başlangıç</div><div className="text-lg font-semibold tabular">{G.start != null ? fmt1(G.start) : '–'}<span className="text-muted-foreground text-xs font-normal"> kg</span></div></div>
          <div><div className="text-muted-foreground text-xs">Şimdi</div><div className="text-lg font-semibold tabular">{G.cur != null ? fmt1(G.cur) : '–'}<span className="text-muted-foreground text-xs font-normal"> kg</span></div></div>
          <div><div className="text-muted-foreground text-xs">Toplam</div><div className={cn('text-lg font-semibold tabular', G.lost > 0 && 'text-success')}>{G.start == null || G.cur == null || G.pts.length === 0 ? '–' : <>{G.lost > 0 ? '↓ ' : G.lost < 0 ? '↑ ' : ''}{fmt1(Math.abs(G.lost))}<span className="text-muted-foreground text-xs font-normal"> kg</span></>}</div></div>
        </div>
        {G.goals.length > 0 ? (
          <div className="grid gap-2.5">
            {G.goals.map((g, i) => {
              const reached = G.cur != null && G.cur <= g
              const active = !G.done && i === G.idx
              return (
                <div key={g} className="grid gap-1.5">
                  <div className="flex items-center justify-between gap-2 text-sm">
                    <span className="flex items-center gap-2"><span className="text-muted-foreground w-14 text-xs">{i + 1}. hedef</span><span className="font-semibold tabular">{fmt1(g)} kg</span></span>
                    {reached ? <Badge variant="success"><IconCircleCheckFilled />Ulaşıldı</Badge> : active ? <Badge>{fmt1(G.left)} kg kaldı</Badge> : <Badge variant="outline">Sırada</Badge>}
                  </div>
                  {active && <div className="bg-primary/15 h-1.5 overflow-hidden rounded-full"><div className="bg-primary h-full transition-all duration-500" style={{ width: `${G.pct * 100}%` }} /></div>}
                </div>
              )
            })}
          </div>
        ) : <Button variant="outline" onClick={() => open('goals')}><IconPlus />Hedef ekle</Button>}
      </Card>

      <SectionTitle action={<Button variant="ghost" className="h-11" onClick={() => open('measure', {})}><IconPlus />Ölçüm</Button>}>Ölçümler</SectionTitle>
      {G.pts.length > 1 && <Card className="p-4"><WeightChart pts={G.pts} goal={G.active} /></Card>}
      {list.length === 0 && <Empty icon={IconRuler} title="Henüz ölçüm yok" action={<Button variant="outline" onClick={() => open('measure', {})}><IconPlus />İlk ölçümünü ekle</Button>}>Kilonu ve çevre ölçülerini ekle; değişimi burada grafikle görürsün.</Empty>}
      <div className="grid gap-2">
        {(all ? list : list.slice(0, 2)).map((m, i) => (
          <button key={m.id} className="press text-left" onClick={() => open('measure', { id: m.id })}>
            <Card className="grid gap-3 p-4">
              <div className="flex items-center justify-between"><span className="font-medium">{longDate(m.date)}</span><IconPencil className="text-muted-foreground size-4" /></div>
              <div className="grid grid-cols-4 gap-x-3 gap-y-2">
                {MF.filter(([k]) => m[k] != null).map(([k, l, u]) => {
                  const pv = list.slice(i + 1).find((x) => x[k] != null); const d = pv ? m[k] - pv[k] : null
                  return (
                    <div key={k} className="min-w-0">
                      <div className="text-muted-foreground text-[11px]">{l}</div>
                      <div className="text-sm font-semibold tabular">{fmt1(m[k])}<span className="text-muted-foreground text-[10px] font-normal"> {u}</span></div>
                      {d != null && d !== 0 && <div className={cn('text-[11px] tabular', d < 0 ? 'text-success' : 'text-muted-foreground')}>{d < 0 ? '↓' : '↑'} {fmt1(Math.abs(d))}</div>}
                    </div>
                  )
                })}
              </div>
            </Card>
          </button>
        ))}
        {list.length > 2 && <Button variant="ghost" onClick={() => setAll(!all)}>{all ? 'Daha az göster' : `Tüm ölçümler (${list.length})`}</Button>}
      </div>

      <SectionTitle>Görünüm</SectionTitle>
      <Segmented value={theme} onChange={(t) => { setTheme(t); applyTheme(t) }} options={[['system', 'Sistem'], ['light', 'Açık'], ['dark', 'Koyu']]} />

      <SectionTitle>Bulut yedeği</SectionTitle>
      <CloudCard />
      <SectionTitle>Veri</SectionTitle>
      <UpdateCard />
      <DataCard />
      <p className="text-muted-foreground pb-2 text-center text-xs">Ballı 1.0 · {db.cloud ? 'veriler cihazda ve bulutta' : 'veriler bu cihazda'}</p>
    </div>
  )
}

function WeightChart({ pts, goal }) {
  pts = pts.filter((p) => p.date && Number.isFinite(+p.kg))
  if (pts.length < 2) return null
  const W = 340, H = 140, pl = 30, pr = 8, pt = 12, pb = 20
  const t0 = new Date(pts[0].date).getTime(), t1 = new Date(pts.at(-1).date).getTime()
  const ys = pts.map((p) => p.kg).concat(goal ? [goal] : [])
  const lo = Math.floor(Math.min(...ys) - 2), hi = Math.ceil(Math.max(...ys) + 2)
  const X = (d) => pl + ((new Date(d).getTime() - t0) / (t1 - t0 || 1)) * (W - pl - pr)
  const Y = (v) => pt + ((hi - v) / (hi - lo)) * (H - pt - pb)
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${X(p.date).toFixed(1)},${Y(p.kg).toFixed(1)}`).join('')
  const area = `${line}L${X(pts.at(-1).date)},${H - pb}L${X(pts[0].date)},${H - pb}Z`
  const ticks = [lo, Math.round((lo + hi) / 2), hi]
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="block w-full max-w-full" role="img" aria-label="Kilo grafiği">
      <defs><linearGradient id="wg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stopColor="var(--primary)" stopOpacity=".22" /><stop offset="1" stopColor="var(--primary)" stopOpacity="0" /></linearGradient></defs>
      {ticks.map((v) => <g key={v}><line x1={pl} x2={W - pr} y1={Y(v)} y2={Y(v)} stroke="var(--border)" /><text x={pl - 6} y={Y(v) + 3} textAnchor="end" fontSize="9" fill="var(--muted-foreground)">{v}</text></g>)}
      {goal >= lo && <g><line x1={pl} x2={W - pr} y1={Y(goal)} y2={Y(goal)} stroke="var(--success)" strokeDasharray="4 3" /><text x={W - pr} y={Y(goal) - 4} textAnchor="end" fontSize="9" fill="var(--success)">hedef {fmt1(goal)}</text></g>}
      <path d={area} fill="url(#wg)" /><path d={line} fill="none" stroke="var(--primary)" strokeWidth="2" strokeLinejoin="round" />
      {pts.map((p, i) => <circle key={p.id} cx={X(p.date)} cy={Y(p.kg)} r={i === pts.length - 1 ? 4 : 2.5} fill={i === pts.length - 1 ? 'var(--primary)' : 'var(--card)'} stroke="var(--primary)" strokeWidth="1.5" />)}
      {[pts[0], pts.at(-1)].map((p, i) => <text key={i} x={X(p.date)} y={H - 5} textAnchor={i ? 'end' : 'start'} fontSize="9" fill="var(--muted-foreground)">{shortDate(p.date)}</text>)}
    </svg>
  )
}

/* ---------- Uygulama güncellemesi (verilere dokunmaz) ---------- */
function useUpdate() {
  const [, force] = React.useReducer((x) => x + 1, 0)
  React.useEffect(() => { window.addEventListener('balli-update', force); return () => window.removeEventListener('balli-update', force) }, [])
  return window.__balliUpdate || { ready: false, checking: false }
}
const BUILD = typeof __APP_BUILD__ !== 'undefined' ? __APP_BUILD__ : null // eslint-disable-line no-undef
function UpdateCard() {
  const { db, activeId, toast } = useApp()
  const U = useUpdate()
  const [busy, setBusy] = React.useState(false)
  const [auto, setAuto] = React.useState(() => { try { return localStorage.getItem('balli-autoupdate') !== '0' } catch { return true } })
  const ver = BUILD ? new Date(BUILD).toLocaleString('tr-TR', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }) : 'geliştirme'
  const check = async () => {
    if (!U.check) return toast('Güncelleme yalnız ana ekrana eklenen uygulamada çalışır')
    const r = await U.check()
    if (!r) toast(navigator.onLine ? 'En güncel sürümü kullanıyorsun' : 'İnternet bağlantısı yok', { kind: navigator.onLine ? undefined : 'error' })
  }
  const apply = async () => {
    setBusy(true)
    // güvenlik için önce yedek: veriler zaten cihazda kalır, bu yalnız ek güvence
    try { await autoBackup(activeId, db, true) } catch {}
    U.apply?.()
  }
  const setA = (v) => { setAuto(v); try { localStorage.setItem('balli-autoupdate', v ? '1' : '0') } catch {} }
  return (
    <>
      <SectionTitle>Uygulama</SectionTitle>
      <Card className="grid gap-3 p-4">
        <div className="flex items-center gap-3">
          <div className={cn('grid size-11 shrink-0 place-items-center rounded-full', U.ready ? 'bg-primary/12 text-primary' : 'bg-muted text-muted-foreground')}><IconRefresh className={cn('size-5', U.checking && 'animate-spin')} /></div>
          <div className="min-w-0 flex-1">
            <div className="font-medium">{U.ready ? 'Yeni sürüm hazır' : 'Ballı güncel'}</div>
            <div className="text-muted-foreground text-xs tabular">Sürüm: {ver}</div>
          </div>
          {U.ready
            ? <Button onClick={apply} disabled={busy}>{busy ? 'Güncelleniyor…' : 'Güncelle'}</Button>
            : <Button variant="outline" onClick={check} disabled={U.checking}>{U.checking ? 'Bakılıyor…' : 'Denetle'}</Button>}
        </div>
        <p className="text-muted-foreground text-xs">Güncelleme yalnız uygulamayı yeniler; kayıtların, programların ve ayarların aynen kalır. Güncellemeden önce otomatik yedek alınır.</p>
        <button type="button" role="switch" aria-checked={auto} onClick={() => setA(!auto)} className="flex min-h-11 items-center justify-between gap-3 text-left text-sm">
          <span>Otomatik güncelle<span className="text-muted-foreground block text-xs">Uygulamadan çıkınca yeni sürüm kendiliğinden yüklenir</span></span>
          <span className={cn('relative h-7 w-12 shrink-0 rounded-full transition-colors', auto ? 'bg-primary' : 'bg-foreground/15')}><span className={cn('absolute top-0.5 size-6 rounded-full bg-white shadow transition-transform', auto ? 'translate-x-[22px]' : 'translate-x-0.5')} /></span>
        </button>
      </Card>
    </>
  )
}

function DataCard() {
  const { db, reset, replace, renameProfile, open } = useApp()
  const [msg, setMsg] = React.useState('')
  const [c, setC] = React.useState(false)
  const ref = React.useRef(null)
  const exportIt = async () => {
    const text = await exportAll(db)
    const name = `balli-yedek-${keyOf(new Date())}.json`
    const file = new File([text], name, { type: 'application/json' })
    try {
      if (navigator.canShare?.({ files: [file] })) { await navigator.share({ files: [file], title: 'Ballı yedeği' }); setMsg('Yedek paylaşıldı.'); return }
    } catch (e) { if (e.name === 'AbortError') return }
    const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = name; a.click()
    setMsg('Yedek indirildi.')
  }
  const importIt = async (f) => {
    try { const d = await importAll(await f.text()); replace(d); if (d.profile?.name) renameProfile(d.profile.name); setMsg('Yedek yüklendi.') }
    catch (e) { setMsg(e.message || 'Yedek okunamadı. Geçerli bir Ballı yedeği seç.') }
  }
  return (
    <>
    <Card className="divide-y">
      <button className="flex min-h-12 w-full items-center gap-3 px-4 py-3 text-left active:bg-accent" onClick={exportIt}><IconDownload className="size-5" stroke={1.5} /><span className="flex-1 text-sm font-medium">Yedeği dışa aktar</span><span className="text-muted-foreground text-xs">JSON</span></button>
      <button className="flex min-h-12 w-full items-center gap-3 px-4 py-3 text-left active:bg-accent" onClick={() => ref.current?.click()}><IconUpload className="size-5" stroke={1.5} /><span className="flex-1 text-sm font-medium">Yedekten geri yükle</span></button>
      <button className="flex min-h-12 w-full items-center gap-3 px-4 py-3 text-left active:bg-accent" onClick={() => open('backups')}><IconHistory className="size-5" stroke={1.5} /><span className="flex-1 text-sm font-medium">Otomatik yedekler</span><span className="text-muted-foreground text-xs">haftalık</span><IconChevronRight className="text-muted-foreground size-4" /></button>
      {msg && <div className="text-muted-foreground px-4 py-2.5 text-xs" role="status">{msg}</div>}
    </Card>
    <SectionTitle>Tehlikeli bölge</SectionTitle>
    <Card>
      <button className="flex min-h-12 w-full items-center gap-3 px-4 py-3 text-left text-destructive active:bg-accent" onClick={() => setC(true)}>
        <IconRefresh className="size-5" stroke={1.5} /><span className="flex-1 text-sm font-medium">Programları ve kayıtları sıfırla</span>
      </button>
    </Card>
    {c && (
      <Sheet onClose={() => setC(false)} title="Her şey sıfırlansın mı?" description="Programların, antrenman ve beslenme kayıtların, ölçümlerin, besinlerin ve tariflerin silinir. Adın, hedeflerin ve bulut bağlantın kalır. Bu işlem geri alınamaz; önce yedek almanı öneririz."
        footer={(close) => <>
          <Button size="lg" variant="destructive" onClick={() => { reset(); setMsg('Programlar ve kayıtlar sıfırlandı.'); close() }}><IconAlertTriangle />Evet, sıfırla</Button>
          <Button variant="ghost" onClick={close}>Vazgeç</Button>
        </>} />
    )}
    <input ref={ref} type="file" accept="application/json,.json" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) importIt(f); e.target.value = '' }} />
    </>
  )
}

/* ---------- Sheets ---------- */
export function MeasureForm({ onClose, id, quick }) {
  const { withUndo, toast, db, update } = useApp()
  const cur = id ? db.measures.find((m) => m.id === id) : null
  const [f, setF] = React.useState(cur ? { ...cur } : { date: keyOf(new Date()) })
  const last = [...db.measures].sort((a, b) => (a.date < b.date ? 1 : -1))[0] || {}
  const fields = quick ? MF.slice(0, 1) : MF
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(f.date || '')
  const vals = {}
  MF.forEach(([k]) => { if (f[k] !== undefined && f[k] !== '' && f[k] !== null && num(f[k]) > 0) vals[k] = num(f[k]) })
  const canSave = Object.keys(vals).length > 0 || !!cur
  const save = (close) => {
    const v = { id: cur?.id || uid(), date: validDate ? f.date : keyOf(new Date()), ...vals }
    update((d) => {
      const i = cur ? d.measures.findIndex((m) => m.id === cur.id) : -1
      if (i >= 0) d.measures[i] = v
      else { const same = d.measures.find((m) => m.date === v.date); if (same) Object.assign(same, { ...v, id: same.id }); else d.measures.push(v) }
    })
    close(); toast('Ölçüm kaydedildi')
  }
  return (
    <Sheet onClose={onClose} title={cur ? 'Ölçümü düzenle' : quick ? 'Kilo gir' : 'Yeni ölçüm'} footer={(close) => <>
      <Button size="lg" onClick={() => save(close)} disabled={!canSave}>Kaydet</Button>
      {cur && <Button variant="ghost" className="text-destructive" onClick={() => { withUndo('Ölçüm silindi', (d) => { const i = d.measures.findIndex((m) => m.id === cur.id); if (i >= 0) d.measures.splice(i, 1) }); close() }}>Ölçümü sil</Button>}
    </>}>
      <Field label="Tarih" id="ms-d"><Input id="ms-d" type="date" required max={keyOf(new Date())} value={f.date || ''} onChange={(e) => setF({ ...f, date: e.target.value || keyOf(new Date()) })} /></Field>
      <div className={quick ? 'grid' : 'grid grid-cols-2 gap-3'}>
        {fields.map(([k, l, u]) => (
          <Field key={k} label={`${l} (${u})`} id={'ms-' + k}><Input id={'ms-' + k} inputMode="decimal" placeholder={last[k] != null ? String(last[k]) : ''} value={f[k] ?? ''} onChange={(e) => setF((x) => ({ ...x, [k]: e.target.value }))} /></Field>
        ))}
      </div>
    </Sheet>
  )
}

// [alan, etiket, gösterim çarpanı (depolanan = gösterilen × çarpan), üst sınır]
const TF = [['kcal', 'Kalori (kcal)', 1, 10000], ['p', 'Protein (g)', 1, 500], ['c', 'Karbonhidrat (g)', 1, 1000], ['f', 'Yağ (g)', 1, 400], ['water', 'Su hedefi (L)', 1000, 10000], ['waterStep', 'Su ekleme adımı (ml)', 1, 2000], ['steps', 'Günlük adım hedefi', 1, 100000]]
export function SettingsSheet({ onClose }) {
  const { toast, db, update } = useApp()
  const [t, setT] = React.useState(() => Object.fromEntries(TF.map(([k, , m]) => [k, String(+((db.targets[k] ?? (k === 'waterStep' ? 500 : 0)) / m).toFixed(2)).replace('.', ',')])))
  const s = (k) => (e) => setT((x) => ({ ...x, [k]: e.target.value }))
  const [meals, setMeals] = React.useState(() => db.targets.meals?.length ? db.targets.meals : MEALS.map(([k]) => k))
  const toggleMeal = (k) => setMeals((x) => (x.includes(k) ? (x.length > 1 ? x.filter((y) => y !== k) : x) : MEALS.map(([m]) => m).filter((m) => m === k || x.includes(m))))
  const save = (close) => {
    const next = {}
    TF.forEach(([k, , m, max]) => { const v = Math.round(num(t[k]) * m); if (v > 0) next[k] = Math.min(v, max) })
    update((d) => { Object.assign(d.targets, next); d.targets.meals = meals })
    close(); toast('Hedefler kaydedildi')
  }
  return (
    <Sheet onClose={onClose} title="Günlük hedefler" description="Boş ya da 0 bıraktığın alanlar eski değerinde kalır." footer={(close) => <Button size="lg" type="submit" form="st-form">Kaydet</Button>}>
      {(close) => (
        <form id="st-form" className="grid grid-cols-2 gap-3" onSubmit={(e) => { e.preventDefault(); save(close) }}>
          <fieldset className="col-span-2 grid gap-2">
            <legend className="mb-2 text-sm font-medium">Öğünler <span className="text-muted-foreground font-normal">· günde kaç öğün yiyorsan onları seç</span></legend>
            <div className="grid grid-cols-4 gap-2">
              {MEALS.map(([k, l]) => { const on = meals.includes(k); return (
                <button key={k} type="button" role="checkbox" aria-checked={on} onClick={() => toggleMeal(k)}
                  className={cn('press h-11 rounded-full border text-sm font-medium transition-colors', on ? 'bg-foreground text-background border-foreground' : 'bg-card text-muted-foreground dark:border-transparent')}>{l.replace(' öğün', '')}</button>
              ) })}
            </div>
            <p className="text-muted-foreground text-xs">{meals.length === 1 ? 'Tek öğün: eklediğin her şey bu öğüne yazılır.' : `${meals.length} öğün. Kapattığın öğünlerdeki eski kayıtlar silinmez.`}</p>
          </fieldset>
          {TF.map(([k, l]) => <Field key={k} label={l} id={'st-' + k}><Input id={'st-' + k} inputMode="decimal" value={t[k]} onChange={s(k)} /></Field>)}
          <button type="submit" hidden />
        </form>
      )}
    </Sheet>
  )
}

export function GoalsSheet({ onClose }) {
  const { withUndo, toast, db, update } = useApp()
  const [start, setStart] = React.useState(db.profile.startKg ?? '')
  const [goals, setGoals] = React.useState((db.targets.goals || []).map(String))
  const save = (close) => {
    const g = [...new Set(goals.map(num).filter((x) => x > 0))].sort((a, b) => b - a)
    update((d) => { d.profile.startKg = num(start) || null; d.targets.goals = g })
    close()
  }
  return (
    <Sheet onClose={onClose} title="Kilo hedefleri" description="Ara hedefler sırayla takip edilir; birine ulaşınca sıradakine geçilir." footer={(close) => <Button size="lg" onClick={() => save(close)}>Kaydet</Button>}>
      <Field label="Başlangıç kilosu (kg)" id="g-start" hint="Toplam kaybın bu değere göre hesaplanır."><Input id="g-start" inputMode="decimal" value={start} onChange={(e) => setStart(e.target.value)} /></Field>
      <div className="grid gap-2">
        <div className="text-sm font-medium">Hedefler</div>
        {goals.map((g, i) => (
          <div key={i} className="flex items-center gap-2">
            <span className="text-muted-foreground w-16 text-xs">{i + 1}. hedef</span>
            <div className="relative flex-1"><Input inputMode="decimal" value={g} onChange={(e) => setGoals(goals.map((x, j) => (j === i ? e.target.value : x)))} aria-label={`${i + 1}. hedef`} /><span className="text-muted-foreground absolute right-3 top-1/2 -translate-y-1/2 text-xs">kg</span></div>
            <Button variant="ghost" size="icon" onClick={() => setGoals(goals.filter((_, j) => j !== i))} aria-label="Hedefi sil"><IconTrash /></Button>
          </div>
        ))}
        <Button variant="outline" onClick={() => setGoals([...goals, ''])}><IconPlus />Hedef ekle</Button>
      </div>
    </Sheet>
  )
}

export function ProfileFields({ onSubmit, submitLabel, allowTemplate = true }) {
  const [f, setF] = React.useState({ name: '', startKg: '', currentKg: '', goals: [''], kcal: '1800', template: 'blank' })
  const s = (k) => (e) => setF({ ...f, [k]: e.target.value })
  const pos = (v) => (num(v) > 0 ? num(v) : null)
  const submit = (e) => {
    e?.preventDefault?.()
    if (!f.name.trim()) return
    onSubmit({
      name: f.name.trim(), startKg: pos(f.startKg), currentKg: pos(f.currentKg), template: f.template,
      goals: [...new Set(f.goals.map(num).filter((x) => x > 0))].sort((a, b) => b - a), kcal: Math.min(10000, Math.round(num(f.kcal))) || 1800,
    })
  }
  const setGoal = (i, v) => setF({ ...f, goals: f.goals.map((x, j) => (j === i ? v : x)) })
  return (
    <form className="grid gap-4" onSubmit={submit}>
      <Field label="Ad" id="pf-n"><Input id="pf-n" value={f.name} onChange={s('name')} placeholder="ör. Ayşe" /></Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Başlangıç kilosu" id="pf-s"><Input id="pf-s" inputMode="decimal" value={f.startKg} onChange={s('startKg')} placeholder="kg" /></Field>
        <Field label="Şu anki kilo" id="pf-c"><Input id="pf-c" inputMode="decimal" value={f.currentKg} onChange={s('currentKg')} placeholder="kg" /></Field>
      </div>
      <div className="grid gap-2">
        <div className="text-sm font-medium">Kilo hedefleri</div>
        {f.goals.map((g, i) => (
          <div key={i} className="flex items-center gap-2">
            <span className="text-muted-foreground w-16 text-xs">{i + 1}. hedef</span>
            <div className="relative flex-1"><Input inputMode="decimal" value={g} onChange={(e) => setGoal(i, e.target.value)} placeholder={i ? '' : 'ör. 72,5'} aria-label={`${i + 1}. hedef`} /><span className="text-muted-foreground absolute right-3 top-1/2 -translate-y-1/2 text-xs">kg</span></div>
            {f.goals.length > 1 && <Button type="button" variant="ghost" size="icon" className="size-11" onClick={() => setF({ ...f, goals: f.goals.filter((_, j) => j !== i) })} aria-label="Hedefi sil"><IconTrash /></Button>}
          </div>
        ))}
        <Button type="button" variant="outline" onClick={() => setF({ ...f, goals: [...f.goals, ''] })}><IconPlus />Ara hedef ekle</Button>
      </div>
      <Field label="Günlük kalori hedefi" id="pf-k"><Input id="pf-k" inputMode="numeric" value={f.kcal} onChange={s('kcal')} /></Field>
      {allowTemplate && <Field label="Antrenman programı"><TemplateSelect value={f.template} onChange={(v) => setF({ ...f, template: v })} /></Field>}
      <Button size="lg" type="submit" disabled={!f.name.trim()}>{submitLabel}</Button>
    </form>
  )
}

export function ProfileFormSheet({ onClose }) {
  const { createProfile } = useApp()
  return (
    <Sheet onClose={onClose} title="Yeni profil" description="Her profilin programı, günlüğü ve ölçümleri ayrı tutulur." full>
      {(close) => <ProfileFields submitLabel="Profili oluştur" onSubmit={async (o) => { close(); setTimeout(() => createProfile(o), 350) }} />}
    </Sheet>
  )
}

export function Onboarding() {
  const { createProfile } = useApp()
  const [pid] = React.useState(() => Math.random().toString(36).slice(2, 10))
  const [restore, setRestore] = React.useState(false)
  const [cloud, setCloud] = React.useState(null)
  return (
    <div className="mx-auto grid max-w-[520px] gap-6 px-gutter pt-[calc(env(safe-area-inset-top,0px)+32px)] pb-12 screen-enter">
      <div>
        <div className="text-primary text-xs font-medium uppercase tracking-wider">Ballı</div>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight">Hoş geldin</h1>
        <p className="text-muted-foreground mt-1 text-sm">Profilini oluştur; antrenmanların, yediklerin ve ölçümlerin bu cihazda saklanır.</p>
      </div>
      {cloudEnabled && !cloud && (
        <button className="press text-left" onClick={() => setRestore(true)}>
          <Card className="flex items-center gap-3 p-4"><div className="flex-1"><div className="font-medium">Yedeğim var</div><div className="text-muted-foreground text-sm">E-posta ve şifrenle giriş yap, verilerin geri gelsin.</div></div><IconChevronRight className="text-muted-foreground size-5" /></Card>
        </button>
      )}
      {cloud && <p className="text-muted-foreground text-sm">{cloud.email} hesabında yedek bulunamadı; profilini oluştur, otomatik yedeklenecek.</p>}
      <ProfileFields submitLabel="Başla" onSubmit={(o) => createProfile({ ...o, id: pid, cloud })} />
      {restore && <CloudSheet pid={pid} mode="restore" onClose={() => setRestore(false)} onLinked={async (c, remote) => {
        if (remote) await createProfile({ id: pid, data: remote, cloud: c })
        else setCloud(c)
      }} />}
    </div>
  )
}

/* Dropdown görünümlü alan → açılınca kartlı seçim sheet'i */
export function TemplateSelect({ value, onChange }) {
  const [open, setOpen] = React.useState(false)
  const cur = templateFor(value)
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="press min-h-11 dark:bg-input/30 dark:border-transparent border-input flex min-h-10 w-full items-center gap-3 rounded-md border bg-transparent px-3 py-2 text-left shadow-xs">
        <div className="min-w-0 flex-1">
          <div className="text-base">{cur.name}{cur.days ? <span className="text-muted-foreground"> · {cur.days} gün</span> : null}</div>
          <div className="text-muted-foreground truncate text-xs">{cur.who}</div>
        </div>
        <IconSelector className="text-muted-foreground size-4 shrink-0" />
      </button>
      {open && (
        <Sheet onClose={() => setOpen(false)} title="Antrenman programı" description="Seçtiğin program haftalık takvime yerleşir; sonra istediğin gibi düzenleyebilirsin." full>
          {(close) => (
            <div className="grid gap-2">
              {PROGRAM_TEMPLATES.filter((t) => t.onboarding !== false).map((t) => {
                const sel = t.key === value
                return (
                  <button key={t.key} type="button" className="press text-left" onClick={() => { onChange(t.key); close() }}>
                    <Card className={cn('grid gap-2 p-4', sel && 'ring-primary ring-2')}>
                      <div className="flex items-center justify-between gap-2">
                        <div className="font-semibold">{t.name}</div>
                        <div className="flex items-center gap-2">{t.days && <Badge variant="secondary">{t.days} gün / hafta</Badge>}{sel && <IconCheck className="text-primary size-5" />}</div>
                      </div>
                      <div className="grid gap-1 text-sm">
                        <div><span className="text-muted-foreground">Kime uygun: </span>{t.who}</div>
                        <div className="text-muted-foreground text-xs">{t.split}</div>
                      </div>
                    </Card>
                  </button>
                )
              })}
            </div>
          )}
        </Sheet>
      )}
    </>
  )
}

/* ---------- Bulut yedeği ---------- */
const ago = (t) => { if (!t) return ''; const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'az önce' : m < 60 ? `${m} dk önce` : `${Math.round(m / 60)} sa önce` }
function CloudCard() {
  const { db, update, sync, syncNow, activeId, toast } = useApp()
  const [open, setOpen] = React.useState(false)
  const [, tick] = React.useState(0)
  React.useEffect(() => { const t = setInterval(() => tick((x) => x + 1), 30000); return () => clearInterval(t) }, [])
  if (!cloudEnabled) return <Card className="p-4 text-sm"><div className="font-medium">Bulut yedeği hazırlanıyor</div><div className="text-muted-foreground mt-1">Kurulum tamamlanınca buradan e-postanla giriş yapıp verilerini otomatik yedekleyebileceksin.</div></Card>
  if (!db.cloud) return (
    <>
      <Card className="grid gap-3 p-4">
        <div><div className="font-medium">Verilerini kaybetme</div><div className="text-muted-foreground mt-1 text-sm">E-posta ve şifreyle hesap oluştur; programın, günlüğün ve ölçümlerin otomatik yedeklensin. Telefon değişse de geri gelir.</div></div>
        <Button className="h-11" onClick={() => setOpen(true)}>Yedeklemeyi aç</Button>
      </Card>
      {open && <CloudLinkSheet onClose={() => setOpen(false)} />}
    </>
  )
  const label = { syncing: 'Eşitleniyor…', ok: `Yedeklendi · ${ago(sync.at)}`, error: 'Eşitlenemedi, tekrar denenecek', offline: 'İnternet yok, bağlanınca yedeklenecek', idle: 'Hazır' }[sync.status]
  return (
    <Card className="grid gap-3 p-4">
      <div className="flex items-center gap-3">
        <span className={cn('size-2 rounded-full', sync.status === 'error' ? 'bg-destructive' : sync.status === 'syncing' ? 'bg-primary animate-pulse' : 'bg-success')} />
        <div className="min-w-0 flex-1"><div className="truncate text-sm font-medium">{db.cloud.email}</div><div className="text-muted-foreground text-xs">{label}</div></div>
        <Button variant="outline" className="h-11" onClick={syncNow}>Şimdi eşitle</Button>
      </div>
      <Button variant="ghost" className="text-muted-foreground h-11 justify-self-start" onClick={async () => { await signOut(activeId); update((d) => { delete d.cloud }) }}>Bu cihazda yedeklemeyi kapat</Button>
    </Card>
  )
}

/* Herhangi bir ekrandan açılabilen bulut bağlama sheet'i */
export function CloudLinkSheet({ onClose }) {
  const { update, activeId, toast } = useApp()
  return <CloudSheet pid={activeId} mode="link" onClose={onClose} onLinked={async (cloud, remote) => {
    if (remote) { let m; try { m = migrate({ ...remote }) } catch { m = null } if (m) update((d) => { Object.assign(d, m, { cloud, updatedAt: Math.max(m.updatedAt || 0, Date.now()) }) }); else update((d) => { d.cloud = cloud }) }
    else update((d) => { d.cloud = cloud })
    toast('Yedekleme açıldı')
  }} />
}

export function CloudSheet({ pid, mode, onClose, onLinked }) {
  const [step, setStep] = React.useState('form')
  const [kind, setKind] = React.useState(mode === 'restore' ? 'in' : 'up')
  const [email, setEmail] = React.useState('')
  const [pw, setPw] = React.useState('')
  const [busy, setBusy] = React.useState(false)
  const [err, setErr] = React.useState('')
  const [found, setFound] = React.useState(null)
  const validEmail = /.+@.+\..+/.test(email)
  const sendReset = async () => {
    setBusy(true); setErr('')
    try { await requestPasswordReset(pid, email.trim()); setStep('sent') } catch (e) { setErr(e.message) }
    setBusy(false)
  }
  const go = async (close) => {
    setBusy(true); setErr('')
    try {
      const cloud = kind === 'up' ? await signUp(pid, email.trim(), pw) : await signIn(pid, email.trim(), pw)
      const remote = await pullRemote(pid).catch(() => null)
      if (mode === 'link' && remote) { setFound({ cloud, remote }); setStep('choose'); setBusy(false); return }
      await onLinked(cloud, remote); close()
    } catch (e) { setErr(e.message) }
    setBusy(false)
  }
  return (
    <Sheet onClose={onClose} title={step === 'forgot' || step === 'sent' ? 'Şifremi unuttum' : mode === 'restore' ? 'Yedeğimi geri yükle' : 'Bulut yedeği'} description={step === 'form' ? 'Bu e-posta ve şifreyle yeni telefonda verilerini geri alırsın.' : step === 'forgot' ? 'Hesabının e-postasını yaz; şifreni yenilemen için bağlantı gönderelim.' : undefined}>
      {(close) => step === 'forgot' ? (
        <form className="grid gap-4" onSubmit={(e) => { e.preventDefault(); if (!busy && validEmail) sendReset() }}>
          <Field label="E-posta" id="cl-fe"><Input id="cl-fe" type="email" inputMode="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="ornek@mail.com" /></Field>
          {err && <p className="text-destructive text-sm" role="alert">{err}</p>}
          <Button size="lg" type="submit" disabled={busy || !validEmail}><IconMailForward />{busy ? 'Gönderiliyor…' : 'Bağlantı gönder'}</Button>
          <Button type="button" variant="ghost" className="h-11" onClick={() => { setStep('form'); setErr('') }}>Girişe dön</Button>
        </form>
      ) : step === 'sent' ? (
        <div className="grid gap-4" role="status">
          <div className="bg-success/10 text-success grid size-12 place-items-center rounded-full"><IconMailForward /></div>
          <p className="text-sm"><span className="font-medium">{email.trim()}</span> adresine bağlantı gönderdik (spam klasörüne de bak). Bağlantıya bu telefonda dokun; Ballı açılınca yeni şifreni belirlersin.</p>
          <Button size="lg" variant="outline" onClick={() => { setStep('form'); setKind('in') }}>Tamam</Button>
        </div>
      ) : step === 'form' ? (
        <form className="grid gap-4" onSubmit={(e) => { e.preventDefault(); if (!busy && /.+@.+\..+/.test(email) && pw.length >= 6) go(close) }}>
          <Segmented value={kind} onChange={(v) => { setKind(v); setErr('') }} options={[['up', 'Hesap oluştur'], ['in', 'Giriş yap']]} />
          <Field label="E-posta" id="cl-e"><Input id="cl-e" type="email" inputMode="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="ornek@mail.com" /></Field>
          <Field label="Şifre" id="cl-p" hint={kind === 'up' ? 'En az 6 karakter. Unutma; telefon değişince bununla gireceksin.' : undefined}>
            <Input id="cl-p" type="password" autoComplete={kind === 'up' ? 'new-password' : 'current-password'} value={pw} onChange={(e) => setPw(e.target.value)} />
          </Field>
          {err && <p className="text-destructive text-sm" role="alert">{err}</p>}
          <Button size="lg" type="submit" disabled={busy || !validEmail || pw.length < 6}>{busy ? 'Bağlanıyor…' : kind === 'up' ? 'Hesap oluştur ve yedekle' : 'Giriş yap'}</Button>
          {kind === 'in' && <Button type="button" variant="ghost" className="text-muted-foreground h-11" onClick={() => { setStep('forgot'); setErr('') }}>Şifremi unuttum</Button>}
        </form>
      ) : (
        <>
          <p className="text-sm">Bu hesapta daha önce alınmış bir yedek var. Hangisi kullanılsın?</p>
          <Button size="lg" onClick={async () => { await onLinked(found.cloud, found.remote); close() }}>Buluttaki yedeği yükle</Button>
          <Button variant="outline" onClick={async () => { await onLinked(found.cloud, null); close() }}>Bu cihazdakini kullan, bulutu güncelle</Button>
          <Button variant="ghost" className="h-auto min-h-11 whitespace-normal py-2" onClick={async () => { await onLinked({ ...found.cloud, key: `p-${pid}` }, null); close() }}>İkisini de koru: bu profili ayrı yedekle</Button>
          <p className="text-muted-foreground text-xs">Aynı hesabı eşinle kullanıyorsan "İkisini de koru"yu seç; veriler birbirini ezmez.</p>
        </>
      )}
    </Sheet>
  )
}

/* ---------- Profilleri yönet: ad değiştir, sil ---------- */
function ProfilesSheet({ onClose }) {
  const { profiles, renameProfile, deleteProfile, switchProfile, update, toast } = useApp()
  const [edit, setEdit] = React.useState(null) // {id, name}
  const [del, setDel] = React.useState(null)
  const saveName = () => {
    const name = edit.name.trim(); if (!name) return
    renameProfile(name, edit.id)
    if (edit.id === profiles.active) update((d) => { d.profile.name = name })
    setEdit(null); toast('Ad güncellendi')
  }
  return (
    <Sheet onClose={onClose} title={profiles.list.length > 1 ? 'Profiller' : 'Profil adı'} description={profiles.list.length > 1 ? 'Her profilin verisi ayrı tutulur.' : undefined}>
      {(close) => (
        <div className="grid gap-2">
          {profiles.list.map((p) => (
            <Card key={p.id} className="flex items-center gap-2 p-2 pl-4">
              {edit?.id === p.id ? (
                <form className="flex flex-1 items-center gap-2" onSubmit={(e) => { e.preventDefault(); saveName() }}>
                  <Input autoFocus value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} aria-label="Profil adı" />
                  <Button type="submit" size="icon" className="size-11 shrink-0" disabled={!edit.name.trim()} aria-label="Kaydet"><IconCheck /></Button>
                </form>
              ) : (
                <>
                  <button type="button" className="press min-h-11 min-w-0 flex-1 text-left" disabled={p.id === profiles.active} onClick={() => { close(); switchProfile(p.id) }}><div className="truncate font-medium">{p.name || 'Profil'}</div><div className="text-muted-foreground text-xs">{p.id === profiles.active ? 'Şu an açık' : 'Geçmek için dokun'}</div></button>
                  <Button variant="ghost" size="icon" className="size-11" onClick={() => setEdit({ id: p.id, name: p.name || '' })} aria-label={`${p.name} adını değiştir`}><IconPencil /></Button>
                  {profiles.list.length > 1 && <Button variant="ghost" size="icon" className="text-destructive size-11" onClick={() => setDel(p)} aria-label={`${p.name} profilini sil`}><IconTrash /></Button>}
                </>
              )}
            </Card>
          ))}
          {del && (
            <Card className="grid gap-3 p-4">
              <div className="text-sm"><span className="font-medium">{del.name}</span> profili ve bu cihazdaki bütün verisi silinsin mi? Bulut yedeği varsa orada kalır.</div>
              <div className="grid grid-cols-2 gap-2">
                <Button variant="outline" onClick={() => setDel(null)}>Vazgeç</Button>
                <Button variant="destructive" onClick={async () => { const last = profiles.list.length === 1; setDel(null); if (last) close(); await deleteProfile(del.id); toast('Profil silindi') }}>Sil</Button>
              </div>
            </Card>
          )}
        </div>
      )}
    </Sheet>
  )
}

/* ---------- Şifre sıfırlama bağlantısından dönünce ---------- */
export function NewPasswordSheet({ onClose, email }) {
  const { activeId, toast } = useApp()
  const [pw, setPw] = React.useState('')
  const [pw2, setPw2] = React.useState('')
  const [busy, setBusy] = React.useState(false)
  const [err, setErr] = React.useState('')
  const ok = pw.length >= 6 && pw === pw2
  return (
    <Sheet onClose={onClose} title="Yeni şifre belirle" description={email ? `${email} hesabı için yeni şifreni yaz.` : 'Hesabın için yeni şifreni yaz.'}>
      {(close) => (
        <form className="grid gap-4" onSubmit={async (e) => {
          e.preventDefault(); if (!ok || busy) return
          setBusy(true); setErr('')
          try { await updatePassword(activeId, pw); toast('Şifren güncellendi'); close() } catch (x) { setErr(x.message || 'Şifre güncellenemedi. Tekrar dene.') }
          setBusy(false)
        }}>
          <Field label="Yeni şifre" id="np-1" hint="En az 6 karakter."><Input id="np-1" type="password" autoComplete="new-password" value={pw} onChange={(e) => setPw(e.target.value)} /></Field>
          <Field label="Yeni şifre (tekrar)" id="np-2"><Input id="np-2" type="password" autoComplete="new-password" value={pw2} onChange={(e) => setPw2(e.target.value)} /></Field>
          {pw2 && pw !== pw2 && <p className="text-destructive text-sm">Şifreler aynı değil.</p>}
          {err && <p className="text-destructive text-sm" role="alert">{err}</p>}
          <Button size="lg" type="submit" disabled={!ok || busy}><IconKey />{busy ? 'Kaydediliyor…' : 'Şifreyi kaydet'}</Button>
        </form>
      )}
    </Sheet>
  )
}

/* ---------- Otomatik yerel yedekler (haftalık, son 4) ---------- */
const ABK = (pid) => `balli-autobackup:${pid}`
const WEEK = 7 * 864e5
export async function autoBackup(pid, db, force = false) {
  if (!pid || !db) return
  try {
    const list = (await idbGet(ABK(pid))) || []
    const autos = list.filter((b) => !b.manual), manuals = list.filter((b) => b.manual)
    if (!force && autos.length && Date.now() - (autos.at(-1).at || 0) < WEEK) return
    const json = JSON.stringify({ app: 'balli', exportedAt: new Date().toISOString(), db })
    const item = { at: Date.now(), json, ...(force ? { manual: true } : {}) }
    // haftalık otomatik (son 4) ve elle alınan (son 3) yedekler ayrı tutulur; biri diğerini silmez
    const next = force ? [...autos.slice(-4), ...[...manuals, item].slice(-3)] : [...[...autos, item].slice(-4), ...manuals.slice(-3)]
    await idbSet(ABK(pid), next.sort((a, b) => a.at - b.at))
  } catch {}
}
const kb = (n) => (n > 1048576 ? `${fmt1(n / 1048576)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`)
export function AutoBackupsSheet({ onClose }) {
  const { activeId, db, replace, renameProfile, toast } = useApp()
  const [list, setList] = React.useState(null)
  const [ask, setAsk] = React.useState(null)
  const load = React.useCallback(() => idbGet(ABK(activeId)).then((l) => setList((l || []).slice().reverse())).catch(() => setList([])), [activeId])
  React.useEffect(() => { load() }, [load])
  const restore = async (b) => {
    try {
      const j = JSON.parse(b.json); const d = j?.db ?? j
      replace(migrate(d)); if (d.profile?.name) renameProfile(d.profile.name)
      toast('Yedek geri yüklendi'); setAsk(null)
    } catch { toast('Bu yedek okunamadı') }
  }
  const download = async (b) => {
    const name = `balli-otomatik-${keyOf(new Date(b.at))}.json`
    const file = new File([b.json], name, { type: 'application/json' })
    try { if (navigator.canShare?.({ files: [file] })) { await navigator.share({ files: [file], title: 'Ballı yedeği' }); return } } catch (e) { if (e.name === 'AbortError') return }
    const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = name; a.click()
  }
  return (
    <Sheet onClose={onClose} title="Otomatik yedekler" description="Ballı haftada bir bu cihaza yedek alır, son 4'ünü saklar. Görseller bu yedeklere dahil değildir.">
      {list == null ? null : (
        <div className="grid gap-2">
          {list.length === 0 && <Empty icon={IconHistory} title="Henüz otomatik yedek yok">İlk yedek bu hafta içinde alınacak. İstersen şimdi al.</Empty>}
          {list.map((b) => (
            <Card key={b.at} className="grid gap-3 p-4">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0"><div className="font-medium">{longDate(keyOf(new Date(b.at)))}</div><div className="text-muted-foreground text-xs tabular">{new Date(b.at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })} · {kb(b.json.length)}{b.manual ? ' · elle' : ' · haftalık'}</div></div>
              </div>
              {ask === b.at ? (
                <div className="grid gap-2">
                  <p className="text-sm">Şu anki verilerin bu yedekle değişsin mi? Önce dışa aktararak yedek almanı öneririz.</p>
                  <div className="grid grid-cols-2 gap-2"><Button variant="outline" className="h-11" onClick={() => setAsk(null)}>Vazgeç</Button><Button className="h-11" onClick={() => restore(b)}>Evet, geri yükle</Button></div>
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="outline" className="h-11" onClick={() => download(b)}><IconDownload />İndir</Button>
                  <Button variant="outline" className="h-11" onClick={() => setAsk(b.at)}><IconUpload />Geri yükle</Button>
                </div>
              )}
            </Card>
          ))}
          <Button variant="ghost" className="h-11" onClick={async () => { await autoBackup(activeId, db, true); load(); toast('Yedek alındı') }}><IconPlus />Şimdi yedek al</Button>
        </div>
      )}
    </Sheet>
  )
}
