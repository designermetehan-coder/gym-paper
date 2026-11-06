import React from 'react'
import ReactDOM from 'react-dom/client'
import './index.css'
import App from './App'

const standalone = window.navigator.standalone === true || matchMedia('(display-mode: standalone)').matches
document.documentElement.classList.toggle('standalone', standalone)

// Güncelleme: yeni sürüm arka planda iner; Profil › Uygulama'dan ya da (otomatikse) uygulama arka plana alınınca uygulanır.
// Veriler IndexedDB'de durur, güncelleme yalnız uygulama dosyalarını değiştirir.
import { registerSW } from 'virtual:pwa-register'
const U = (window.__balliUpdate = { ready: false, checking: false, lastCheck: 0, reg: null })
const emit = () => window.dispatchEvent(new Event('balli-update'))
const updateSW = registerSW({
  onNeedRefresh() { U.ready = true; emit() },
  onRegisteredSW(_url, reg) { U.reg = reg || null; emit() },
})
U.apply = () => updateSW(true)
U.check = async () => {
  if (!U.reg || !navigator.onLine) return U.ready
  U.checking = true; emit()
  try { await U.reg.update() } catch {}
  await new Promise((r) => setTimeout(r, 1500)) // yeni sürüm iniyorsa onNeedRefresh'e zaman tanı
  U.checking = false; U.lastCheck = Date.now(); emit()
  return U.ready
}
const autoOn = () => { try { return localStorage.getItem('balli-autoupdate') !== '0' } catch { return true } }
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && Date.now() - U.lastCheck > 30 * 60e3) U.check()
  if (document.visibilityState === 'hidden' && U.ready && autoOn() && !window.__balliSession) U.apply()
})
setTimeout(() => U.check(), 5000)
// Eski sürümün parça dosyası bulunamazsa bir kez yenile
window.addEventListener('vite:preloadError', (e) => {
  if (!navigator.onLine || sessionStorage.getItem('balli-reloaded')) return
  try { sessionStorage.setItem('balli-reloaded', '1') } catch {}
  e.preventDefault(); location.reload()
})
setTimeout(() => { try { sessionStorage.removeItem('balli-reloaded') } catch {} }, 10000)

ReactDOM.createRoot(document.getElementById('root')).render(<App />)
