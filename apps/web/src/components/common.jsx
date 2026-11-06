import * as React from 'react'
import { cn, DAYS, todayIdx, fmt } from '@/lib/utils'

export function Header({ eyebrow, title, sub, actions }) {
  const ref = React.useRef(null)
  React.useLayoutEffect(() => {
    const el = ref.current; if (!el) return
    const set = () => document.documentElement.style.setProperty('--hdr', `${el.offsetHeight}px`)
    set(); const ro = new ResizeObserver(set); ro.observe(el); return () => ro.disconnect()
  }, [])
  return (
    <header ref={ref} className="navbar progressive-top sticky top-0 z-20 -mx-[max(16px,env(safe-area-inset-left,0px))] flex items-end justify-between gap-3 border-b border-transparent px-gutter pt-[calc(env(safe-area-inset-top,0px)+12px)] pb-3">
      <div className="min-w-0">
        {eyebrow && <div className="text-muted-foreground text-xs font-medium uppercase tracking-wider">{eyebrow}</div>}
        <h1 className="mt-1 text-[28px] font-semibold leading-tight tracking-tight text-balance">{title}</h1>
        {sub && <div className="text-muted-foreground mt-0.5 text-sm tabular">{sub}</div>}
      </div>
      {actions && <div className="flex shrink-0 gap-2">{actions}</div>}
    </header>
  )
}

// status(i): 'done' tamamlandı (yeşil tik) · 'todo' planlı, yapılmadı (gri) · 'rest' off gün (boş halka)
const DayMark = ({ state, sel }) => state === 'done' ? (
  <span className="bg-success grid size-3.5 place-items-center rounded-full text-white"><svg viewBox="0 0 24 24" className="size-2.5" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg></span>
) : state === 'todo' ? <span className={cn('block size-3.5 rounded-full', sel ? 'bg-background/35' : 'bg-foreground/25')} />
  : <span className={cn('block size-3.5 rounded-full border-[1.5px]', sel ? 'border-background/45' : 'border-foreground/30')} />
const MARK_LABEL = { done: 'tamamlandı', todo: 'yapılmadı', rest: 'off' }

export function DayStrip({ value, onChange, label, status, todayIndex }) {
  const t = todayIndex ?? todayIdx()
  return (
    <div className="progressive-top sticky top-[var(--hdr,0px)] z-10 -mx-[max(16px,env(safe-area-inset-left,0px))] px-gutter py-2">
      <div className="grid grid-cols-7 gap-[3px]">
        {DAYS.map((d, i) => {
          const sel = i === value
          return (
            <button
              key={d}
              onClick={() => onChange(i)}
              aria-pressed={sel}
              aria-label={`${d}, ${label?.(i) && label(i) !== '–' ? label(i) : 'antrenman yok'}${status ? `, ${MARK_LABEL[status(i)]}` : ''}`}
              className={cn(
                'press relative flex h-[76px] min-w-0 flex-col items-center justify-center gap-0.5 border px-0 rounded-2xl',
                sel ? 'bg-foreground text-background border-foreground' : 'bg-card dark:border-transparent',
                !sel && i === t && 'border-primary dark:border-primary'
              )}
            >
              {status && <span aria-hidden className="mb-0.5 block"><DayMark state={status(i)} sel={sel} /></span>}
              <span className="text-[13px] font-semibold">{d}</span>
              {(() => {
                const l = label?.(i) || '–'; const rest = l === '–'
                return (
                  <span className={cn('line-clamp-2 block w-full px-0 text-center text-[10px] leading-[1.15] tracking-[-0.02em] [overflow-wrap:anywhere]', sel ? (rest ? 'text-background/60' : 'text-background/85') : rest ? 'text-muted-foreground/70' : 'text-muted-foreground')}>
                    {rest ? '–' : (() => { const m = l.match(/^(.*\S)\s([A-D1-9])$/); return m ? <>{m[1]}<span className="hidden min-[375px]:inline"> {m[2]}</span></> : l })()}
                  </span>
                )
              })()}
            </button>
          )
        })}
      </div>
    </div>
  )
}

