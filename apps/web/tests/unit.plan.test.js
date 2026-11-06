// Birim testleri: tekrarlı haftalık plan (geçmiş sabit, gelecek değişir), göç ve tamamlama işaretleri
import { produce } from 'immer'
import { migrate, programFor, assignedProgram, assignDay, setScheduleFrom, freezePast, workoutProgress, completeWorkout, uncompleteWorkout, toggleExDone } from '../src/lib/store'
import { todayKey, keyOf, dowOf } from '../src/lib/utils'
import { shortOf } from '../src/lib/program'

let failed = 0, passed = 0
const t = (name, fn) => { try { fn(); passed++ } catch (e) { failed++; console.error('✗', name, '\n ', e.message) } }
const eq = (a, b, m = '') => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m} beklenen ${JSON.stringify(b)}, gelen ${JSON.stringify(a)}`) }
const shift = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return keyOf(d) }
const today = todayKey(), dow = dowOf(today)
const ex = (id) => ({ id, name: id, unit: 'tekrar', sets: 3, reps: 10 })
const base = () => migrate({ v: 2, programsV: 2, profile: { name: 'T' }, targets: {}, programs: [{ id: 'A', name: 'A', blocks: [{ id: 'b1', kind: 'single', ex: ex('e1') }] }, { id: 'B', name: 'B', blocks: [{ id: 'b2', kind: 'single', ex: ex('e2') }] }], schedule: { [dow]: 'A' }, planMode: 'weekly', log: {} })

t('göç: eski haftalık plan geçmişe taşınır, döngü modu haftalığa döner', () => {
  const d = base()
  eq(d.scheduleHist.length, 1); eq(d.scheduleHist[0].days[dow], 'A'); eq(programFor(d, shift(-7)).id, 'A'); eq(programFor(d, shift(7)).id, 'A')
  const c = migrate({ ...d, scheduleHist: undefined, planMode: 'cycle' })
  eq(c.planMode, 'weekly'); eq(programFor(c, shift(-7)), null, 'döngüde geçmiş gün planı yoktu'); eq(programFor(c, today).id, 'A')
})
t('tekrarlı atama: bugünden sonraki bütün aynı günler değişir, geçmiş değişmez', () => {
  const d = produce(base(), (x) => assignDay(x, today, 'B', true))
  eq(programFor(d, today).id, 'B'); eq(programFor(d, shift(7)).id, 'B'); eq(programFor(d, shift(70)).id, 'B'); eq(programFor(d, shift(-7)).id, 'A')
})
t('ileri haftadan "her hafta tekrarla": bu haftanın aynı gününden başlar', () => {
  const d = produce(base(), (x) => assignDay(x, shift(14), 'B', true))
  eq(programFor(d, today).id, 'B'); eq(programFor(d, shift(7)).id, 'B'); eq(programFor(d, shift(21)).id, 'B'); eq(programFor(d, shift(-7)).id, 'A')
})
t('haftalık plandan sonraki değişiklik ileriye yayılır, geçmiş korunur', () => {
  const d = produce(base(), (x) => setScheduleFrom(x, shift(7), dow, 'B'))
  eq(programFor(d, today).id, 'A'); eq(programFor(d, shift(7)).id, 'B'); eq(programFor(d, shift(21)).id, 'B')
})
t('gelecekteki boş "yalnız bu gün" seçimi haftalık planı engellemez', () => {
  const d0 = produce(base(), (x) => { x.log[shift(7)] = { programId: null } })
  eq(programFor(d0, shift(7)), null)
  const d = produce(d0, (x) => setScheduleFrom(x, today, dow, 'B'))
  eq(programFor(d, shift(7)).id, 'B')
})
t('sadece bu tarih: haftalık plan değişmez', () => {
  const d = produce(base(), (x) => assignDay(x, today, 'B', false))
  eq(programFor(d, today).id, 'B'); eq(programFor(d, shift(7)).id, 'A')
})
t('program içeriği değişince geçmişte yapılmış gün eski hâliyle kalır', () => {
  let d = produce(base(), (x) => { x.log[shift(-7)] = { sets: { e1: [{ kg: '20', reps: '10', done: true }] } }; x.log[shift(-14)] = {} })
  d = produce(d, (x) => { freezePast(x, 'A'); x.programs.find((p) => p.id === 'A').blocks.push({ id: 'b3', kind: 'single', ex: ex('e3') }) })
  const past = programFor(d, shift(-7))
  eq(past.archived, true); eq(past.blocks.length, 1); eq(past.blocks[0].ex.id, 'e1', 'hareket id korunur')
  eq(programFor(d, today).blocks.length, 2); eq(programFor(d, shift(-14)).id, 'A', 'boş geçmiş gün dondurulmaz')
  const again = produce(d, (x) => freezePast(x, 'A'))
  eq(again.programs.length, d.programs.length, 'ikinci düzenleme yeni kopya açmaz')
})
t('tamamlandı işaretini kaldır: setler girilmiş olsa da tamamlanmamış sayılır', () => {
  let d = produce(base(), (x) => { x.log[today] = { sets: { e1: [{ done: true }, { done: true }, { done: true }] } } })
  const A = () => d.programs.find((p) => p.id === 'A')
  eq(workoutProgress(d, A(), today).complete, true)
  d = produce(d, (x) => uncompleteWorkout(x, today, 'A'))
  eq(workoutProgress(d, A(), today).complete, false)
  d = produce(d, (x) => completeWorkout(x, today, 'A'))
  eq(workoutProgress(d, A(), today).complete, true)
})
t('kutucuk: hepsi işaretlenince tamamlanır, biri kaldırılınca geri döner', () => {
  let d = base()
  const A = () => d.programs.find((p) => p.id === 'A')
  d = produce(d, (x) => toggleExDone(x, today, 'A', ex('e1')))
  eq(workoutProgress(d, A(), today).complete, true); eq(d.log[today].workoutDone, true)
  d = produce(d, (x) => toggleExDone(x, today, 'A', ex('e1')))
  eq(workoutProgress(d, A(), today).complete, false); eq(d.log[today].workoutDone, false)
})
t('hareketsiz program dinlenme sayılır', () => {
  const d = produce(base(), (x) => { x.programs.push({ id: 'E', name: '', blocks: [] }); assignDay(x, today, 'E', true) })
  eq(programFor(d, today), null); eq(assignedProgram(d, today).id, 'E')
  eq(shortOf(programFor(d, today)), '–'); eq(shortOf({ name: '' }), '–')
})

console.log(`${passed} geçti, ${failed} başarısız`)
if (failed) process.exitCode = 1
