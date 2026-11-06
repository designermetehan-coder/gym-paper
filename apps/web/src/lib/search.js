import { FOODS } from './foods'
import { norm, uid } from './utils'

export function scoreFood(food, q) {
  const n = norm(food.name + ' ' + (food.tags || ''))
  const qq = norm(q)
  if (!qq) return 0
  if (norm(food.name) === qq) return 100
  if (norm(food.name).startsWith(qq)) return 80
  const words = qq.split(' ')
  let hit = 0
  for (const w of words) if (w.length > 1 && n.includes(w)) hit++
  if (!hit) return 0
  return 40 + (hit / words.length) * 30 - Math.min(10, n.length / 10)
}

export function searchLocal(q, myFoods = []) {
  const all = [...myFoods.map((f) => ({ ...f, mine: true })), ...FOODS]
  return all
    .map((f) => ({ f, s: scoreFood(f, q) + (f.mine ? 15 : 0) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s)
    .slice(0, 20)
    .map((x) => x.f)
}

const fin = (v) => (Number.isFinite(+v) ? +v : 0)
export const macrosFor = (per100 = {}, g) => {
  const G = Math.max(0, fin(g))
  return { kcal: (fin(per100.kcal) * G) / 100, p: (fin(per100.p) * G) / 100, c: (fin(per100.c) * G) / 100, f: (fin(per100.f) * G) / 100 }
}

/* ---- Yazılı giriş: "2 dilim pizza, 1 kutu kola, 150 g makarna" ---- */
const WORDNUM = { yarim: 0.5, bir: 1, iki: 2, uc: 3, dort: 4, bes: 5, alti: 6, yedi: 7, sekiz: 8, dokuz: 9, on: 10, ceyrek: 0.25 }
const UNITS = [
  ['g', ['g', 'gr', 'gram']], ['ml', ['ml']], ['dilim', ['dilim']], ['adet', ['adet', 'tane']], ['porsiyon', ['porsiyon', 'pors']],
  ['kutu', ['kutu']], ['bardak', ['bardak']], ['kase', ['kase']], ['top', ['top']], ['kadeh', ['kadeh']], ['tek', ['tek']],
  ['duble', ['duble']], ['paket', ['paket']], ['ölçek', ['olcek']], ['şişe', ['sise']], ['tabak', ['tabak']], ['avuç', ['avuc']],
  ['yemek kaşığı', ['yemek kasigi', 'yk']], ['tatlı kaşığı', ['tatli kasigi', 'tk']], ['büyük', ['buyuk']], ['kare', ['kare']],
]

export function parseLine(line) {
  // sayıyı norm'dan önce al: norm "." ve "," karakterlerini boşluğa çevirir (1.5 / 1,5)
  let qty = null
  let rest = line.trim()
  const m = rest.match(/^(\d+(?:[.,]\d+)?)\s*/)
  if (m) { qty = parseFloat(m[1].replace(',', '.')); rest = rest.slice(m[0].length) }
  let t = norm(rest)
  if (qty == null) {
    const w = t.split(' ')[0]
    if (WORDNUM[w] != null) {
      qty = WORDNUM[w]; t = t.slice(w.length).trim()
      if (w === 'yarim' || w === 'ceyrek') return { qty: 1, unit: w === 'yarim' ? 'yarım' : 'çeyrek', name: t, raw: line, frac: WORDNUM[w] }
    }
  }
  let unit = null
  for (const [u, alts] of UNITS) {
    for (const a of alts) {
      if (t === a || t.startsWith(a + ' ')) { unit = u; t = t.slice(a.length).trim(); break }
    }
    if (unit) break
  }
  // "yarım" sonra gelirse: "1 yarım ekmek kokoreç" gibi nadir; yok say
  return { qty: qty ?? 1, unit, name: t, raw: line.trim() }
}

export function resolveLine(parsed, myFoods) {
  const cands = searchLocal(parsed.name, myFoods)
  const food = cands[0]
  if (!food) return { ...parsed, id: uid(), food: null, cands: [] }
  return { ...parsed, id: uid(), food, cands: cands.slice(0, 6), g: gramsFor(parsed, food) }
}

export function gramsFor({ qty, unit, frac }, food) {
  const P = food.portions || {}
  if (unit === 'g' || unit === 'ml') return qty
  if (unit === 'yarım' && P['yarım']) return P['yarım']
  if (unit === 'çeyrek' && P['çeyrek']) return P['çeyrek']
  if (unit && P[unit]) return qty * P[unit]
  const first = Object.values(P)[0]
  const base = first || 100
  return (frac ?? qty) * base
}

const UNIT_WORDS = /^(g|gr|gram|kg|ml|lt|l|adet|tane|dilim|porsiyon|kase|kâse|tabak|bardak|kaşık|kasik|yemek|tatlı|tatli|çay|cay|avuç|avuc|paket|kutu|büyük|buyuk|küçük|kucuk|orta|yarım|yarim)$/i
// "2 yumurta 1 dilim ekmek" gibi tek satırdaki birden çok besini ayırır (QA-45)
function splitByNumbers(piece) {
  if (!/^\d/.test(piece)) return [piece]
  const out = []; let rest = piece
  for (;;) {
    const m = rest.slice(1).search(/\s\d+(?:[.,]\d+)?\s+\S/)
    if (m < 0) break
    const at = m + 1
    const tail = rest.slice(at).trim()
    const words = tail.replace(/^\d+(?:[.,]\d+)?\s*/, '').split(/\s+/)
    if (!words.some((w) => w && !UNIT_WORDS.test(w))) break // kalan yalnız birimse ("200 g") bölme
    out.push(rest.slice(0, at).trim()); rest = tail
  }
  out.push(rest.trim())
  return out.filter(Boolean)
}
export const splitText = (text) =>
  text.split(/\n|,(?!\d)|;|\+|\s+ve\s+|\s+ile\s+/i).map((s) => s.trim()).filter(Boolean).flatMap(splitByNumbers)

/* ---- Open Food Facts (internet) ---- */
const OFF = 'https://world.openfoodfacts.org'
const toFood = (p) => {
  const n = p.nutriments || {}
  const kcal = Number.isFinite(+n['energy-kcal_100g']) && n['energy-kcal_100g'] !== '' ? +n['energy-kcal_100g'] : Number.isFinite(+n['energy_100g']) && +n['energy_100g'] > 0 ? +n['energy_100g'] / 4.184 : null
  if (kcal == null || !Number.isFinite(kcal) || kcal < 0) return null
  const serving = parseFloat(p.serving_quantity) > 0 ? parseFloat(p.serving_quantity) : null
  return {
    id: 'off-' + p.code,
    name: [p.product_name_tr || p.product_name, p.brands?.split(',')[0]].filter(Boolean).join(' · ') || 'Adsız ürün',
    per100: { kcal, p: Math.max(0, fin(n.proteins_100g)), c: Math.max(0, fin(n.carbohydrates_100g)), f: Math.max(0, fin(n.fat_100g)) },
    portions: serving ? { porsiyon: serving } : {},
    image: p.image_front_small_url || null,
    barcode: p.code,
    source: 'off',
  }
}
// 10 sn zaman aşımı; dışarıdan gelen signal da iptal eder
async function getJSON(url, signal) {
  const ac = new AbortController()
  const t = setTimeout(() => ac.abort(), 10000)
  const off = () => ac.abort()
  signal?.addEventListener('abort', off)
  try {
    const r = await fetch(url, { signal: ac.signal })
    return r
  } catch (e) {
    if (signal?.aborted) throw e
    throw new Error(navigator.onLine === false ? 'İnternet bağlantısı yok.' : ac.signal.aborted ? 'Bağlantı zaman aşımına uğradı. Tekrar dene.' : 'İnternete bağlanılamadı. Bağlantını kontrol et.')
  } finally { clearTimeout(t); signal?.removeEventListener('abort', off) }
}
export async function searchOnline(q, signal) {
  const url = `${OFF}/cgi/search.pl?search_terms=${encodeURIComponent(q)}&search_simple=1&action=process&json=1&page_size=15&fields=code,product_name,product_name_tr,brands,nutriments,serving_quantity,image_front_small_url`
  const r = await getJSON(url, signal)
  if (!r.ok) throw new Error('Arama yapılamadı')
  const j = await r.json()
  return (j.products || []).map(toFood).filter(Boolean)
}
export async function lookupBarcode(code, signal) {
  const c = String(code).replace(/\D/g, '')
  if (!c) throw new Error('Geçerli bir barkod yaz.')
  const r = await getJSON(`${OFF}/api/v2/product/${encodeURIComponent(c)}.json?fields=code,product_name,product_name_tr,brands,nutriments,serving_quantity,image_front_small_url`, signal)
  if (r.status === 404) throw new Error('Bu barkod Open Food Facts\'te kayıtlı değil')
  if (!r.ok) throw new Error('Ürün bulunamadı')
  const j = await r.json()
  if (j.status !== 1) throw new Error('Bu barkod Open Food Facts\'te kayıtlı değil')
  const f = toFood(j.product)
  if (!f) throw new Error('Ürünün besin değerleri eksik')
  return f
}
