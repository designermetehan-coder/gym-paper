// Hafif konfeti (GM-08): tek canvas, kendini temizler; azaltılmış hareket tercihinde yalnız titreşim.
import { haptic } from '@/lib/utils'

const COLORS = ['#f97316', '#fb923c', '#facc15', '#22c55e', '#38bdf8', '#a78bfa', '#f43f5e']

export function burst({ x = 0.5, y = 0.35, count = 90, spread = 70, power = 1 } = {}) {
  try { if (navigator.userActivation?.hasBeenActive ?? true) haptic(true) } catch {}
  if (typeof window === 'undefined' || matchMedia('(prefers-reduced-motion: reduce)').matches) return
  const c = document.createElement('canvas')
  const dpr = Math.min(2, devicePixelRatio || 1)
  c.width = innerWidth * dpr; c.height = innerHeight * dpr
  Object.assign(c.style, { position: 'fixed', inset: '0', width: '100%', height: '100%', pointerEvents: 'none', zIndex: 80 })
  c.setAttribute('aria-hidden', 'true')
  document.body.appendChild(c)
  const g = c.getContext('2d'); g.scale(dpr, dpr)
  const ox = innerWidth * x, oy = innerHeight * y
  const ps = Array.from({ length: count }, () => {
    const a = (-90 + (Math.random() - 0.5) * spread * 2) * (Math.PI / 180)
    const v = (6 + Math.random() * 7) * power
    return { x: ox, y: oy, vx: Math.cos(a) * v, vy: Math.sin(a) * v, r: 3 + Math.random() * 4, rot: Math.random() * 6, vr: (Math.random() - 0.5) * 0.4, col: COLORS[(Math.random() * COLORS.length) | 0], life: 0 }
  })
  const t0 = performance.now()
  const step = (t) => {
    const k = (t - t0) / 1000
    g.clearRect(0, 0, innerWidth, innerHeight)
    for (const p of ps) {
      p.vy += 0.28; p.vx *= 0.985; p.vy *= 0.985; p.x += p.vx; p.y += p.vy; p.rot += p.vr
      g.save(); g.globalAlpha = Math.max(0, 1 - k / 2.2); g.translate(p.x, p.y); g.rotate(p.rot); g.fillStyle = p.col
      g.fillRect(-p.r, -p.r / 2, p.r * 2, p.r); g.restore()
    }
    if (k < 2.2) requestAnimationFrame(step); else c.remove()
  }
  requestAnimationFrame(step)
}
