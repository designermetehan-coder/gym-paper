import Foundation
import SwiftData
import WidgetKit
import BalliKit

/// Widget'ların okuduğu anlık durumu yazar; widget'tan eklenen suyu veriye işler.
@MainActor
enum WidgetSync {
    private static var lastWritten: WidgetSnapshot?
    /// Son hesaplanan bazal metabolizma; saatteki kalori açığı göstergesine gider (WC-03)
    static var lastBmr: Double?

    /// Widget düğmesiyle eklenen su (uygulama kapalıyken) → günlük kayda
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

        // Programlar ve bu iki haftanın günleri tek sorguda (her kayıtta onlarca sorgu atılmasın — CR-30)
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

        // Bu hafta (Pzt–Paz): plan + yapıldı mı
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
        // Değişiklik yoksa widget'ları boşuna yenileme (günlük yenileme bütçesi sınırlı)
        if var last = lastWritten { last.updatedAt = s.updatedAt; if last == s { return } }
        s.updatedAt = .now
        SharedStore.shared.write(s)
        lastWritten = s
        WidgetCenter.shared.reloadAllTimelines()
        // Saat push'u çağıranlarda (kayıt, öne gelme, iCloud) yapılır; burada ikinci kez hesaplanmaz (PF-01)
    }

    /// Sağlık arka plan teslimi: adım değişince yalnız adım widget'larını yenile
    nonisolated static func pushSteps(_ n: Int) {
        guard SharedStore.shared.setSteps(n) != nil else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "balli.adim")
    }
}
