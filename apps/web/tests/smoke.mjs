// Uçtan uca duman testi: `npm run build && npm run test:e2e` (vite preview'ı kendisi başlatır)
import { chromium } from 'playwright'
import { spawn } from 'node:child_process'

const PORT = 4300, BASE = `http://localhost:${PORT}`
const srv = spawn('npx', ['vite', 'preview', '--port', String(PORT), '--strictPort'], { stdio: 'ignore' })
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
for (let i = 0; i < 40; i++) { try { if ((await fetch(BASE)).ok) break } catch {} await wait(250) }

const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {})
let failed = 0
async function flow(name, fn, cs = 'light') {
  const ctx = await browser.newContext({ serviceWorkers: 'block', viewport: { width: 390, height: 844 }, colorScheme: cs, locale: 'tr-TR', hasTouch: true, isMobile: true })
  const p = await ctx.newPage(); const errs = []
  p.on('pageerror', (e) => errs.push(e.message))
  try {
    await p.goto(BASE); await p.getByLabel('Ad').fill('Test'); await p.getByRole('button', { name: 'Başla', exact: true }).click(); await p.waitForTimeout(800)
    await fn(p)
    if (errs.length) throw new Error('Sayfa hatası: ' + errs[0])
    console.log('✓', name, cs)
  } catch (e) { failed++; console.error('✗', name, cs, '\n ', e.message.split('\n')[0]) }
  await ctx.close()
}
const tab = (p, n) => p.locator('nav[aria-label=Sekmeler]').getByRole('button', { name: new RegExp('^' + n) }).click()
const sheet = (p) => p.locator('[data-vaul-drawer]').last()

for (const cs of ['light', 'dark']) {
  await flow('onboarding ve sekmeler', async (p) => { for (const t of ['Antrenman', 'Beslenme', 'Profil', 'Bugün']) { await tab(p, t); await p.waitForTimeout(300) } }, cs)
  await flow('besin ekle ve geri al', async (p) => {
    await tab(p, 'Beslenme'); await p.getByRole('button', { name: 'Yediğini ekle' }).first().click()
    await sheet(p).getByPlaceholder(/Besin ara/).fill('yumurta'); await p.waitForTimeout(300)
    await sheet(p).getByRole('button').filter({ hasText: /Yumurta/ }).first().click(); await p.waitForTimeout(400)
    await sheet(p).getByRole('button', { name: /^Ekle/ }).last().click(); await p.waitForTimeout(500)
    if (!(await p.getByText(/kcal · P/).count())) throw new Error('kayıt görünmedi')
    await p.getByRole('button', { name: 'Geri al' }).click(); await p.waitForTimeout(500)
    if (await p.getByText(/Yumurta/).count()) throw new Error('geri alma çalışmadı')
  }, cs)
  await flow('su ekle', async (p) => {
    await p.getByRole('button', { name: /ml ekle/ }).click(); await p.waitForTimeout(300)
    if (!(await p.getByText(/0,5|500/).count())) throw new Error('su artmadı')
  }, cs)
  await flow('tema kalıcı', async (p) => {
    await tab(p, 'Profil'); await p.getByRole('radio', { name: 'Koyu' }).click(); await p.reload(); await p.waitForTimeout(800)
    if (!(await p.evaluate(() => document.documentElement.classList.contains('dark')))) throw new Error('koyu tema kalmadı')
  }, cs)
}
await browser.close(); srv.kill()
console.log(failed ? `${failed} akış başarısız` : 'Bütün akışlar geçti')
process.exit(failed ? 1 : 0)
