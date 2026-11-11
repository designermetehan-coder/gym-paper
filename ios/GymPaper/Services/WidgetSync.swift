import Foundation
import SwiftData
import WidgetKit
import GymPaperKit

/// Writes the snapshot the widgets read; applies water added from the widget.
@MainActor
enum WidgetSync {
    private static var lastWritten: WidgetSnapshot?
    /// Last computed basal metabolism; feeds the watch's calorie deficit complication
    static var lastBmr: Double?

    /// Water added with the widget button (app closed) → daily log
    static func applyPending(ctx: ModelContext) {
        let p = SharedStore.shared.takePending()
        guard !p.isEmpty else { return }
        for (key, ml) in p { if let d = Store.day(ctx, key) { d.waterMl = max(0, d.waterMl + ml) } }
        Store.save(ctx)
    }

    static func update(ctx: ModelContext, health: HealthService) {
        guard SharedStore.shared.dir != nil else { return }   // App Group yoksa (Lite) atla
        let key = DayKey.today
        let profile = Store.profile(ctx)
        let day = Store.day(ctx, key, create: false)
        let e = Energy.summary(profile: profile, health: health, day: day, latestMeasureKg: Store.latestWeight(ctx), isToday: true)
        lastBmr = e.bmr

        // programs and these two weeks' days in one query (no dozens of queries per save)
        let progs = Dictionary(Store.programs(ctx, includeArchived: true).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let monday = DayKey.shift(key, days: -DayKey.weekday(key))
        let lastKey = DayKey.shift(key, days: 7)
        let rangeDays = (try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= monday && $0.date <= lastKey }))) ?? []
        func dayOf(_ k: String) -> DayLog? { rangeDays.day(k) }
        func progFor(_ k: String) -> WorkoutProgram? {
            let raw = dayOf(k)?.programIdRaw
            let id: String? = raw != nil ? (raw!.isEmpty ? nil : raw) : Schedule.programId(profile.schedule, date: k)
            return id.flatMap { progs[$0] }
        }
        var workouts: [String: WidgetWorkout?] = [:]
        for i in 0..<7 {
            let k = DayKey.shift(key, days: i)
            if let prog = progFor(k) {
                let mins = CalorieEngine.estimatedMinutes(sets: prog.blocks.restProfile)
                workouts[k] = .some(WidgetWorkout(name: prog.name, exercises: prog.blocks.allExercises.map(\.name),
                                                  minutes: Int(mins.rounded()), sets: prog.blocks.setCount))
            } else {
                workouts[k] = .some(nil)
            }
        }

        // this week (Mon–Sun): plan + done or not
        let week: [WidgetWeekDay] = (0..<7).map { i in
            let k = DayKey.shift(monday, days: i)
            return WidgetWeekDay(date: k, name: progFor(k)?.name, done: dayOf(k)?.workoutDone ?? false)
        }

        var s = WidgetSnapshot(
            date: key, kcalTarget: e.target, kcalEaten: e.eaten, kcalActive: e.activeKcal,
            eaten: day?.eaten ?? .zero,
            goal: Macros(kcal: e.target, p: profile.proteinG, c: profile.carbsG, f: profile.fatG),
            waterMl: day?.waterMl ?? 0, waterGoalMl: profile.waterMl, waterStepMl: profile.waterStepMl,
            workoutDone: day?.workoutDone ?? false, workouts: workouts,
            steps: max(day?.steps ?? 0, health.stepsToday), stepGoal: profile.stepGoal, week: week)
        s.fast = profile.fastOn ? profile.fast : nil
        if let prog = progFor(key), let d = dayOf(key) {
            let ids = Set(prog.blocks.allExercises.map(\.id))
            let n = d.sets.filter { ids.contains($0.key) }.reduce(0) { $0 + $1.value.filter(\.done).count }
            s.setsDoneRaw = min(n, prog.blocks.setCount)
        }
        // don't refresh widgets for nothing when unchanged (daily refresh budget is limited)
        if var last = lastWritten { last.updatedAt = s.updatedAt; if last == s { return } }
        s.updatedAt = .now
        SharedStore.shared.write(s)
        lastWritten = s
        WidgetCenter.shared.reloadAllTimelines()
        // the watch push is done by the callers (save, foreground, iCloud); not computed twice here
    }

    /// Health background delivery: refresh only the step widgets when steps change
    nonisolated static func pushSteps(_ n: Int) {
        guard SharedStore.shared.setSteps(n) != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "gympaper.adim")
    }
}
