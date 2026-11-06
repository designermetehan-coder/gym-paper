// Birim testleri: birleştirme (RM-04), geri alma, besin metni ayrıştırma, migrasyon yardımcıları
import { mergeDb, mergeList } from '../src/lib/merge'
import { parseLine, splitText } from '../src/lib/search'
import { rings, streak, weekScore, isoWeek, pendingGoals, shiftKey } from '../src/lib/gamify'

let failed = 0, passed = 0
const t = (name, fn) => { try { fn(); passed++ } catch (e) { failed++; console.error('✗', name, '\n ', e.message) } }
const eq = (a, b, m = '') => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m} beklenen ${JSON.stringify(b)}, gelen ${JSON.stringify(a)}`) }

t('merge: iki cihazın eklemeleri, silme ve düzenleme korunur', () => {
  const base = { updatedAt: 1, myFoods: [{ id: 'a', n: 1 }, { id: 'b', n: 1 }], log: { d1: { water: 500, entries: [{ id: 'e1' }] } }, targets: { kcal: 1800 } }
  const local = { updatedAt: 3, myFoods: [{ id: 'a', n: 2 }, { id: 'c' }], log: { d1: { water: 1000, entries: [{ id: 'e1' }, { id: 'e2' }] } }, targets: { kcal: 1800 } }
  const remote = { updatedAt: 2, myFoods: [{ id: 'a', n: 1 }, { id: 'b', n: 1 }, { id: 'd' }], log: { d1: { water: 500, steps: 9000, entries: [{ id: 'e1' }, { id: 'e3' }] }, d2: { water: 250 } }, targets: { kcal: 2000 } }
  const m = mergeDb(base, local, remote)
  eq(m.myFoods.map((x) => x.id), ['a', 'c', 'd'])
  eq(m.myFoods[0].n, 2)
  eq(m.log.d1.entries.map((x) => x.id), ['e1', 'e2', 'e3'])
  eq([m.log.d1.water, m.log.d1.steps, m.log.d2.water, m.targets.kcal], [1000, 9000, 250, 2000])
})
t('merge: base yoksa yeni olan kazanır', () => { eq(mergeDb(null, { updatedAt: 1, x: 1 }, { updatedAt: 2, x: 2 }).x, 2) })
t('merge: iki taraf aynı kaydı değiştirirse yeni db kazanır', () => {
  eq(mergeList([{ id: 'a', n: 0 }], [{ id: 'a', n: 1 }], [{ id: 'a', n: 2 }], false)[0].n, 2)
})

// Geri alma = mergeDb(sonrası, güncel, öncesi)
const undo = (before, after, cur) => mergeDb(after, { ...cur, updatedAt: 99 }, before)
t('geri al: yeni gün kaydına ekleme geri alınınca aynı güne sonradan eklenen su kalır', () => {
  const before = { updatedAt: 1, log: {} }, after = { updatedAt: 2, log: { x: { entries: [{ id: 'e1' }] } } }
  const cur = { updatedAt: 3, log: { x: { entries: [{ id: 'e1' }], water: 500 } } }
  eq(undo(before, after, cur).log, { x: { entries: [], water: 500 } })
})
t('geri al: silme geri alınınca pencerede yapılan düzenleme ve ekleme kalır', () => {
  const before = { updatedAt: 1, log: { d: { entries: [{ id: 'y' }, { id: 'm' }, { id: 'e', g: 55 }] } } }
  const after = { updatedAt: 2, log: { d: { entries: [{ id: 'm' }, { id: 'e', g: 55 }] } } }
  const cur = { updatedAt: 3, log: { d: { entries: [{ id: 'm' }, { id: 'e', g: 300 }, { id: 'n' }] } } }
  const r = undo(before, after, cur).log.d.entries
  eq(r.map((x) => x.id).sort(), ['e', 'm', 'n', 'y']); eq(r.find((x) => x.id === 'e').g, 300)
})
t('geri al: iki silmeden yalnız biri geri alınır', () => {
  const s0 = { updatedAt: 1, mealTemplates: [{ id: 1 }, { id: 2 }, { id: 3 }] }
  const s1 = { updatedAt: 2, mealTemplates: [{ id: 1 }, { id: 2 }] }
  const s2 = { updatedAt: 3, mealTemplates: [{ id: 1 }] }
  eq(undo(s0, s1, s2).mealTemplates.map((x) => x.id), [1, 3])
})
t('geri al: içe aktarma geri alınınca kullanıcının yeni besini kalır', () => {
  const s0 = { updatedAt: 1, myFoods: [{ id: 'old' }] }
  const s1 = { updatedAt: 2, myFoods: [{ id: 'i1' }, { id: 'i2' }, { id: 'old' }] }
  const s2 = { updatedAt: 3, myFoods: [{ id: 'mine' }, { id: 'i1' }, { id: 'i2' }, { id: 'old' }] }
  eq(undo(s0, s1, s2).myFoods.map((x) => x.id), ['mine', 'old'])
})
t('ayrıştırma: virgüllü ondalık', () => { const r = parseLine('1,5 dilim ekmek'); if (!r || !(r.qty === 1.5 || Math.abs((r.g || 0) - 45) < 1)) throw new Error(JSON.stringify(r)) })
t('ayrıştırma: noktalı ondalık', () => { const r = parseLine('1.5 porsiyon pilav'); if (!r || !(r.qty === 1.5 || Math.round(r.g) === 270)) throw new Error(JSON.stringify(r)) })


// ---- Oyunlaştırma ----
const T = { kcal: 2000, p: 100, water: 2000, steps: 8000 }
const food = (kcal, p = 0) => ({ entries: [{ id: Math.random(), kcal, p }] })
t('halkalar: kalori %90–105 kapanır, az ya da fazla kapanmaz, %110 üstü uyarı', () => {
  eq(rings({ targets: T, log: { d: food(1900, 100) } }, 'd').kcal.closed, true)
  eq(rings({ targets: T, log: { d: food(1500) } }, 'd').kcal.closed, false)
  const o = rings({ targets: T, log: { d: food(2300) } }, 'd').kcal
  eq([o.closed, o.over], [false, true])
  eq(rings({ targets: T, log: { d: { ...food(0, 100), steps: 8000 } } }, 'd').protein.closed, true)
})
t('ISO hafta', () => { eq(isoWeek('2026-10-22'), '2026-W43'); eq(isoWeek('2026-01-01'), '2026-W01'); eq(isoWeek('2027-01-01'), '2026-W53') })
t('seri: ardışık günler, bugün boşsa dünden sayar', () => {
  const log = { '2026-10-19': food(100), '2026-10-20': food(100), '2026-10-21': { workoutDone: true } }
  const s = streak({ targets: T, log }, '2026-10-22')
  eq([s.count, s.activeToday, s.frozen.length], [3, false, 0])
})
t('seri: tek boş gün haftalık dondurmayla köprülenir, ikinci boşluk bozar', () => {
  // 19,20 aktif · 21 boş · 22 aktif (aynı hafta W43)
  const log = { '2026-10-19': food(1), '2026-10-20': food(1), '2026-10-22': food(1) }
  const s = streak({ targets: T, log }, '2026-10-22')
  eq([s.count, s.frozen, s.pending], [4, ['2026-10-21'], { '2026-W43': '2026-10-21' }])
  eq(s.freezeReady, false)
  // önceki haftadaki boşluk (18, W42) o haftanın hakkıyla köprülenir
  eq(streak({ targets: T, log: { ...log, '2026-10-17': food(1) } }, '2026-10-22').count, 6)
  // aynı haftada ikinci boşluk köprülenmez: 22 ✓ 21 ✗ 20 ✓ 19 ✗ 18 ✓
  eq(streak({ targets: T, log: { '2026-10-18': food(1), '2026-10-20': food(1), '2026-10-22': food(1) } }, '2026-10-22').count, 3)
  // kalıcı dondurma başka güne verilmişse bu boşluk köprülenmez
  const s3 = streak({ targets: T, log, streak: { freezes: { '2026-W43': '2026-10-23' } } }, '2026-10-22')
  eq(s3.count, 1)
})
t('seri: iki gün üst üste boşluk köprülenmez', () => {
  const log = { '2026-10-18': food(1), '2026-10-22': food(1) }
  eq(streak({ targets: T, log }, '2026-10-22').count, 1)
})
t('haftalık skor: elle hesapla aynı', () => {
  // haftalık plan: Pzt, Çar (2 gün). 7 gün: 16–22 Ekim 2026 (Cum–Per). Pzt 19, Çar 21 planlı.
  const log = {
    '2026-10-19': { workoutDone: true, ...food(0, 95), water: 2000, steps: 9000 },
    '2026-10-20': { ...food(0, 50), water: 2500 },
    '2026-10-22': { ...food(0, 120), steps: 8000 },
  }
  const W = weekScore({ targets: T, log, schedule: { 0: 'a', 2: 'b' } }, '2026-10-22')
  // antrenman 1/2, protein 2/7, su 2/7, adım 2/7 → (0.5*35 + 2/7*35 + 2/7*15 + 2/7*15) = 17.5+10+4.2857+4.2857 = 36.07
  eq(W.score, 36)
  const W2 = weekScore({ targets: T, log, schedule: {} }, '2026-10-22') // plan yok → antrenman payı dağıtılır
  eq(W2.score, Math.round((2 / 7) * 100))
})
t('kilo kademesi: ulaşılan ve kutlanmamış hedefler', () => {
  eq(pendingGoals({ targets: { goals: [95, 90, 85] }, celebrated: [95] }, 89.5, true), [90])
  eq(pendingGoals({ targets: { goals: [95, 90] } }, 96, true), [])
  eq(pendingGoals({ targets: { goals: [95] } }, 90, false), [])
})

t('ayrıştırma: tek satırda iki besin', () => { eq(splitText('2 yumurta 1 dilim ekmek'), ['2 yumurta', '1 dilim ekmek']) })
t('ayrıştırma: sondaki birim bölünmez', () => { eq(splitText('1 porsiyon pilav 200 g'), ['1 porsiyon pilav 200 g']); eq(splitText('tavuk 100 g'), ['tavuk 100 g']) })
t('ayrıştırma: üç besin', () => { eq(splitText('100 g tavuk 2 yumurta 1,5 dilim ekmek'), ['100 g tavuk', '2 yumurta', '1,5 dilim ekmek']) })
console.log(`${passed} geçti, ${failed} başarısız`)
if (failed) process.exit(1)
