import * as React from 'react'
import { IconHome, IconBarbell, IconToolsKitchen2, IconUserCircle } from '@tabler/icons-react'
import { AppProvider, useApp } from '@/lib/store'
import { cn, haptic } from '@/lib/utils'
import { Toasts } from '@/components/ui'
import Today from '@/screens/Today'
import Nutrition, { EntrySheet, AddFoodSheet, CheatSheet, FoodEditSheet, RecipeSheet, RecipeForm, TemplateForm } from '@/screens/Nutrition'
import { cloudEnabled, consumeRecovery, reportError } from '@/lib/cloud'
import { keyOf } from '@/lib/utils'

// Antrenman, Profil ve Seans ilk açılışta yüklenmez; boşta önceden yüklenir (ana paket küçülür)
const loadWorkout = () => import('@/screens/Workout')
const loadProfile = () => import('@/screens/Profile')
const loadSession = () => import('@/screens/Session')
const lz = (load, name = 'default') => React.lazy(() => load().then((m) => ({ default: m[name] })))
const Workout = lz(loadWorkout), Profile = lz(loadProfile), Onboarding = lz(loadProfile, 'Onboarding'), Session = lz(loadSession)

const SHEETS = {
  exercise: lz(loadWorkout, 'ExerciseSheet'), exForm: lz(loadWorkout, 'ExForm'), exPicker: lz(loadWorkout, 'ExercisePicker'), blockForm: lz(loadWorkout, 'BlockForm'),
  programs: lz(loadWorkout, 'ProgramsSheet'), programEdit: lz(loadWorkout, 'ProgramEditSheet'), pickProgram: lz(loadWorkout, 'PickProgramSheet'),
  entry: EntrySheet, addFood: AddFoodSheet, cheat: CheatSheet, foodEdit: FoodEditSheet, recipe: RecipeSheet, recipeForm: RecipeForm, tplForm: TemplateForm,
  measure: lz(loadProfile, 'MeasureForm'), settings: lz(loadProfile, 'SettingsSheet'), goals: lz(loadProfile, 'GoalsSheet'), profileForm: lz(loadProfile, 'ProfileFormSheet'),
  cloud: lz(loadProfile, 'CloudLinkSheet'), newPassword: lz(loadProfile, 'NewPasswordSheet'), backups: lz(loadProfile, 'AutoBackupsSheet'),
}
const idle = (fn) => (window.requestIdleCallback ? requestIdleCallback(fn, { timeout: 2500 }) : setTimeout(fn, 1200))

/* Uygulama geneli arka plan işleri: kalıcı depolama, haftalık yedek, şifre sıfırlama dönüşü, Sağlık adımları */
function useBackgroundJobs() {
  const { db, activeId, update, open, toast } = useApp()
  const dbRef = React.useRef(db); dbRef.current = db
  const ready = !!db
  React.useEffect(() => { navigator.storage?.persist?.().catch?.(() => {}) }, [])
  React.useEffect(() => { // modülleri boşta önceden yükle
    if (!ready) return
    idle(() => { loadWorkout(); loadProfile(); loadSession() })
  }, [ready])
  React.useEffect(() => { // haftalık otomatik yedek
    if (!ready || !activeId) return
    const t = setTimeout(() => loadProfile().then((m) => m.autoBackup(activeId, dbRef.current)).catch(() => {}), 4000)
    return () => clearTimeout(t)
  }, [ready, activeId])
  React.useEffect(() => { // e-postadaki şifre sıfırlama bağlantısı
    if (!ready || !activeId || !cloudEnabled) return
    const h = location.hash
    if (/error_code=|error=/.test(h)) { history.replaceState(null, '', location.pathname); toast('Bağlantının süresi dolmuş, yeniden iste'); return }
    if (!/type=recovery/.test(h)) return
    consumeRecovery(activeId).then((email) => email !== null && open('newPassword', { email })).catch((e) => toast(e.message || 'Bağlantı geçersiz'))
  }, [ready, activeId]) // eslint-disable-line
  const cloudOn = !!db?.cloud
}
const TABS = [['today', 'Bugün', IconHome], ['workout', 'Antrenman', IconBarbell], ['food', 'Beslenme', IconToolsKitchen2], ['profile', 'Profil', IconUserCircle]]
const SCREENS = { today: Today, workout: Workout, food: Nutrition, profile: Profile }