export function Ring({ value, size = 56, stroke = 5, children, className, linear }) {
  const r = (size - stroke) / 2, C = 2 * Math.PI * r
  return (
    <div className={cn('relative grid shrink-0 place-items-center', className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--muted)" strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--primary)" strokeWidth={stroke} strokeDasharray={C} strokeDashoffset={C * (1 - Math.min(1, value))} style={{ transition: linear ? 'stroke-dashoffset .25s linear' : 'stroke-dashoffset .6s cubic-bezier(.32,.72,0,1)' }} />
      </svg>
      <div className="absolute inset-0 grid place-items-center">{children}</div>
    </div>
  )
}

export function MacroRow({ eat, plan, compact }) {
  const rows = [['Protein', 'p', 'bg-primary'], ['Karb.', 'c', 'bg-chart-2'], ['Yağ', 'f', 'bg-chart-4']]
  return (
    <div className={cn('grid grid-cols-3', compact ? 'gap-3' : 'gap-4')}>
      {rows.map(([l, k, bg]) => (
        <div key={k} className="min-w-0">
          <div className="text-muted-foreground flex items-center gap-1.5 text-xs"><span className={cn('size-2 rounded-full', bg)} />{l}</div>
          <div className="mt-1 text-base font-semibold tabular"><AnimatedNumber value={eat[k]} /><span className="text-muted-foreground text-xs font-normal"> / {fmt(plan[k])} g</span></div>
          <div className="bg-muted mt-1.5 h-1 overflow-hidden rounded-full"><div className={cn('h-full transition-all duration-500', bg)} style={{ width: `${Math.min(100, (eat[k] / (plan[k] || 1)) * 100)}%` }} /></div>
        </div>
      ))}
    </div>
  )
}

export const Stat = ({ label, value, unit, className }) => (
  <div className={cn('min-w-0', className)}>
    <div className="text-muted-foreground text-xs">{label}</div>
    <div className="mt-0.5 text-lg font-semibold tabular">{value}{unit && <span className="text-muted-foreground text-xs font-normal"> {unit}</span>}</div>
  </div>
)

export function Stepper({ value, onChange, step = 1, min = 0, suffix }) {
  return (
    <div className="flex h-11 items-stretch border rounded-full overflow-hidden bg-background/60 dark:border-transparent dark:bg-input/30">
      <button className="press w-11 text-lg" onClick={() => onChange(Math.max(min, +(value - step).toFixed(2)))} aria-label="Azalt">−</button>
      <div className="grid flex-1 place-items-center border-x text-sm font-medium tabular">{value}{suffix}</div>
      <button className="press w-11 text-lg" onClick={() => onChange(+(value + step).toFixed(2))} aria-label="Artır">+</button>
    </div>
  )
}

/* Hareket görseli: başlangıç ↔ bitiş pozisyonu sırayla oynar */
import { mediaFor } from '@/lib/media'
export function ExerciseMedia({ name, className, interval = 1100 }) {
  const m = mediaFor(name)
  const [i, setI] = React.useState(0)
  React.useEffect(() => {
    if (!m || m.imgs.length < 2) return
    const t = setInterval(() => setI((x) => (x + 1) % m.imgs.length), interval)
    return () => clearInterval(t)
  }, [name]) // eslint-disable-line
  if (!m) return null
  return (
    <div className={cn('relative aspect-[3/2] overflow-hidden rounded-lg border bg-white dark:border-transparent dark:bg-[oklch(0.92_0_0)]', className)}>
      {m.imgs.map((src, k) => (
        <img key={k} src={src} decoding="async" alt={k ? `${name} bitiş pozisyonu` : `${name} başlangıç pozisyonu`} className="absolute inset-0 size-full object-contain transition-opacity duration-300" style={{ opacity: k === i ? 1 : 0 }} />
      ))}
    </div>
  )
}
export function ExerciseThumb({ name, className }) {
  const m = mediaFor(name)
  return m ? <img src={m.imgs[0]} alt="" loading="lazy" decoding="async" className={cn('size-14 shrink-0 rounded-md border bg-white object-cover dark:border-transparent dark:brightness-90', className)} />
    : <div className={cn('bg-muted size-14 shrink-0 rounded-md', className)} />
}

/* Sayı değişince yumuşakça sayar (iOS Activity gibi) */
export function AnimatedNumber({ value, format = (n) => Math.round(n).toLocaleString('tr-TR') }) {
  const [shown, setShown] = React.useState(value)
  const from = React.useRef(value)
  React.useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) { setShown(value); from.current = value; return }
    const a = from.current, b = value, t0 = performance.now(), D = 450
    if (a === b) return
    let raf
    const step = (t) => {
      const k = Math.min(1, (t - t0) / D), e = 1 - Math.pow(1 - k, 3)
      setShown(a + (b - a) * e)
      if (k < 1) raf = requestAnimationFrame(step); else from.current = b
    }
    raf = requestAnimationFrame(step)
    return () => { cancelAnimationFrame(raf); from.current = value }
  }, [value])
  return <>{format(shown)}</>
}
