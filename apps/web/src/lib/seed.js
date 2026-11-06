import { uid } from './utils'
import { FOODS } from './foods'
import { programsV2, SCHEDULE_V2, CYCLE_V2, NOTES_V2, PROGRAM_VERSION } from './program'

const ex = (name, sets, reps, unit, rest, o = {}) => ({ id: uid(), name, sets, reps, unit, rest, muscle: o.m || '', desc: o.d || '', note: o.n || '', video: o.v || '' })
const single = (e) => ({ id: uid(), kind: 'single', ex: e })
const sset = (tag, rounds, rest, exs) => ({ id: uid(), kind: 'superset', tag, rounds, rest, note: '', exs })

const byName = (n) => FOODS.find((f) => f.name === n)
const mine = (name, per100, portions = {}) => ({ id: uid(), name, per100, portions, source: 'mine', image: null })

export function seed(template = 'mete', o = {}) {
  if (template !== 'mete') return blankSeed(o)
  const kiyma = byName('Dana kıyma (%10 yağ)'), pat = byName('Patates'), kab = byName('Kabak'), bib = byName('Biber'), dom = byName('Domates'), sog = byName('Soğan'), zy = byName('Zeytinyağı')
  const rItem = (f, g) => ({ id: uid(), name: f.name, g, per100: f.per100 })

  return {
    v: 2,
    profile: { name: 'Mete', startKg: 125 },
    programs: programsV2(),
    programsV: PROGRAM_VERSION,
    planMode: 'weekly',
    schedule: SCHEDULE_V2,
    cycle: CYCLE_V2,
    cycleIdx: 0,
    targets: { kcal: 1460, p: 142, c: 140, f: 36, water: 3000, steps: 10000, goals: [95, 90, 85] },
    customExercises: [],
    myFoods: [
      mine('Fırın palamut', { kcal: 150, p: 22, c: 0, f: 6.5 }, { porsiyon: 200 }),
      mine('Fırın somon', { kcal: 208, p: 20, c: 0, f: 13 }, { porsiyon: 200 }),
      mine('Kuzu pirzola', { kcal: 280, p: 17, c: 0, f: 23 }, { adet: 60 }),
      mine('Tavada et', { kcal: 210, p: 26, c: 0, f: 11 }, { porsiyon: 180 }),
      mine('Tavuk göğsü (ızgara)', { kcal: 165, p: 31, c: 0, f: 3.6 }, { porsiyon: 150 }),
      mine('Sek sade quark', { kcal: 65, p: 11.5, c: 3.5, f: 0.2 }, { kutu: 165 }),
      mine('Protein bar (20 g protein)', { kcal: 350, p: 33, c: 35, f: 12 }, { adet: 60 }),
      mine('İzole whey protein', { kcal: 380, p: 85, c: 5, f: 1.5 }, { ölçek: 30 }),
      mine('Protein süt', { kcal: 55, p: 7.5, c: 4, f: 1 }, { kutu: 200 }),
    ],
    recipes: [
      { id: uid(), name: 'Sebzeli fırın kıyma', servings: 4, image: null, note: 'Örnek tarif', items: [
        rItem(kiyma, 500), rItem(pat, 340), rItem(kab, 300), rItem(bib, 80), rItem(dom, 120), rItem(sog, 100), rItem(zy, 10),
      ] },
    ],
    measures: [
      { id: uid(), date: '2026-08-09', kg: 115 },
      { id: uid(), date: '2026-09-08', kg: 107.6 },
      { id: uid(), date: '2026-10-07', kg: 100.8, bel: 106, kalca: 109, gogus: 114, sagkol: 40, solkol: 40, bacak: 60, omuz: 50 },
      { id: uid(), date: '2026-10-21', kg: 98 },
    ],
    photos: [],
    log: {},
  }
}

export function blankSeed({ name = 'Yeni profil', startKg = null, currentKg = null, goals = [], kcal = 1800, p = 120, c = 180, f = 60 } = {}) {
  const today = new Date(); const pad = (n) => String(n).padStart(2, '0')
  const date = `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`
  const kg = currentKg || startKg
  return {
    v: 2, profile: { name, startKg: startKg || kg || null },
    programs: [], programsV: PROGRAM_VERSION, planMode: 'weekly',
    schedule: { 0: null, 1: null, 2: null, 3: null, 4: null, 5: null, 6: null }, cycle: [], cycleIdx: 0,
    targets: { kcal, p, c, f, water: 2500, steps: 10000, goals },
    customExercises: [], myFoods: [], recipes: [],
    measures: kg ? [{ id: uid(), date, kg }] : [],
    photos: [], log: {},
  }
}
