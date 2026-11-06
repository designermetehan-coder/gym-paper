// Üç yönlü birleştirme (RM-04): base = son başarılı senkrondaki durum.
// İki cihazda aynı anda yapılan değişiklikler kayıt düzeyinde birleşir; silmeler korunur.
// Aynı kaydı iki taraf da değiştirdiyse daha yeni db (updatedAt) kazanır.

const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b)
const keyOf = (x) => (x && typeof x === 'object' ? x.id ?? x.date ?? x.name ?? JSON.stringify(x) : String(x))
const COLLECTIONS = ['myFoods', 'recipes', 'measures', 'programs', 'customExercises', 'mealTemplates']
const DAY_COLLECTIONS = ['entries', 'extras']

function mergeValue(b, l, r, localWins) {
  if (eq(l, r)) return l
  if (eq(l, b)) return r
  if (eq(r, b)) return l
  return localWins ? l : r
}

export function mergeList(base = [], local = [], remote = [], localWins) {
  const B = new Map(base.map((x) => [keyOf(x), x]))
  const R = new Map(remote.map((x) => [keyOf(x), x]))
  const L = new Map(local.map((x) => [keyOf(x), x]))
  const out = []
  // yerel sırayı koru, uzakta yeni eklenenleri sona ekle
  for (const [k, l] of L) {
    const r = R.get(k), b = B.get(k)
    if (r !== undefined) out.push(mergeValue(b, l, r, localWins))
    else if (b === undefined || !eq(l, b)) out.push(l) // yerelde eklendi ya da uzak silerken yerel değiştirdi
    // aksi halde uzak sildi → düş
  }
  for (const [k, r] of R) {
    if (L.has(k)) continue
    const b = B.get(k)
    if (b === undefined || !eq(r, b)) out.push(r) // uzakta eklendi
    // aksi halde yerel sildi → düş
  }
  return out
}

function mergeObj(b = {}, l = {}, r = {}, localWins, lists = []) {
  const out = {}
  for (const k of new Set([...Object.keys(l), ...Object.keys(r)])) {
    if (lists.includes(k)) { out[k] = mergeList(b?.[k], l[k], r[k], localWins); continue }
    const hasL = k in l, hasR = k in r, bv = b?.[k]
    if (hasL && hasR) out[k] = mergeValue(bv, l[k], r[k], localWins)
    else if (hasL) { if (bv === undefined || !eq(l[k], bv)) out[k] = l[k] }
    else if (bv === undefined || !eq(r[k], bv)) out[k] = r[k]
  }
  return out
}

export function mergeDb(base, local, remote) {
  if (!base) return (remote.updatedAt || 0) > (local.updatedAt || 0) ? { ...remote, cloud: local.cloud } : local
  const localWins = (local.updatedAt || 0) >= (remote.updatedAt || 0)
  const top = mergeObj(base, local, remote, localWins, COLLECTIONS)
  delete top.log
  const log = {}
  const bl = base.log || {}, ll = local.log || {}, rl = remote.log || {}
  for (const d of new Set([...Object.keys(ll), ...Object.keys(rl)])) {
    const m = mergeObj(bl[d] || {}, ll[d] || {}, rl[d] || {}, localWins, DAY_COLLECTIONS)
    if (Object.keys(m).length) log[d] = m
  }
  return { ...top, log, cloud: local.cloud, updatedAt: Math.max(local.updatedAt || 0, remote.updatedAt || 0) + 1 }
}
