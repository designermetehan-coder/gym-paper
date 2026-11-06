import * as React from 'react'
import { cva } from 'class-variance-authority'
import { Drawer as V } from 'vaul'
import { IconAlertCircle, IconCheck, IconX, IconTrash } from '@tabler/icons-react'
import { cn } from '@/lib/utils'

/* shadcn/ui (vega) — mobil dokunma hedefleri için hafifçe büyütüldü */

export const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full text-sm font-medium transition-all disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] active:scale-[.97]",
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground btn-primary-glow active:bg-primary/90',
        destructive: 'bg-destructive text-white shadow-xs active:bg-destructive/90',
        outline: 'border bg-background/60 backdrop-blur-md shadow-xs active:bg-accent dark:bg-input/30 dark:border-input',
        secondary: 'bg-secondary text-secondary-foreground shadow-xs active:bg-secondary/80',
        ghost: 'active:bg-accent active:text-accent-foreground',
        link: 'text-primary underline-offset-4 underline',
      },
      size: {
        default: 'h-11 px-4 py-2 has-[>svg]:px-3',
        sm: 'h-8 gap-1.5 px-3 has-[>svg]:px-2.5',
        lg: 'h-12 px-6 text-base has-[>svg]:px-4',
        icon: 'size-10',
        'icon-sm': 'size-9 relative after:absolute after:-inset-1 after:content-[""]',
      },
    },
    defaultVariants: { variant: 'default', size: 'default' },
  }
)
export const Button = React.forwardRef(({ className, variant, size, ...p }, ref) => (
  <button ref={ref} className={cn(buttonVariants({ variant, size }), className)} {...p} />
))

export const Card = ({ className, ...p }) => (
  <div className={cn('bg-card text-card-foreground border shadow-xs rounded-lg dark:border-transparent dark:shadow-none', className)} {...p} />
)

const badgeVariants = cva(
  'inline-flex items-center justify-center rounded-full border px-2 py-0.5 text-xs font-medium w-fit whitespace-nowrap shrink-0 gap-1 [&>svg]:size-3',
  {
    variants: {
      variant: {
        default: 'border-transparent bg-primary text-primary-foreground',
        secondary: 'border-transparent bg-secondary text-secondary-foreground',
        outline: 'text-foreground',
        soft: 'border-transparent bg-primary/12 text-primary',
        success: 'border-transparent bg-success/15 text-success',
      },
    },
    defaultVariants: { variant: 'default' },
  }
)
export const Badge = ({ className, variant, ...p }) => <span className={cn(badgeVariants({ variant }), className)} {...p} />

export const Input = React.forwardRef(({ className, ...p }, ref) => (
  <input
    ref={ref}
    className={cn(
      'placeholder:text-muted-foreground selection:bg-primary selection:text-primary-foreground dark:bg-input/30 dark:border-transparent border-input flex h-10 w-full min-w-0 rounded-md border bg-transparent px-3 py-1 text-base shadow-xs transition-[color,box-shadow] outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px] tabular',
      className
    )}
    {...p}
  />
))
export const Textarea = ({ className, ...p }) => (
  <textarea
    className={cn(
      'placeholder:text-muted-foreground dark:bg-input/30 dark:border-transparent border-input flex min-h-20 w-full rounded-md border bg-transparent px-3 py-2 text-base shadow-xs outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]',
      className
    )}
    {...p}
  />
)
export const NativeSelect = ({ className, children, ...p }) => (
  <div className="relative">
    <select
      className={cn(
        'dark:bg-input/30 dark:border-transparent border-input h-10 w-full appearance-none rounded-md border bg-transparent pl-3 pr-8 text-base shadow-xs outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]',
        className
      )}
      {...p}
    >
      {children}
    </select>
    <svg className="pointer-events-none absolute right-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="m6 9 6 6 6-6" /></svg>
  </div>
)
export const Label = ({ className, ...p }) => <label className={cn('text-sm font-medium leading-none', className)} {...p} />
export const Field = ({ label, id, hint, children }) => (
  <div className="grid gap-2">
    {label && <Label htmlFor={id}>{label}</Label>}
    {children}
    {hint && <p className="text-muted-foreground text-xs">{hint}</p>}
  </div>
)

export const Checkbox = ({ checked, className, ...p }) => (
  <span
    aria-hidden="true"
    data-state={checked ? 'checked' : 'unchecked'}
    className={cn(
      'grid size-5 shrink-0 place-items-center rounded-[7px] border border-input shadow-xs transition-[background-color,border-color] duration-150 dark:bg-input/30 data-[state=checked]:animate-[pop_.28s_cubic-bezier(.34,1.56,.64,1)] data-[state=checked]:bg-primary data-[state=checked]:border-primary data-[state=checked]:text-primary-foreground',
      className
    )}
    {...p}
  >
    {checked && <svg viewBox="0 0 24 24" className="size-3.5 check-draw" fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>}
  </span>
)

export const Progress = ({ value = 0, className, indicator }) => (
  <div className={cn('bg-primary/15 relative h-1.5 w-full overflow-hidden rounded-full', className)}>
    <div className={cn('bg-primary h-full transition-all duration-500', indicator)} style={{ width: `${Math.min(100, Math.max(0, value))}%` }} />
  </div>
)
export const Separator = ({ className }) => <div className={cn('bg-border h-px w-full shrink-0', className)} />

