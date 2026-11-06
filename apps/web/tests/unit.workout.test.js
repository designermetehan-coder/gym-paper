// Birim testleri: güç seviyesi eşlemesi (GM-06) ve seans içi rekor (GM-08)
import { levelFor, liftOf, strengthLevels, beatsPrevBest, LIFTS } from '../src/lib/progress'

let failed = 0, passed = 0
const t = (name, fn) => { try { fn(); passed++ } catch (e) { failed++; console.error('✗', name, '\n ', e.message) } }
const eq = (a, b, m = '') => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m} beklenen ${JSON.stringify(b)}, gelen ${JSON.stringify(a)}`) }
const near = (a, b, m = '') => { if (Math.abs(a - b) > 0.05) throw new Error(`${m} beklenen ${b}, gelen ${a}`) }

const SQ = LIFTS.find((l) => l.id === 'squat')
t('seviye: eşik altı Başlangıç, eşikte bir üst seviye', () => {
  eq(levelFor(0.3, SQ.m).label, 'Başlangıç')
  eq(levelFor(1.25, SQ.m).label, 'Acemi')
  eq(levelFor(1.4, SQ.m).nextLabel, 'Orta')
  near(levelFor(1.4, SQ.m).pct, 0.6)
  eq(levelFor(3, SQ.m).label, 'Elit'); eq(levelFor(3, SQ.m).next, null)
})
t('eşleme: halter adları eşleşir, dumbbell/yardımlı eşleşmez', () => {
  eq(liftOf('Barbell Bench Press').id, 'bench'); eq(liftOf('Back Squat').id, 'squat'); eq(liftOf('Pull Up').id, 'pullup')
  eq(liftOf('Dumbbell Bench Press'), null); eq(liftOf('Romanian Deadlift'), null); eq(liftOf('Assisted Pull Up'), null)
})
const ex = (id, name, reps = 5) => ({ id, name, unit: 'tekrar', sets: 5, reps })
const db = (sex) => ({
  profile: { sex, startKg: 120 }, measures: [{ id: 'm', date: '2026-10-01', kg: 100 }],
  programs: [{ id: 'p', blocks: [{ kind: 'single', ex: ex('s', 'Back Squat') }, { kind: 'single', ex: ex('b', 'Barbell Bench Press') }, { kind: 'single', ex: ex('u', 'Pull Up', 8) }] }],
  log: { '2026-10-19': { sets: { s: [{ kg: '120', reps: '5', done: true }], b: [{ kg: '80', reps: '5', done: true }], u: [{ kg: '', reps: '12', done: true }] } } },
})
t('seviye: elle hesap (100 kg, erkek)', () => {
  const r = strengthLevels(db('m'))
  const sq = r.rows.find((x) => x.lift.id === 'squat'), be = r.rows.find((x) => x.lift.id === 'bench'), pu = r.rows.find((x) => x.lift.id === 'pullup')
  near(sq.value, 140); eq(sq.label, 'Acemi'); near(sq.toNext, 10)
  near(be.value, 93.33); eq(be.label, 'Acemi'); near(be.toNext, 6.67)
  eq(pu.value, 12); eq(pu.label, 'Orta')
})
t('seviye: kadın standardı daha düşük eşik', () => { eq(strengthLevels(db('f')).rows.find((x) => x.lift.id === 'squat').label, 'Orta') })
t('seviye: cinsiyet seçilmemişse sorulur', () => { eq(strengthLevels(db(undefined)).need, 'sex') })
t('rekor: önceki en iyiyi geçen set', () => {
  eq(beatsPrevBest(db('m'), 'Back Squat', '2026-10-22', 125, 5), true)
  eq(beatsPrevBest(db('m'), 'Back Squat', '2026-10-22', 120, 5), false)
  eq(beatsPrevBest(db('m'), 'Leg Press', '2026-10-22', 300, 5), false) // geçmiş yok → ilk seans rekor sayılmaz
})

console.log(`${passed} geçti, ${failed} başarısız`)
if (failed) process.exit(1)
