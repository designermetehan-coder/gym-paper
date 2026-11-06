import { clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export const cn = (...a) => twMerge(clsx(a))
export const uid = () => Math.random().toString(36).slice(2, 10)

export const DAYS = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
export const DAYS_LONG = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
export const MONTHS = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık']
const pad = (n) => String(n).padStart(2, '0')
export const keyOf = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
export const todayKey = () => keyOf(new Date())
export const dowOf = (key) => { const [y, m, d] = String(key || '').split('-').map(Number); const t = y ? new Date(y, m - 1, d) : new Date(); return (t.getDay() + 6) % 7 }
export const todayIdx = () => (new Date().getDay() + 6) % 7
export const weekDate = (i, weekOffset = 0) => { const t = new Date(); t.setDate(t.getDate() - todayIdx() + i + weekOffset * 7); return keyOf(t) }
const parts = (k) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(k || '')); return m && +m[2] >= 1 && +m[2] <= 12 ? [+m[1], +m[2], +m[3]] : null }
export const longDate = (k) => { const p = parts(k); return p ? `${p[2]} ${MONTHS[p[1] - 1]} ${p[0]}` : '–' }
export const shortDate = (k) => { const p = parts(k); return p ? `${p[2]} ${MONTHS[p[1] - 1].slice(0, 3)}` : '–' }
export const fmt = (n) => Math.round(n || 0).toLocaleString('tr-TR')
export const fmt1 = (n) => (Math.round((n || 0) * 10) / 10).toLocaleString('tr-TR')
export const num = (v) => { const n = parseFloat(String(v ?? '').replace(',', '.')); return isNaN(n) ? 0 : n }
export const mmss = (s) => `${Math.floor(s / 60)}:${pad(Math.max(0, Math.floor(s % 60)))}`
export const norm = (s) =>
  String(s || '').toLocaleLowerCase('tr-TR')
    .replace(/[ıi̇]/g, 'i').replace(/ş/g, 's').replace(/ğ/g, 'g').replace(/ü/g, 'u').replace(/ö/g, 'o').replace(/ç/g, 'c')
    .replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim()
let hapticEl
// iOS 18+ Safari: <input switch> değiştirildiğinde sistem titreşimi verir; Android'de vibrate.
export const haptic = (strong) => {
  try {
    if (navigator.vibrate) { navigator.vibrate(strong ? 18 : 8); return }
    if (!hapticEl) {
      hapticEl = document.createElement('label'); hapticEl.setAttribute('aria-hidden', 'true'); hapticEl.style.display = 'none'
      const i = document.createElement('input'); i.type = 'checkbox'; i.setAttribute('switch', ''); hapticEl.appendChild(i); document.body.appendChild(hapticEl)
    }
    hapticEl.click()
  } catch {}
}