function Shell() {
  const [upd, setUpd] = React.useState(() => !!window.__balliUpdate?.ready)
  React.useEffect(() => { const f = () => setUpd(!!window.__balliUpdate?.ready); window.addEventListener('balli-update', f); return () => window.removeEventListener('balli-update', f) }, [])
  const { db, tab, setTab, sheets, closeSheet, session, toasts } = useApp()
  useBackgroundJobs()
  const scroll = React.useRef({})
  const mainRef = React.useRef(null)
  const go = (t) => {
    haptic()
    if (t === tab) return mainRef.current?.scrollTo({ top: 0, behavior: 'smooth' })
    scroll.current[tab] = mainRef.current?.scrollTop || 0
    setTab(t)
    requestAnimationFrame(() => mainRef.current?.scrollTo(0, scroll.current[t] || 0))
  }
  const onScroll = (e) => e.currentTarget.classList.toggle('scrolled', e.currentTarget.scrollTop > 4)
  React.useEffect(() => {
    const mq = matchMedia('(prefers-color-scheme: dark)')
    const on = () => loadProfile().then(({ applyTheme }) => { try { if (JSON.parse(localStorage.getItem('balli-theme') || '"system"') === 'system') applyTheme('system') } catch { applyTheme('system') } })
    mq.addEventListener('change', on); return () => mq.removeEventListener('change', on)
  }, [])
  if (!db) return <div className="h-dvh overflow-y-auto"><React.Suspense fallback={null}><Onboarding /></React.Suspense></div>
  const Screen = SCREENS[tab]
  return (
    <div className="app-shell">
      <main ref={mainRef} key={tab} onScroll={onScroll} className="app-scroll stagger">
        <div className={cn('mx-auto max-w-[520px] px-gutter', session?.minimized ? 'pb-48' : 'pb-28')}><React.Suspense fallback={null}><Screen /></React.Suspense></div>
      </main>
      <div className="bottom-fade" aria-hidden />
      <nav aria-label="Sekmeler" className="glass-tabbar">
        <div className="glass-pill">
          <span aria-hidden className="glass-indicator" style={{ transform: `translateX(calc(${TABS.findIndex((x) => x[0] === tab)} * 100%))` }} />
          {TABS.map(([k, l, I]) => (
            <button key={k} onClick={() => go(k)} aria-current={tab === k ? 'page' : undefined}
              className={cn('relative z-10 flex flex-col items-center justify-center gap-0.5 rounded-full py-1.5 text-[11px] font-medium transition-colors duration-200', tab === k ? 'text-foreground font-semibold' : 'text-foreground/70 active:text-foreground')}>
              <span className="relative">
                <I key={tab === k ? 'on' : 'off'} className={cn('size-[22px]', tab === k && 'tab-bounce text-primary')} stroke={tab === k ? 2 : 1.6} />
                {k === 'profile' && ((cloudEnabled && !db.cloud) || upd) && <span className="bg-primary ring-background absolute -right-0.5 -top-0.5 size-2 rounded-full ring-2" />}
              </span>{l}{k === 'profile' && upd && <span className="sr-only"> (yeni sürüm hazır)</span>}{k === 'profile' && cloudEnabled && !db.cloud && <span className="sr-only"> (bulut yedeği kapalı)</span>}
            </button>
          ))}
        </div>
      </nav>
      <Toasts items={toasts} top={sheets.length > 0 || (!!session && !session.minimized)} />
      <React.Suspense fallback={null}>
        {session && <Session key={`${session.pid}-${session.date}`} />}{(window.__balliSession = !!session) && null}
        {sheets.map((s) => { const C = SHEETS[s.kind]; return C ? <C key={s.key} {...s.props} onClose={() => closeSheet(s.key)} /> : null })}
      </React.Suspense>
    </div>
  )
}

/* Beklenmeyen bir render hatasında beyaz ekran yerine kurtarma ekranı */
class ErrorBoundary extends React.Component {
  state = { err: null, msg: '' }
  static getDerivedStateFromError(err) { return { err } }
  componentDidCatch(err, info) { try { console.error('[Ballı]', err, info?.componentStack); reportError(err?.message || err, (err?.stack || '') + (info?.componentStack || '')) } catch {} }
  download = async () => {
    try {
      const { get, keys } = await import('idb-keyval')
      const P = await get('balli-profiles')
      const all = {}
      for (const k of await keys()) if (typeof k === 'string' && k.startsWith('balli-db')) all[k] = await get(k)
      const active = P?.active ? all[`balli-db-v2:${P.active}`] : Object.values(all)[0]
      const text = JSON.stringify({ app: 'balli', exportedAt: new Date().toISOString(), db: active || null, profiles: P || null, all })
      const name = `balli-kurtarma-${new Date().toISOString().slice(0, 10)}.json`
      const file = new File([text], name, { type: 'application/json' })
      try { if (navigator.canShare?.({ files: [file] })) { await navigator.share({ files: [file], title: 'Ballı yedeği' }); return } } catch (e) { if (e.name === 'AbortError') return }
      const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = name; a.click()
      this.setState({ msg: 'Yedek indirildi.' })
    } catch { this.setState({ msg: 'Yedek alınamadı.' }) }
  }
  render() {
    if (!this.state.err) return this.props.children
    return (
      <div role="alert" className="mx-auto grid h-dvh max-w-[520px] content-center gap-4 px-gutter text-center">
        <div className="text-primary text-xs font-medium uppercase tracking-wider">Ballı</div>
        <h1 className="text-2xl font-semibold tracking-tight">Bir şeyler ters gitti</h1>
        <p className="text-muted-foreground text-sm">Verilerin cihazında duruyor. Önce yeniden yüklemeyi dene; sorun sürerse yedeği indirip bize gönderebilirsin.</p>
        <button className="btn-primary-glow bg-primary text-primary-foreground h-12 rounded-full px-6 font-medium" onClick={() => location.reload()}>Yeniden yükle</button>
        <button className="border h-12 rounded-full px-6 font-medium" onClick={this.download}>Yedeği indir</button>
        {this.state.msg && <p className="text-muted-foreground text-xs" role="status">{this.state.msg}</p>}
        <details className="text-muted-foreground text-left text-xs"><summary>Hata ayrıntısı</summary><pre className="mt-2 whitespace-pre-wrap break-words">{String(this.state.err?.message || this.state.err)}</pre></details>
      </div>
    )
  }
}

// Yakalanmamış hatalar (kişisel veri gönderilmez)
if (typeof window !== 'undefined' && !window.__balliErr) {
  window.__balliErr = true
  window.addEventListener('error', (e) => { if (e?.message) reportError(e.message, e.error?.stack) })
  window.addEventListener('unhandledrejection', (e) => { const r = e?.reason; if (r && !/fetch|network|load failed/i.test(String(r?.message || r))) reportError(r?.message || String(r), r?.stack) })
}

export default function App() { return <ErrorBoundary><AppProvider><Shell /></AppProvider></ErrorBoundary> }
