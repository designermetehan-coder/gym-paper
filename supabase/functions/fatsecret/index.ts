// FatSecret vekil sunucusu: anahtarlar yalnız burada (Supabase gizli değişkenleri), uygulamada değil.
// Gizli değişkenler: FATSECRET_CLIENT_ID, FATSECRET_CLIENT_SECRET, isteğe bağlı FATSECRET_SCOPE (premier|basic), FATSECRET_REGION (TR).
// GET ?q=metin  → { foods: FoodItem[] }   GET ?barcode=869...  → { foods: [FoodItem] }
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' }
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

let token: { value: string; exp: number } | null = null
async function getToken(): Promise<string | null> {
  const id = Deno.env.get('FATSECRET_CLIENT_ID'), secret = Deno.env.get('FATSECRET_CLIENT_SECRET')
  if (!id || !secret) return null
  if (token && token.exp > Date.now() + 60_000) return token.value
  const r = await fetch('https://oauth.fatsecret.com/connect/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: 'Basic ' + btoa(`${id}:${secret}`) },
    body: new URLSearchParams({ grant_type: 'client_credentials', scope: Deno.env.get('FATSECRET_SCOPE') || 'premier' }),
  })
  if (!r.ok) return null
  const j = await r.json()
  token = { value: j.access_token, exp: Date.now() + (j.expires_in || 3600) * 1000 }
  return token.value
}

async function api(method: string, params: Record<string, string>, tk: string) {
  const region = Deno.env.get('FATSECRET_REGION') || 'TR'
  const call = async (localized: boolean) => {
    const u = new URL('https://platform.fatsecret.com/rest/server.api')
    u.search = new URLSearchParams({ method, format: 'json', ...params, ...(localized ? { region, language: 'tr' } : {}) }).toString()
    const r = await fetch(u, { headers: { Authorization: `Bearer ${tk}` } })
    return r.ok ? await r.json() : { error: { message: `HTTP ${r.status}` } }
  }
  let j = await call(true)
  if (j?.error) j = await call(false) // bölgesel lisans yoksa genel veri
  return j
}

const num = (v: unknown) => { const n = parseFloat(String(v ?? '').replace(',', '.')); return Number.isFinite(n) ? n : 0 }
const arr = <T>(v: T | T[] | undefined): T[] => (v == null ? [] : Array.isArray(v) ? v : [v])

// "Per 100g - Calories: 165kcal | Fat: 3.57g | Carbs: 0.00g | Protein: 31.02g"
function fromDescription(f: Record<string, string>) {
  const m = /Per (.+?) - Calories: ([\d.]+)kcal \| Fat: ([\d.]+)g \| Carbs: ([\d.]+)g \| Protein: ([\d.]+)g/i.exec(f.food_description || '')
  if (!m) return null
  const g = /(\d+(?:\.\d+)?)\s*(g|ml)\b/i.exec(m[1]); if (!g) return null
  const grams = num(g[1]); if (grams <= 0) return null
  const k = 100 / grams
  const name = [f.food_name, f.brand_name].filter(Boolean).join(' · ')
  return { id: `fs-${f.food_id}`, name, per100: { kcal: num(m[2]) * k, p: num(m[5]) * k, c: num(m[4]) * k, f: num(m[3]) * k }, portions: grams !== 100 ? { porsiyon: grams } : {}, tags: '', source: 'fatsecret' }
}

function fromServings(food: Record<string, unknown>, barcode?: string) {
  const s = arr((food.servings as { serving?: unknown })?.serving as Record<string, string>[])
    .find((x) => ['g', 'ml'].includes(String(x.metric_serving_unit)) && num(x.metric_serving_amount) > 0)
  if (!s) return null
  const k = 100 / num(s.metric_serving_amount)
  return {
    id: `fs-${food.food_id}`, name: [food.food_name, food.brand_name].filter(Boolean).join(' · '),
    per100: { kcal: num(s.calories) * k, p: num(s.protein) * k, c: num(s.carbohydrate) * k, f: num(s.fat) * k },
    portions: { porsiyon: num(s.metric_serving_amount) }, tags: '', source: 'fatsecret', ...(barcode ? { barcode } : {}),
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  const tk = await getToken()
  if (!tk) return json({ error: 'FatSecret anahtarı tanımlı değil' }, 503)
  const u = new URL(req.url)
  const q = u.searchParams.get('q')?.trim().slice(0, 80), barcode = u.searchParams.get('barcode')?.replace(/\D/g, '').slice(0, 14)
  try {
    if (barcode) {
      const gtin = barcode.padStart(13, '0')
      const id = (await api('food.find_id_for_barcode', { barcode: gtin }, tk))?.food_id?.value
      if (!id || id === '0') return json({ foods: [] }, 404)
      const food = (await api('food.get.v4', { food_id: String(id) }, tk))?.food
      const item = food && fromServings(food, barcode)
      return item ? json({ foods: [item] }) : json({ foods: [] }, 404)
    }
    if (q) {
      const j = await api('foods.search', { search_expression: q, max_results: '20' }, tk)
      const foods = arr(j?.foods?.food).map(fromDescription).filter(Boolean)
      return json({ foods })
    }
    return json({ error: 'q ya da barcode gerekli' }, 400)
  } catch {
    return json({ error: 'FatSecret yanıt vermedi' }, 502)
  }
})