export function Segmented({ value, onChange, options, className }) {
  return (
    <div className={cn('bg-foreground/[0.07] text-foreground/70 inline-flex h-11 w-full items-center p-[3px] rounded-full dark:bg-input/30 dark:text-muted-foreground', className)} role="radiogroup">
      {options.map(([v, l]) => (
        <button
          key={String(v)}
          type="button"
          role="radio"
          aria-checked={value === v}
          onClick={() => onChange(v)}
          className={cn(
            'inline-flex h-full flex-1 items-center justify-center gap-1.5 rounded-full px-2 text-sm font-medium whitespace-nowrap transition-all',
            value === v && 'bg-background text-foreground shadow-[0_1px_3px_rgb(0_0_0/.12),inset_0_1px_0_rgb(255_255_255/.4)] dark:bg-input/40 dark:shadow-[inset_0_1px_0_rgb(255_255_255/.08)]'
          )}
        >
          {l}
        </button>
      ))}
    </div>
  )
}

/* Drawer (vaul) — iOS sheet hissi: sürükleyerek kapanır, arka plan ölçeklenir */
export function Sheet({ title, description, onClose, children, footer, full }) {
  const [open, setOpen] = React.useState(true)
  const close = React.useCallback(() => setOpen(false), [])
  // Kontrollü kapanışta vaul onAnimationEnd çağırmıyor: animasyon bitince onClose'u biz çağırırız (bir kez)
  const closedRef = React.useRef(false)
  const onCloseRef = React.useRef(onClose); onCloseRef.current = onClose
  const finish = React.useCallback(() => { if (closedRef.current) return; closedRef.current = true; onCloseRef.current?.() }, [])
  React.useEffect(() => { if (open) return; const t = setTimeout(finish, 420); return () => clearTimeout(t) }, [open, finish])
  return (
    <V.Root open={open} onOpenChange={(o) => !o && setOpen(false)} onAnimationEnd={(o) => !o && finish()} repositionInputs={false}>
      <V.Portal>
        <V.Overlay className="fixed inset-0 z-50 bg-black/50 dark:bg-black/70" />
        <V.Content
          aria-describedby={undefined}
          onPointerDownOutside={(e) => { if (e.target?.closest?.('[data-toast]')) e.preventDefault() }}
          onInteractOutside={(e) => { if (e.target?.closest?.('[data-toast]')) e.preventDefault() }}
          className={cn(
            'bg-background/90 dark:bg-[oklch(0.2_0_0/.96)] fixed inset-x-0 bottom-0 z-50 mx-auto flex max-w-[520px] flex-col rounded-t-[28px] border-t outline-none backdrop-blur-2xl backdrop-saturate-150 shadow-[0_-10px_40px_-12px_rgb(0_0_0/.35),inset_0_1px_0_rgb(255_255_255/.12)]',
            full ? 'h-[92dvh]' : 'max-h-[88dvh]'
          )}
        >
          <div className="bg-foreground/20 mx-auto mt-2.5 h-[5px] w-10 shrink-0 rounded-full" />
          <div className="flex items-start justify-between gap-3 px-gutter pt-3 pb-2">
            <div className="min-w-0">
              <V.Title className="text-foreground text-lg font-semibold leading-tight line-clamp-2 [overflow-wrap:anywhere]">{title}</V.Title>
              {description && <V.Description className="text-muted-foreground mt-1 text-sm">{description}</V.Description>}
            </div>
            <Button variant="ghost" size="icon" className="-mr-2 -mt-1.5 shrink-0" onClick={close} aria-label="Kapat"><IconX className="size-5" /></Button>
          </div>
          <div className="flex-1 overflow-y-auto overflow-x-hidden overscroll-contain px-gutter pb-4 pt-1" data-vaul-no-drag={false}>
            <div className="grid gap-4">{typeof children === 'function' ? children(close) : children}</div>
          </div>
          {footer && <div className="border-t px-gutter pt-3 pb-[max(12px,env(safe-area-inset-bottom))] grid gap-2">{typeof footer === 'function' ? footer(close) : footer}</div>}
          {!footer && <div className="pb-safe" />}
        </V.Content>
      </V.Portal>
    </V.Root>
  )
}

export const Empty = ({ icon: I, title, children, action }) => (
  <div className="flex flex-col items-center gap-2 border border-dashed px-6 py-8 text-center rounded-lg">
    {I && <I className="text-muted-foreground size-6" stroke={1.5} />}
    <div className="font-medium">{title}</div>
    {children && <p className="text-muted-foreground text-sm text-balance">{children}</p>}
    {action}
  </div>
)

export const SectionTitle = ({ children, action }) => (
  <div className="flex items-center justify-between gap-2 pt-2">
    <h2 className="text-muted-foreground text-xs font-medium uppercase tracking-wider">{children}</h2>
    {action}
  </div>
)

export function Toasts({ items, top }) {
  return (
    <div className={cn('pointer-events-none fixed inset-x-0 z-[60] flex flex-col items-center gap-2 px-gutter', top ? 'top-[calc(env(safe-area-inset-top,0px)+10px)]' : 'bottom-[calc(84px+env(safe-area-inset-bottom,0px))]')} aria-live="polite">
      {items.map((t) => (
        <div key={t.id} data-toast className={cn('glass text-foreground pointer-events-auto flex items-center gap-2 rounded-full py-2 pl-4 text-sm font-medium', t.undo ? 'pr-2' : 'pr-4 py-2.5', t.out ? 'toast-out' : 'toast-in')}>
          {t.kind === 'delete' ? <IconTrash className="text-muted-foreground size-4" /> : t.kind === 'error' ? <IconAlertCircle className="text-destructive size-4" /> : <IconCheck className="text-primary size-4" stroke={2.5} />}
          <span className="min-w-0 max-w-[60vw] truncate">{t.msg}</span>
          {t.undo && <button onClick={t.undo} className="text-foreground bg-foreground/10 ml-1 h-9 shrink-0 whitespace-nowrap rounded-full px-3.5 text-sm font-semibold active:scale-95">Geri al</button>}
        </div>
      ))}
    </div>
  )
}
