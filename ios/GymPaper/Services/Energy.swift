import Foundation
import GymPaperKit

/// Daily energy figures from the profile and Health data
struct EnergySummary {
    var bmr: Double?
    var need: Double?            // daily need (TDEE)
    var target: Double           // target intake
    var eaten: Double
    var activeKcal: Double       // active calories burned today (Health or estimate)
    var activeSource: Source
    var workoutKcal: Double
    var missing: [String]        // details missing for the calculation
    enum Source { case health, estimate, none }
    var remaining: Double { target - eaten }
}

@MainActor
enum Energy {
    static func body(profile: UserProfile, health: HealthService, latestMeasureKg: Double?) -> (BodyProfile?, [String]) {
        var missing: [String] = []
        // whichever is newer wins: Health or the in-app measurement
        let healthNewer = (health.latestWeightAt ?? .distantPast) >= (Store.latestWeightAt ?? .distantPast)
        let kg = (healthNewer ? (health.latestWeightKg ?? latestMeasureKg) : (latestMeasureKg ?? health.latestWeightKg)) ?? profile.startKg
        let cm = health.heightCm ?? profile.heightCm
        let birth = health.birthDate ?? profile.birthDate
        let sex = health.sex ?? profile.sex
        if kg == nil { missing.append(tl("kilo")) }
        if cm == nil { missing.append(tl("boy")) }
        if birth == nil { missing.append(tl("doğum tarihi")) }
        if sex == nil { missing.append(tl("cinsiyet")) }
        guard let kg, let cm, let birth, let sex else { return (nil, missing) }
        return (BodyProfile(weightKg: kg, heightCm: cm, age: min(100, max(10, AgeCalc.age(birth: birth))), sex: sex), [])
    }

    static func summary(profile: UserProfile, health: HealthService, day: DayLog?, latestMeasureKg: Double?, isToday: Bool) -> EnergySummary {
        let (body, missing) = body(profile: profile, health: health, latestMeasureKg: latestMeasureKg)
        let eaten = day?.eaten.kcal ?? 0
        let workout = day?.workoutKcal ?? 0
        // active calories: Health > steps estimate (+ workout estimate)
        var active = 0.0, src = EnergySummary.Source.none
        if isToday, health.authorized, health.activeKcalToday > 0 { active = health.activeKcalToday; src = .health }
        else if let body {
            let steps = isToday && health.stepsToday > 0 ? health.stepsToday : (day?.steps ?? 0)
            active = CalorieEngine.stepsKcal(steps: steps, weightKg: body.weightKg) + workout
            src = steps > 0 || workout > 0 ? .estimate : .none
        }
        guard let body else {
            return EnergySummary(bmr: nil, need: nil, target: profile.manualKcal ?? 1800, eaten: eaten, activeKcal: active, activeSource: src, workoutKcal: workout, missing: missing)
        }
        let bmr = CalorieEngine.bmr(body)
        // The target comes only from basal metabolism × activity level; active calories from Health,
        // steps and workout calories are NOT added to it (shown for information only).
        let need = CalorieEngine.tdee(body, activity: profile.activity)
        let target = profile.manualKcal ?? CalorieEngine.dailyTarget(tdee: need, bmr: bmr, weeklyLossKg: profile.weeklyLossKg)
        return EnergySummary(bmr: bmr, need: need, target: target, eaten: eaten, activeKcal: active, activeSource: src, workoutKcal: workout, missing: [])
    }
}
