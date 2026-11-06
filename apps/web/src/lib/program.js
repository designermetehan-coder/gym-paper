import { uid } from './utils'

// Ballı programı v2 — 4 gün ağırlık (Pzt İtiş · Sal Çekiş · Per Alt · Cum Üst), Çar/Cmt/Paz off.
// Hedef: yağ yakarken kas korumak; göğüs ve karın bölgesine ekstra hacim. Her gün sonunda 30 dk kardiyo.
const ex = (name, sets, reps, rest, m, o = {}) => ({ id: uid(), name, sets, reps, unit: o.unit || 'tekrar', rest, muscle: m, desc: o.d || '', note: o.n || '', video: '' })
const one = (e) => ({ id: uid(), kind: 'single', ex: e })
const ss = (tag, rounds, rest, exs, note = '') => ({ id: uid(), kind: 'superset', tag, rounds, rest, note, exs: exs.map((e) => ({ ...e, rest: 0 })) })
const walk = (name = 'Incline Treadmill Walk') => one(ex(name, 1, 30, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %8–12 · 5,5 km/s · 110–130 bpm nabız' }))

export const PROGRAM_VERSION = 2

export function programsV2() {
  const itis = { id: 'itis', name: 'İtiş', blocks: [
    ss('warm', 2, 30, [ex('Band Pull Apart', 2, 15, 0, 'Isınma'), ex('Band External Rotation', 2, 15, 0, 'Isınma')]),
    one(ex('Incline Dumbbell Press', 4, 10, 90, 'Göğüs', { n: '8–10 tekrar · ilk set ısınma', d: 'Sehpa 30°. Kürek kemiklerini geriye ve aşağı sabitle, dambılları göğüs hizasına kontrollü indir, dirsekler gövdeyle yaklaşık 45° açıda kalsın.' })),
    one(ex('Machine Chest Press', 3, 10, 75, 'Göğüs', { n: '10–12 tekrar' })),
    one(ex('Seated Dumbbell Shoulder Press', 3, 10, 75, 'Omuz', { n: '8–10 tekrar' })),
    ss(null, 3, 60, [ex('Cable Crossover', 3, 12, 0, 'Göğüs', { n: 'Tepe noktada 1 sn sık' }), ex('Dumbbell Lateral Raise', 3, 15, 0, 'Omuz')]),
    one(ex('Rope Push Down', 3, 12, 60, 'Triceps')),
    ss(null, 3, 45, [ex('Cable Crunch', 3, 15, 0, 'Karın'), ex('Plank', 3, 40, 0, 'Karın', { unit: 'sn' })]),
    walk(),
  ] }
  const cekis = { id: 'cekis', name: 'Çekiş', blocks: [
    ss('warm', 2, 30, [ex('Band Pull Apart', 2, 15, 0, 'Isınma'), ex('Prone Y Raise', 2, 12, 0, 'Isınma')]),
    one(ex('Lat Pull Down', 4, 10, 90, 'Sırt', { n: '8–10 tekrar · ilk set ısınma', d: 'Göğsünü kaldır, barı köprücük kemiğine doğru çek. Dirsekleri aşağı ve geriye sür, bel ile salınım yapma.' })),
    one(ex('Chest Supported Row', 3, 10, 75, 'Sırt', { n: '10–12 tekrar' })),
    one(ex('Seated Cable Row', 3, 12, 60, 'Sırt')),
    one(ex('Face Pull', 3, 15, 45, 'Omuz', { n: 'Duruş için; hafif kilo' })),
    ss(null, 3, 60, [ex('Hammer Curl', 3, 12, 0, 'Biceps'), ex('Incline Dumbbell Curl', 3, 12, 0, 'Biceps')]),
    ss(null, 3, 45, [ex('Hanging Leg Raise', 3, 12, 0, 'Karın', { n: 'Zorlanırsan dizleri bükerek yap' }), ex('Dead Bug', 3, 10, 0, 'Karın', { n: 'Her taraf' })]),
    walk(),
  ] }
  const alt = { id: 'alt', name: 'Alt Vücut', blocks: [
    ss('warm', 2, 30, [ex('Glute Bridge', 2, 15, 0, 'Isınma'), ex("World's Greatest Stretch", 2, 6, 0, 'Isınma', { n: 'Her taraf' })]),
    one(ex('Leg Press', 4, 10, 120, 'Bacak', { n: '10–12 tekrar · ilk set ısınma', d: 'Ayaklar kalça genişliğinde, platformun ortasında. Dizleri içe kaçırmadan 90°ye kadar indir, belini koltuktan kaldırma.' })),
    one(ex('Romanian Deadlift', 3, 10, 90, 'Bacak', { d: 'Dizler hafif bükük, kalçayı geriye iterek barı bacaklara yakın indir. Hamstring gerilince dur, sırt düz kalsın.' })),
    one(ex('Bulgarian Split Squat', 3, 10, 75, 'Bacak', { n: 'Her bacak' })),
    ss(null, 3, 60, [ex('Leg Extension', 3, 12, 0, 'Bacak'), ex('Seated Leg Curl', 3, 12, 0, 'Bacak')]),
    one(ex('Standing Calf Raise', 4, 15, 45, 'Baldır', { n: 'Tepe noktada 1 sn bekle' })),
    ss(null, 3, 45, [ex('Side Plank', 3, 30, 0, 'Karın', { unit: 'sn', n: 'Her taraf' }), ex('Russian Twist', 3, 20, 0, 'Karın')]),
    walk('Brisk Walking'),
    ss('cool', 1, 0, [ex('Hamstring Stretch', 1, 40, 0, 'Esneme', { unit: 'sn' }), ex('Pigeon Stretch', 1, 45, 0, 'Esneme', { unit: 'sn', n: 'Her taraf' })]),
  ] }
  const ust = { id: 'ust', name: 'Üst Vücut', blocks: [
    ss('warm', 2, 30, [ex('Band Internal Rotation', 2, 15, 0, 'Isınma'), ex('Band External Rotation', 2, 15, 0, 'Isınma')]),
    one(ex('Dumbbell Bench Press', 4, 10, 90, 'Göğüs', { n: '8–10 tekrar · ilk set ısınma' })),
    one(ex('Close Grip Lat Pull Down', 3, 12, 60, 'Sırt')),
    ss(null, 3, 60, [ex('Pec Deck Fly', 3, 12, 0, 'Göğüs'), ex('Reverse Pec Deck', 3, 15, 0, 'Omuz')]),
    one(ex('Machine Lateral Raise', 3, 15, 45, 'Omuz')),
    ss(null, 3, 60, [ex('Cable Curl', 3, 12, 0, 'Biceps'), ex('Overhead Cable Extension', 3, 12, 0, 'Triceps')]),
    ss(null, 3, 45, [ex('Leg Raise', 3, 15, 0, 'Karın'), ex('Crunch', 3, 20, 0, 'Karın')]),
    walk(),
    ss('cool', 1, 0, [ex('Chest Doorway Stretch', 1, 30, 0, 'Esneme', { unit: 'sn' }), ex('Child Pose', 1, 50, 0, 'Esneme', { unit: 'sn' })]),
  ] }
  return [itis, cekis, alt, ust]
}

export const SCHEDULE_V2 = { 0: 'itis', 1: 'cekis', 2: null, 3: 'alt', 4: 'ust', 5: null, 6: null }
export const CYCLE_V2 = ['itis', 'cekis', 'alt', 'ust']
export const NOTES_V2 = `Haftada 4 gün: Pzt İtiş · Sal Çekiş · Per Alt Vücut · Cum Üst Vücut. Çarşamba, Cumartesi ve Pazar off; off günlerde 10.000 adım yeterli.

İlerleme: Bir harekette bütün setlerde üst tekrar sayısına ulaştığında bir sonraki antrenmanda kiloyu 2,5 kg (dambılda 1–2 kg) artır.

Ağırlık seçimi: Çalışma setlerinde son 1–2 tekrar zorlasın ama form bozulmasın. İlk set her zaman daha hafif ısınma seti.

Süperset: Hareketleri arka arkaya yap, tur bitince belirtilen süre dinlen.

Her antrenmanın sonunda 30 dk eğimli yürüyüş var; kalori açığının büyük kısmı buradan ve adımdan geliyor.`

// Eş programı — yeni başlayan, yağ yakımı + sıkılaşma, kalça/bacak ve karın odaklı. Pzt/Sal/Per/Cum.
export function programsWife() {
  const altA = { id: uid(), name: 'Alt Vücut A · Kalça', blocks: [
    ss('warm', 2, 30, [ex('Glute Bridge', 2, 15, 0, 'Isınma'), ex('Cat Cow', 2, 8, 0, 'Isınma')]),
    one(ex('Leg Press', 3, 12, 90, 'Bacak', { n: 'İlk 2 hafta hafif kilo, formu öğren', d: 'Ayaklarını platformda kalça genişliğinde ve biraz yüksekte tut; kalça daha çok çalışır. Dizleri içe kaçırmadan indir, belini koltuktan kaldırma.' })),
    one(ex('Hip Thrust', 3, 12, 90, 'Kalça', { n: 'Başta makinede ya da tek dambılla', d: 'Sırtının üstünü sehpaya daya, ayaklar kalça genişliğinde. Kalçanı sıkarak gövde düz olana kadar kaldır, tepede 1 sn bekle.' })),
    one(ex('Seated Leg Curl', 3, 12, 60, 'Bacak')),
    one(ex('Hip Abduction Machine', 3, 15, 45, 'Kalça', { n: 'Hafif öne eğilirsen kalça daha çok çalışır' })),
    one(ex('Cable Kickback', 2, 12, 45, 'Kalça', { n: 'Her bacak' })),
    ss(null, 3, 45, [ex('Dead Bug', 3, 10, 0, 'Karın', { n: 'Her taraf' }), ex('Plank', 3, 30, 0, 'Karın', { unit: 'sn' })]),
    one(ex('Incline Treadmill Walk', 1, 25, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %6–10 · konuşabileceğin tempoda' })),
    ss('cool', 1, 0, [ex('Pigeon Stretch', 1, 40, 0, 'Esneme', { unit: 'sn', n: 'Her taraf' }), ex('Hamstring Stretch', 1, 30, 0, 'Esneme', { unit: 'sn' })]),
  ] }
  const ustA = { id: uid(), name: 'Üst Vücut A', blocks: [
    ss('warm', 2, 30, [ex('Band Pull Apart', 2, 15, 0, 'Isınma'), ex('Arm Circles', 2, 30, 0, 'Isınma', { unit: 'sn' })]),
    one(ex('Lat Pull Down', 3, 12, 75, 'Sırt', { n: 'İlk 2 hafta hafif kilo, formu öğren' })),
    one(ex('Machine Chest Press', 3, 12, 75, 'Göğüs')),
    one(ex('Seated Cable Row', 3, 12, 60, 'Sırt')),
    one(ex('Machine Shoulder Press', 3, 12, 60, 'Omuz')),
    ss(null, 2, 45, [ex('Dumbbell Curl', 2, 12, 0, 'Biceps'), ex('Rope Push Down', 2, 12, 0, 'Triceps')]),
    ss(null, 3, 45, [ex('Crunch', 3, 15, 0, 'Karın'), ex('Side Plank', 3, 20, 0, 'Karın', { unit: 'sn', n: 'Her taraf' })]),
    one(ex('Incline Treadmill Walk', 1, 25, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %6–10 · konuşabileceğin tempoda' })),
  ] }
  const altB = { id: uid(), name: 'Alt Vücut B · Bacak', blocks: [
    ss('warm', 2, 30, [ex('Glute Bridge', 2, 15, 0, 'Isınma'), ex("World's Greatest Stretch", 2, 5, 0, 'Isınma', { n: 'Her taraf' })]),
    one(ex('Goblet Squat', 3, 12, 90, 'Bacak', { n: 'Hafif dambılla başla', d: 'Dambılı göğsünde tut, ayaklar omuz genişliğinde. Kalçanı geriye ve aşağı gönder, dizler ayak uçlarıyla aynı yöne baksın; topuklarından iterek kalk.' })),
    one(ex('Romanian Deadlift', 3, 12, 90, 'Bacak', { n: 'Dambılla' })),
    one(ex('Walking Lunge', 2, 10, 75, 'Bacak', { n: 'Her bacak · önce ağırlıksız' })),
    one(ex('Leg Extension', 3, 12, 60, 'Bacak')),
    one(ex('Hip Adduction Machine', 2, 15, 45, 'Kalça')),
    ss(null, 3, 45, [ex('Leg Raise', 3, 12, 0, 'Karın', { n: 'Zorlanırsan dizleri bük' }), ex('Russian Twist', 3, 16, 0, 'Karın')]),
    one(ex('Incline Treadmill Walk', 1, 25, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %6–10 · konuşabileceğin tempoda' })),
    ss('cool', 1, 0, [ex('Quad Stretch', 1, 30, 0, 'Esneme', { unit: 'sn', n: 'Her taraf' }), ex('Lunge Stretch', 1, 30, 0, 'Esneme', { unit: 'sn', n: 'Her taraf' })]),
  ] }
  const ustB = { id: uid(), name: 'Üst Vücut B', blocks: [
    ss('warm', 2, 30, [ex('Band Pull Apart', 2, 15, 0, 'Isınma'), ex('Band External Rotation', 2, 12, 0, 'Isınma')]),
    one(ex('Assisted Pull Up', 3, 8, 90, 'Sırt', { n: 'Destek makinesi ya da bantla' })),
    one(ex('Incline Dumbbell Press', 3, 12, 75, 'Göğüs')),
    one(ex('One Arm Dumbbell Row', 3, 12, 60, 'Sırt', { n: 'Her kol' })),
    one(ex('Dumbbell Lateral Raise', 3, 12, 45, 'Omuz')),
    one(ex('Face Pull', 2, 15, 45, 'Omuz')),
    ss(null, 3, 45, [ex('Cable Crunch', 3, 15, 0, 'Karın'), ex('Dead Bug', 3, 10, 0, 'Karın', { n: 'Her taraf' })]),
    one(ex('Incline Treadmill Walk', 1, 25, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %6–10 · konuşabileceğin tempoda' })),
  ] }
  const list = [altA, ustA, altB, ustB]
  return { programs: list, schedule: { 0: altA.id, 1: ustA.id, 2: null, 3: altB.id, 4: ustB.id, 5: null, 6: null }, cycle: list.map((p) => p.id) }
}
export function programsMete() {
  const list = programsV2().map((p) => ({ ...p, id: uid() }))
  const by = Object.fromEntries(programsV2().map((p, i) => [p.id, list[i].id]))
  const schedule = Object.fromEntries(Object.entries(SCHEDULE_V2).map(([k, v]) => [k, v ? by[v] : null]))
  return { programs: list, schedule, cycle: list.map((p) => p.id) }
}


/* ---------- Geleneksel hazır programlar ---------- */
const warmUp = () => ss('warm', 2, 30, [ex('Band Pull Apart', 2, 15, 0, 'Isınma'), ex('Band External Rotation', 2, 12, 0, 'Isınma')])
const warmLow = () => ss('warm', 2, 30, [ex('Glute Bridge', 2, 15, 0, 'Isınma'), ex("World's Greatest Stretch", 2, 5, 0, 'Isınma', { n: 'Her taraf' })])
const warmFull = () => ss('warm', 2, 30, [ex('Glute Bridge', 2, 15, 0, 'Isınma'), ex('Band Pull Apart', 2, 15, 0, 'Isınma')])
const cardio = (dk = 20) => one(ex('Incline Treadmill Walk', 1, dk, 0, 'Kardiyo', { unit: 'dk', n: 'Eğim %6–10 · konuşabileceğin tempoda' }))
const S = (name, sets, reps, rest, m, o) => one(ex(name, sets, reps, rest, m, o))
const prog = (name, blocks) => ({ id: uid(), name, blocks })
const pack = (days) => { // days: {weekday: program}
  const list = [...new Set(Object.values(days))]
  const schedule = { 0: null, 1: null, 2: null, 3: null, 4: null, 5: null, 6: null }
  for (const [d, p] of Object.entries(days)) schedule[d] = p.id
  return { programs: list, schedule, cycle: list.map((p) => p.id) }
}

function fullBody() {
  const A = prog('Full Body A', [warmFull(),
    S('Goblet Squat', 3, 10, 90, 'Bacak'), S('Dumbbell Bench Press', 3, 10, 90, 'Göğüs'), S('Lat Pull Down', 3, 10, 75, 'Sırt'),
    S('Romanian Deadlift', 3, 10, 90, 'Bacak', { n: 'Dambılla' }), S('Seated Dumbbell Shoulder Press', 2, 12, 60, 'Omuz'),
    S('Plank', 3, 30, 45, 'Karın', { unit: 'sn' }), cardio(15)])
  const B = prog('Full Body B', [warmFull(),
    S('Leg Press', 3, 12, 90, 'Bacak'), S('Seated Cable Row', 3, 10, 75, 'Sırt'), S('Incline Dumbbell Press', 3, 10, 75, 'Göğüs'),
    S('Seated Leg Curl', 3, 12, 60, 'Bacak'), S('Dumbbell Lateral Raise', 2, 15, 45, 'Omuz'),
    ss(null, 3, 45, [ex('Dead Bug', 3, 10, 0, 'Karın', { n: 'Her taraf' }), ex('Crunch', 3, 15, 0, 'Karın')]), cardio(15)])
  return pack({ 0: A, 2: B, 4: A })
}
function upperLower() {
  const UA = prog('Üst Vücut A', [warmUp(),
    S('Barbell Bench Press', 4, 8, 120, 'Göğüs', { n: '6–8 tekrar' }), S('Barbell Row', 4, 8, 90, 'Sırt'), S('Overhead Press', 3, 10, 90, 'Omuz'),
    S('Lat Pull Down', 3, 10, 75, 'Sırt'), ss(null, 3, 60, [ex('Barbell Curl', 3, 12, 0, 'Biceps'), ex('Rope Push Down', 3, 12, 0, 'Triceps')])])
  const LA = prog('Alt Vücut A', [warmLow(),
    S('Back Squat', 4, 8, 120, 'Bacak', { n: '6–8 tekrar' }), S('Romanian Deadlift', 3, 10, 90, 'Bacak'), S('Leg Press', 3, 12, 90, 'Bacak'),
    S('Seated Leg Curl', 3, 12, 60, 'Bacak'), S('Standing Calf Raise', 3, 15, 45, 'Baldır'), S('Hanging Leg Raise', 3, 12, 45, 'Karın')])
  const UB = prog('Üst Vücut B', [warmUp(),
    S('Incline Dumbbell Press', 4, 10, 90, 'Göğüs'), S('Chest Supported Row', 3, 10, 75, 'Sırt'), S('Seated Dumbbell Shoulder Press', 3, 10, 75, 'Omuz'),
    S('Assisted Pull Up', 3, 8, 90, 'Sırt', { n: 'Yapabiliyorsan desteksiz' }),
    ss(null, 3, 45, [ex('Dumbbell Lateral Raise', 3, 15, 0, 'Omuz'), ex('Face Pull', 3, 15, 0, 'Omuz')]),
    ss(null, 3, 60, [ex('Hammer Curl', 3, 12, 0, 'Biceps'), ex('Overhead Cable Extension', 3, 12, 0, 'Triceps')])])
  const LB = prog('Alt Vücut B', [warmLow(),
    S('Deadlift', 3, 6, 150, 'Sırt'), S('Bulgarian Split Squat', 3, 10, 90, 'Bacak', { n: 'Her bacak' }), S('Hip Thrust', 3, 10, 90, 'Kalça'),
    S('Leg Extension', 3, 12, 60, 'Bacak'), S('Seated Calf Raise', 3, 15, 45, 'Baldır'), S('Cable Crunch', 3, 15, 45, 'Karın')])
  return pack({ 0: UA, 1: LA, 3: UB, 4: LB })
}
function pushPullLegs() {
  const P = prog('Push', [warmUp(),
    S('Barbell Bench Press', 4, 8, 120, 'Göğüs'), S('Incline Dumbbell Press', 3, 10, 90, 'Göğüs'), S('Overhead Press', 3, 10, 90, 'Omuz'),
    S('Cable Crossover', 3, 12, 60, 'Göğüs'), S('Dumbbell Lateral Raise', 3, 15, 45, 'Omuz'),
    ss(null, 3, 60, [ex('Rope Push Down', 3, 12, 0, 'Triceps'), ex('Overhead Cable Extension', 3, 12, 0, 'Triceps')])])
  const Pl = prog('Pull', [warmUp(),
    S('Lat Pull Down', 4, 10, 90, 'Sırt'), S('Barbell Row', 4, 8, 90, 'Sırt'), S('Seated Cable Row', 3, 12, 60, 'Sırt'),
    S('Face Pull', 3, 15, 45, 'Omuz'), ss(null, 3, 60, [ex('Barbell Curl', 3, 10, 0, 'Biceps'), ex('Hammer Curl', 3, 12, 0, 'Biceps')])])
  const L = prog('Legs', [warmLow(),
    S('Back Squat', 4, 8, 120, 'Bacak'), S('Romanian Deadlift', 3, 10, 90, 'Bacak'), S('Leg Press', 3, 12, 90, 'Bacak'),
    ss(null, 3, 60, [ex('Leg Extension', 3, 12, 0, 'Bacak'), ex('Lying Leg Curl', 3, 12, 0, 'Bacak')]),
    S('Standing Calf Raise', 4, 15, 45, 'Baldır'), S('Hanging Leg Raise', 3, 12, 45, 'Karın')])
  return pack({ 0: P, 2: Pl, 4: L })
}
function broSplit() {
  const G = prog('Göğüs', [warmUp(), S('Barbell Bench Press', 4, 8, 120, 'Göğüs'), S('Incline Dumbbell Press', 4, 10, 90, 'Göğüs'),
    S('Machine Chest Press', 3, 12, 75, 'Göğüs'), S('Pec Deck Fly', 3, 12, 60, 'Göğüs'), S('Chest Dips', 3, 10, 75, 'Göğüs'), S('Crunch', 3, 20, 45, 'Karın')])
  const Si = prog('Sırt', [warmUp(), S('Deadlift', 3, 6, 150, 'Sırt'), S('Lat Pull Down', 4, 10, 90, 'Sırt'), S('Barbell Row', 4, 8, 90, 'Sırt'),
    S('Seated Cable Row', 3, 12, 60, 'Sırt'), S('Straight Arm Pulldown', 3, 12, 60, 'Sırt'), S('Back Extension', 3, 12, 45, 'Sırt')])
  const O = prog('Omuz', [warmUp(), S('Overhead Press', 4, 8, 120, 'Omuz'), S('Arnold Press', 3, 10, 75, 'Omuz'), S('Dumbbell Lateral Raise', 4, 15, 45, 'Omuz'),
    S('Reverse Pec Deck', 3, 15, 45, 'Omuz'), S('Face Pull', 3, 15, 45, 'Omuz'), S('Dumbbell Shrug', 3, 12, 60, 'Omuz'), S('Plank', 3, 40, 45, 'Karın', { unit: 'sn' })])
  const B = prog('Bacak', [warmLow(), S('Back Squat', 4, 8, 120, 'Bacak'), S('Leg Press', 4, 12, 90, 'Bacak'), S('Romanian Deadlift', 3, 10, 90, 'Bacak'),
    S('Leg Extension', 3, 12, 60, 'Bacak'), S('Lying Leg Curl', 3, 12, 60, 'Bacak'), S('Standing Calf Raise', 4, 15, 45, 'Baldır')])
  const K = prog('Kol', [warmUp(),
    ss(null, 4, 60, [ex('Barbell Curl', 4, 10, 0, 'Biceps'), ex('Skull Crusher', 4, 10, 0, 'Triceps')]),
    ss(null, 3, 60, [ex('Hammer Curl', 3, 12, 0, 'Biceps'), ex('Rope Push Down', 3, 12, 0, 'Triceps')]),
    ss(null, 3, 60, [ex('Preacher Curl', 3, 12, 0, 'Biceps'), ex('Overhead Dumbbell Extension', 3, 12, 0, 'Triceps')]),
    S('Hanging Leg Raise', 3, 12, 45, 'Karın')])
  return pack({ 0: G, 1: Si, 2: O, 3: B, 4: K })
}
function strength5x5() {
  const n = { n: 'Her antrenmanda 2,5 kg ekle' }
  const A = prog('5×5 A', [warmFull(), S('Back Squat', 5, 5, 180, 'Bacak', n), S('Barbell Bench Press', 5, 5, 180, 'Göğüs', n), S('Barbell Row', 5, 5, 150, 'Sırt', n)])
  const B = prog('5×5 B', [warmFull(), S('Back Squat', 5, 5, 180, 'Bacak', n), S('Overhead Press', 5, 5, 180, 'Omuz', n), S('Deadlift', 1, 5, 180, 'Sırt', { n: 'Tek ağır set · 5 kg ekle' })])
  return pack({ 0: A, 2: B, 4: A })
}
function homeDumbbell() {
  const A = prog('Evde A', [warmFull(), S('Goblet Squat', 3, 12, 60, 'Bacak'), S('Push Up', 3, 10, 60, 'Göğüs', { n: 'Zorlanırsan dizler yerde' }),
    S('One Arm Dumbbell Row', 3, 12, 60, 'Sırt', { n: 'Her kol' }), S('Romanian Deadlift', 3, 12, 60, 'Bacak', { n: 'Dambılla' }),
    S('Seated Dumbbell Shoulder Press', 3, 10, 60, 'Omuz'), S('Plank', 3, 30, 45, 'Karın', { unit: 'sn' })])
  const B = prog('Evde B', [warmFull(), S('Walking Lunge', 3, 10, 60, 'Bacak', { n: 'Her bacak' }), S('Dumbbell Bench Press', 3, 10, 60, 'Göğüs', { n: 'Yerde ya da sehpada' }),
    S('Glute Bridge', 3, 15, 45, 'Kalça'), S('Dumbbell Lateral Raise', 3, 12, 45, 'Omuz'), S('Dumbbell Curl', 3, 12, 45, 'Biceps'),
    ss(null, 3, 45, [ex('Dead Bug', 3, 10, 0, 'Karın', { n: 'Her taraf' }), ex('Russian Twist', 3, 16, 0, 'Karın')])])
  return pack({ 0: A, 2: B, 4: A })
}

export const PROGRAM_TEMPLATES = [
  { key: 'blank', name: 'Boş', days: null, who: 'Kendi programını kuracak olan', split: 'Program yok; antrenmanları kendin eklersin.', fn: null },
  { key: 'fullbody', name: 'Full Body', days: 3, who: 'Yeni başlayan, zamanı kısıtlı olan', split: 'Pzt A · Çar B · Cum A (A ve B dönüşümlü)', fn: fullBody },
  { key: 'upperlower', name: 'Upper / Lower', days: 4, who: 'Başlangıç–orta seviye, dengeli gelişim', split: 'Pzt Üst · Sal Alt · Per Üst · Cum Alt', fn: upperLower },
  { key: 'ppl', name: 'Push / Pull / Legs', days: 3, who: 'Orta seviye', split: 'Pzt İtiş · Çar Çekiş · Cum Bacak', fn: pushPullLegs },
  { key: 'bro', name: 'Bro Split', days: 5, who: 'Orta–ileri seviye, kas gelişimi', split: 'Pzt Göğüs · Sal Sırt · Çar Omuz · Per Bacak · Cum Kol + karın', fn: broSplit },
  { key: '5x5', name: 'Güç 5×5', days: 3, who: 'Gücünü artırmak isteyen', split: 'A: Squat, Bench, Row · B: Squat, OHP, Deadlift', fn: strength5x5 },
  { key: 'esim', name: 'Kalça & Karın', days: 4, who: 'Sıkılaşma, kalça ve bacak odağı', split: 'Pzt Alt A · Sal Üst A · Per Alt B · Cum Üst B', fn: programsWife },
  { key: 'home', name: 'Evde Dambıl', days: 3, who: 'Salona gidemeyen, evde çalışan', split: 'Pzt A · Çar B · Cum A · dambıl ve vücut ağırlığı', fn: homeDumbbell },
]
export const templateFor = (key) => PROGRAM_TEMPLATES.find((t) => t.key === key)

// Gün kartı için kısa ad: program.short ya da addan türetilir ("Üst Vücut A" → "Üst A")
const SHORT_MAP = [
  [/alt v[uü]cut|bacak|legs?\b|squat/i, 'Bacak'], [/[uü]st v[uü]cut|upper/i, 'Üst'], [/alt|lower/i, 'Alt'],
  [/iti[sş]|push/i, 'İtiş'], [/[cç]eki[sş]|pull/i, 'Çekiş'], [/full ?body|t[uü]m v[uü]cut/i, 'Tüm'],
  [/kal[cç]a|glute/i, 'Kalça'], [/g[oö]ğ[uü]s|gogus|chest/i, 'Göğüs'], [/s[ıi]rt|back/i, 'Sırt'], [/omuz|shoulder/i, 'Omuz'],
  [/kol|arm|biceps|triceps/i, 'Kol'], [/kar[ıi]n|core|abs/i, 'Karın'], [/kardiyo|cardio|ko[sş]u/i, 'Kardiyo'],
]
export function shortOf(p) {
  if (!p) return '–'
  if (p.short?.trim()) return p.short.trim().slice(0, 10)
  const name = String(p.name || '').trim()
  if (!name) return '–'
  const letter = (name.match(/\s([A-D]|\d)$/) || [])[1]
  const hit = SHORT_MAP.find(([re]) => re.test(name))
  const base = hit ? hit[1] : (name.split(/\s+/)[0] || 'Antr.').slice(0, 7)
  return letter ? `${base} ${letter}` : base
}
