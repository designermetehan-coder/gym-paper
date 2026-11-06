import Foundation

// Uygulama ↔ widget (ve ileride saat) arasında paylaşılan "anlık durum".
// Widget SwiftData/iCloud açmaz; uygulama her değişiklikte bu küçük JSON'u App Group'a yazar.

public struct WidgetWorkout: Codable, Equatable, Sendable {
    public var name: String
    public var exercises: [String]
    public var minutes: Int
    public var sets: Int
    public init(name: String, exercises: [String], minutes: Int, sets: Int) {
        self.name = name; self.exercises = exercises; self.minutes = minutes; self.sets = sets
    }
}

/// Haftalık takvim günü (Pzt–Paz)
public struct WidgetWeekDay: Codable, Equatable, Sendable {
    public var date: String
    public var name: String?        // nil → dinlenme
    public var done: Bool
    public init(date: String, name: String?, done: Bool) { self.date = date; self.name = name; self.done = done }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var date: String                 // YYYY-MM-DD (yazıldığı gün)
    public var kcalTarget: Double
    public var kcalEaten: Double
    public var kcalActive: Double
    public var eaten: Macros
    public var goal: Macros                 // makro hedefleri (kcal = kcalTarget)
    public var waterMl: Int
    public var waterGoalMl: Int
    public var waterStepMl: Int
    public var workoutDone: Bool
    /// Önümüzdeki 7 günün antrenmanı (anahtar: gün). Değer nil → dinlenme.
    public var workouts: [String: WidgetWorkout?]
    public var updatedAt: Date
    // Sonradan eklenenler (eski JSON'da yok → isteğe bağlı)
    public var stepsRaw: Int?
    public var stepGoalRaw: Int?
    public var week: [WidgetWeekDay]?
    /// Aralıklı oruç programı (kapalıysa nil)
    public var fast: FastPlan?
    /// Bugün tamamlanan set sayısı (kilit ekranı antrenman halkası)
    public var setsDoneRaw: Int?
    public var setsDone: Int { setsDoneRaw ?? 0 }
    public var steps: Int { stepsRaw ?? 0 }
    public var stepGoal: Int { max(1, stepGoalRaw ?? 10_000) }

    public init(date: String, kcalTarget: Double, kcalEaten: Double, kcalActive: Double, eaten: Macros, goal: Macros,
                waterMl: Int, waterGoalMl: Int, waterStepMl: Int, workoutDone: Bool, workouts: [String: WidgetWorkout?], steps: Int? = nil, stepGoal: Int? = nil, week: [WidgetWeekDay]? = nil, updatedAt: Date = .now) {
        self.date = date; self.kcalTarget = kcalTarget; self.kcalEaten = kcalEaten; self.kcalActive = kcalActive
        self.eaten = eaten; self.goal = goal; self.waterMl = waterMl; self.waterGoalMl = waterGoalMl; self.waterStepMl = waterStepMl
        self.workoutDone = workoutDone; self.workouts = workouts; self.updatedAt = updatedAt
        self.stepsRaw = steps; self.stepGoalRaw = stepGoal; self.week = week
    }

    public static let placeholder = WidgetSnapshot(
        date: DayKey.today, kcalTarget: 2000, kcalEaten: 1240, kcalActive: 320,
        eaten: Macros(kcal: 1240, p: 92, c: 120, f: 40), goal: Macros(kcal: 2000, p: 140, c: 160, f: 60),
        waterMl: 1500, waterGoalMl: 2500, waterStepMl: 500, workoutDone: false,
        workouts: [DayKey.today: WidgetWorkout(name: "Üst vücut", exercises: ["Bench press", "Barfiks", "Omuz press", "Biceps curl"], minutes: 55, sets: 16)],
        steps: 6420, stepGoal: 10_000,
        week: (0..<7).map { i in
            let k = DayKey.shift(DayKey.today, days: i - DayKey.weekday(DayKey.today))
            let name: String? = [0, 2, 4].contains(i) ? "Üst vücut" : (i == 1 || i == 3 ? "Alt vücut" : nil)
            return WidgetWeekDay(date: k, name: name, done: name != nil && k < DayKey.today)
        })

    public var remaining: Double { kcalTarget - kcalEaten }

    /// Başka bir güne bakılırken (gece yarısı geçtiyse) günlük sayaçlar sıfırlanmış hâli
    public func on(_ day: String) -> WidgetSnapshot {
        guard day != date else { return self }
        var s = self
        s.date = day; s.kcalEaten = 0; s.kcalActive = 0; s.eaten = .zero; s.waterMl = 0; s.workoutDone = false; s.stepsRaw = 0
        return s
    }

