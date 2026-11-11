import Foundation

// "Snapshot" shared between the app and widgets (and the watch).
// Widgets don't open SwiftData/iCloud; the app writes this small JSON to the App Group on every change.

public struct WidgetWorkout: Codable, Equatable, Sendable {
    public var name: String
    public var exercises: [String]
    public var minutes: Int
    public var sets: Int
    public init(name: String, exercises: [String], minutes: Int, sets: Int) {
        self.name = name; self.exercises = exercises; self.minutes = minutes; self.sets = sets
    }
}

/// Weekly calendar day (Mon–Sun)
public struct WidgetWeekDay: Codable, Equatable, Sendable {
    public var date: String
    public var name: String?        // nil → dinlenme
    public var done: Bool
    public init(date: String, name: String?, done: Bool) { self.date = date; self.name = name; self.done = done }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var date: String                 // YYYY-MM-DD (day written)
    public var kcalTarget: Double
    public var kcalEaten: Double
    public var kcalActive: Double
    public var eaten: Macros
    public var goal: Macros                 // makro hedefleri (kcal = kcalTarget)
    public var waterMl: Int
    public var waterGoalMl: Int
    public var waterStepMl: Int
    public var workoutDone: Bool
    /// Workouts for the next 7 days (key: day). nil value → rest.
    public var workouts: [String: WidgetWorkout?]
    public var updatedAt: Date
    // added later (missing in old JSON → optional)
    public var stepsRaw: Int?
    public var stepGoalRaw: Int?
    public var week: [WidgetWeekDay]?
    /// Intermittent fasting schedule (nil when off)
    public var fast: FastPlan?
    /// Sets completed today (Lock Screen workout ring)
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

    /// Same snapshot with daily counters reset when looking at another day (after midnight)
    public func on(_ day: String) -> WidgetSnapshot {
        guard day != date else { return self }
        var s = self
        s.date = day; s.kcalEaten = 0; s.kcalActive = 0; s.eaten = .zero; s.waterMl = 0; s.workoutDone = false; s.stepsRaw = 0
        return s
    }

    /// That day's workout: .some(nil) rest, nil unknown
    public func workout(on day: String) -> WidgetWorkout?? { workouts[day] }
}

/// Snapshot + pending water added from the widget, in the App Group folder
public struct SharedStore: Sendable {
    public static let appGroup = AppConfig.appGroup
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

    /// The app, widgets and Health background delivery write the same files: cross-process lock
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
        // NaN/infinite values must not break the JSON
        func clean(_ x: Double) -> Double { x.isFinite ? x : 0 }
        s.kcalTarget = clean(s.kcalTarget); s.kcalEaten = clean(s.kcalEaten); s.kcalActive = clean(s.kcalActive)
        s.eaten = Macros(kcal: clean(s.eaten.kcal), p: clean(s.eaten.p), c: clean(s.eaten.c), f: clean(s.eaten.f))
        s.goal = Macros(kcal: clean(s.goal.kcal), p: clean(s.goal.p), c: clean(s.goal.c), f: clean(s.goal.f))
        guard let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Health-sourced values stay out of the iCloud backup
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        var uu = u; try? uu.setResourceValues(v)
    }

    public func write(_ s: WidgetSnapshot) { locked { rawWrite(s) } }

    private func writePending(_ p: [String: Int]) {
        guard let u = pendingURL else { return }
        if p.isEmpty { try? FileManager.default.removeItem(at: u); return }
        if let d = try? JSONEncoder().encode(p) { try? d.write(to: u, options: .atomic) }
    }

    /// Widget button: adds water to the snapshot right away and queues it for the app to apply.
    /// Without a snapshot (app never opened) it only queues; no fake data is created.
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

    /// Health background notification: updates steps only (without opening app data)
    @discardableResult
    public func setSteps(_ n: Int, day: String = DayKey.today) -> WidgetSnapshot? {
        guard dir != nil else { return nil }
        return locked {
            guard let old = read() else { return nil }
            var s = old.on(day)
            // a higher manual step count isn't overwritten by a lower background Health value
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

    /// When the app opens: take the pending items and clear the queue
    public func takePending() -> [String: Int] {
        locked {
            let p = pending()
            if !p.isEmpty { writePending([:]) }
            return p
        }
    }
}
