import Foundation
import SwiftData
import BalliKit

// PWA src/lib/gamify.js + store.goalState karşılığı (seri, haftalık skor, kilo kademeleri).

/// Oyunlaştırma girdisi: günlük kayıtlar + hedefler
struct GamifyInput {
    var logs: [String: DayLog]
    var stepGoal: Int
    var proteinGoal: Double
    var waterGoal: Int
    /// ISO hafta → dondurulan gün (kalıcı; AppStorage)
    var freezes: [String: String]
    /// O gün planlı (hareketli) antrenman var mı
    var plannedOn: (String) -> Bool
    /// Bugünün adımı Sağlık'tan geliyorsa (kayda yazılmamış olabilir)
    var todayKey: String = DayKey.today
    var todaySteps: Int? = nil

    func steps(_ k: String) -> Int {
        let s = logs[k]?.steps ?? 0
        return k == todayKey ? max(s, todaySteps ?? 0) : s
    }
    func isActive(_ k: String) -> Bool {
        if k == todayKey, (todaySteps ?? 0) >= max(1, stepGoal) { return true }
        guard let L = logs[k] else { return false }
        return !L.entries.isEmpty || L.workoutDone || L.steps >= max(1, stepGoal)
    }
}

enum Gamify {
    /// ISO hafta anahtarı "2026-W43"
    static func isoWeek(_ k: String) -> String {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
        guard let d = DayKey.date(k) else { return "" }
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    struct Streak { var count: Int; var activeToday: Bool; var frozen: [String]; var pending: [String: String]; var freezeReady: Bool }

    /// GM-02 Seri: bugün ya da dün biten ardışık aktif günler; her ISO haftada 1 dondurma tek boş günü köprüler
    static func streak(_ x: GamifyInput, today: String) -> Streak {
        var used = x.freezes
        var pending: [String: String] = [:]
        var frozen: [String] = []
        let activeToday = x.isActive(today)
        let earliest = x.logs.keys.min()
        var k = activeToday ? today : DayKey.shift(today, days: -1)
        var count = 0
        var i = 0
        while i < 800, let e = earliest, k >= e {
            i += 1
            if x.isActive(k) { count += 1; k = DayKey.shift(k, days: -1); continue }
            let w = isoWeek(k)
            let can = (used[w] == k || used[w] == nil) && count > 0 && x.isActive(DayKey.shift(k, days: -1))
            if !can { break }
            if used[w] == nil { used[w] = k; pending[w] = k }
            frozen.append(k); count += 1; k = DayKey.shift(k, days: -1)
        }
        return Streak(count: count, activeToday: activeToday, frozen: frozen, pending: pending, freezeReady: used[isoWeek(today)] == nil)
    }

    struct CalDay: Identifiable { var k: String; var active: Bool; var frozen: Bool; var id: String { k } }

    struct ScorePart: Identifiable { var key: String; var label: String; var w: Int; var v: Double?; var detail: String; var id: String { key } }
    struct WeekScore { var score: Int; var parts: [ScorePart]; var from: String; var to: String; var prev: Int = 0; var delta: Int = 0 }

    /// GM-04 Haftalık skor: antrenman %35, protein %35, su %15, adım %15
    static func weekScore(_ x: GamifyInput, end: String) -> WeekScore {
        let days = (0..<7).map { DayKey.shift(end, days: $0 - 6) }
        var planned = 0, done = 0, prot = 0, water = 0, steps = 0
        for k in days {
            let L = x.logs[k]
            if x.plannedOn(k) { planned += 1 }
            if L?.workoutDone == true { done += 1 }
            if x.proteinGoal > 0, (L?.eaten.p ?? 0) >= 0.9 * x.proteinGoal { prot += 1 }
            if x.waterGoal > 0, (L?.waterMl ?? 0) >= x.waterGoal { water += 1 }
            if x.stepGoal > 0, x.steps(k) >= x.stepGoal { steps += 1 }
        }
        let parts = [
            ScorePart(key: "workout", label: "Antrenman", w: 35, v: planned > 0 ? min(1, Double(done) / Double(planned)) : nil, detail: planned > 0 ? "\(done)/\(planned) gün" : "Plan yok"),
            ScorePart(key: "protein", label: "Protein", w: 35, v: Double(prot) / 7, detail: "\(prot)/7 gün"),
            ScorePart(key: "water", label: "Su", w: 15, v: Double(water) / 7, detail: "\(water)/7 gün"),
            ScorePart(key: "steps", label: "Adım", w: 15, v: Double(steps) / 7, detail: "\(steps)/7 gün"),
        ]
        let act = parts.filter { $0.v != nil }
        var wSum = 0.0, vSum = 0.0
        for p in act {
            let w = Double(p.w)
            wSum += w
            vSum += (p.v ?? 0) * w
        }
        let ratio: Double = vSum / max(1.0, wSum)
        let score = Int((ratio * 100).rounded())
        return WeekScore(score: score, parts: parts, from: days[0], to: end)
    }

    /// GM-03 Ulaşılan ama kutlanmamış hedefler (en düşük önce)
    static func pendingGoals(goals: [Double], celebrated: Set<Double>, cur: Double?, hasMeasure: Bool) -> [Double] {
        guard let cur, hasMeasure else { return [] }
        return goals.filter { cur <= $0 && !celebrated.contains($0) }.sorted()
    }
}

/// store.goalState: kilo kademeleri
struct GoalState {
    struct Pt: Identifiable { var date: Date; var kg: Double; var id: Date { date } }
    var start: Double?
    var cur: Double?
    var goals: [Double]          // büyükten küçüğe
    var active: Double?
    var idx: Int = 0
    var done = false
    var pct: Double = 0
    var left: Double = 0
    var lost: Double = 0
    var pts: [Pt]

    init(startKg: Double?, goals g: [Double], measures: [BodyMeasure]) {
        pts = measures.compactMap { m in m.kg.map { Pt(date: m.date, kg: $0) } }.sorted { $0.date < $1.date }
        start = startKg ?? pts.first?.kg
        cur = pts.last?.kg ?? start
        goals = g.sorted(by: >)
        guard let cur else { active = goals.first; return }
        var i = goals.firstIndex { cur > $0 }
        done = i == nil && !goals.isEmpty
        if i == nil { i = goals.count - 1 }
        idx = max(0, i ?? 0)
        active = goals.indices.contains(idx) ? goals[idx] : nil
        let from = idx > 0 ? goals[idx - 1] : (start ?? cur)
        if let a = active {
            let span = (from - a) == 0 ? 1 : (from - a)
            pct = done ? 1 : max(0, min(1, (from - cur) / span))
            left = max(0, cur - a)
        }
        lost = start.map { $0 - cur } ?? 0
    }
}
