// Haftalık plan geçmişi: [{ from: 'YYYY-MM-DD', days: {0..6: programId|null} }], from'a göre artan.
// Bir gün değişince yeni kayıt o tarihten başlar; önceki tarihler eski planı göstermeye devam eder.
export const EPOCH = '0000-01-01'

export function scheduleAt(db, date) {
  const H = db.scheduleHist
  if (!Array.isArray(H) || !H.length) return db.schedule || {}
  let cur = H[0]
  for (const h of H) if (h.from <= date) cur = h
  return cur.days || {}
}