    /// O günün antrenmanı: .some(nil) dinlenme, nil bilinmiyor
    public func workout(on day: String) -> WidgetWorkout?? { workouts[day] }
}

/// App Group klasöründe anlık durum + widget'tan gelen bekleyen su eklemeleri
public struct SharedStore: Sendable {
    public static let appGroup = "group.com.metehankaya.balli"
    public static var shared: SharedStore {
        #if canImport(Darwin)
        SharedStore(dir: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup))
        #else
        SharedStore(dir: nil)
        #endif
    }

    public let dir: URL?
    public init(dir: URL?) { self.dir = dir }

    private var snapURL: URL? { dir?.appendingPathComponent("snapshot.json") }
    private var pendingURL: URL? { dir?.appendingPathComponent("pending-water.json") }

    public func read() -> WidgetSnapshot? {
        guard let u = snapURL, let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    /// Uygulama, widget ve Sağlık arka plan teslimi aynı dosyalara yazar: süreçler arası kilit (WG-04/05)
    private func locked<T>(_ body: () -> T) -> T {
        #if canImport(Darwin)
        guard let dir else { return body() }
        var out: T?
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: dir.appendingPathComponent(".lock"), options: [], error: &err) { _ in out = body() }
        return out ?? body()
        #else
        return body()
        #endif
    }

    private func rawWrite(_ s: WidgetSnapshot) {
        guard let u = snapURL else { return }
        var s = s
        // NaN/sonsuz değer JSON'u bozmasın (WG-12)
        func clean(_ x: Double) -> Double { x.isFinite ? x : 0 }
        s.kcalTarget = clean(s.kcalTarget); s.kcalEaten = clean(s.kcalEaten); s.kcalActive = clean(s.kcalActive)
        s.eaten = Macros(kcal: clean(s.eaten.kcal), p: clean(s.eaten.p), c: clean(s.eaten.c), f: clean(s.eaten.f))
        s.goal = Macros(kcal: clean(s.goal.kcal), p: clean(s.goal.p), c: clean(s.goal.c), f: clean(s.goal.f))
        guard let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Sağlık kaynaklı değerler iCloud yedeğine girmesin (RL-13)
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        var uu = u; try? uu.setResourceValues(v)
    }

    public func write(_ s: WidgetSnapshot) { locked { rawWrite(s) } }

    private func writePending(_ p: [String: Int]) {
        guard let u = pendingURL else { return }
        if p.isEmpty { try? FileManager.default.removeItem(at: u); return }
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: u, options: .atomic) }
    }

    /// Widget düğmesi: suyu hemen anlık duruma ekler ve uygulamanın işlemesi için kuyruğa yazar.
    /// Anlık durum yoksa (uygulama hiç açılmadı) yalnız kuyruğa yazar; sahte veri oluşturmaz (WG-06).
    @discardableResult
    public func addWater(_ ml: Int? = nil, day: String = DayKey.today) -> WidgetSnapshot? {
        guard dir != nil else { return nil }
        return locked {
            let snap = read()?.on(day)
            let step = ml ?? max(50, snap?.waterStepMl ?? 250)
            var p = pending()
            p[day, default: 0] += step
            writePending(p)
            guard var s = snap else { return nil }
            s.waterMl = max(0, s.waterMl + step)
            s.updatedAt = .now
            rawWrite(s)
            return s
        }
    }

    /// Sağlık arka plan bildirimi: yalnız adımı günceller (uygulama verisi açılmadan)
    @discardableResult
    public func setSteps(_ n: Int, day: String = DayKey.today) -> WidgetSnapshot? {
        guard dir != nil else { return nil }
        return locked {
            guard let old = read() else { return nil }
            var s = old.on(day)
            // Elle girilen daha yüksek adım, arka plandaki düşük Sağlık değeriyle ezilmesin (CR-35)
            let v = max(n, s.stepsRaw ?? 0)
            guard s.stepsRaw != v else { return nil }
            s.stepsRaw = v; s.updatedAt = .now
            rawWrite(s)
            return s
        }
    }

    public func pending() -> [String: Int] {
        guard let u = pendingURL, let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: d)) ?? [:]
    }

    /// Uygulama açılınca: bekleyenleri al ve kuyruğu temizle
    public func takePending() -> [String: Int] {
        locked {
            let p = pending()
            if !p.isEmpty { writePending([:]) }
            return p
        }
    }
}
