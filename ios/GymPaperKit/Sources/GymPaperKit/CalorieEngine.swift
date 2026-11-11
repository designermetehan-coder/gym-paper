import Foundation

// Calorie engine: daily need (BMR/TDEE), step and workout calories, daily target from the weight goal.
// Pure math; independent of HealthKit and UI, verified by unit tests.

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
    public var label: String { self == .male ? "Erkek" : "Kadın" }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive
    /// Common activity multipliers used with Mifflin-St Jeor
    public var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
    public var label: String {
        switch self {
        case .sedentary: "Hareketsiz (masa başı)"
        case .light: "Hafif (haftada 1–3 antrenman)"
        case .moderate: "Orta (haftada 3–5 antrenman)"
        case .active: "Yüksek (haftada 6–7 antrenman)"
        case .veryActive: "Çok yüksek (ağır iş + antrenman)"
        }
    }
}

public struct BodyProfile: Equatable, Sendable {
    public var weightKg: Double
    public var heightCm: Double
    public var age: Int
    public var sex: Sex
    public init(weightKg: Double, heightCm: Double, age: Int, sex: Sex) {
        self.weightKg = weightKg; self.heightCm = heightCm; self.age = age; self.sex = sex
    }
}

public enum CalorieEngine {
    /// 1 kg of body fat ≈ 7700 kcal
    public static let kcalPerKg = 7700.0

    /// Basal metabolic rate (Mifflin-St Jeor, kcal/day)
    public static func bmr(_ p: BodyProfile) -> Double {
        10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age) + (p.sex == .male ? 5 : -161)
    }

    /// Estimated daily need (TDEE) with the activity multiplier
    public static func tdee(_ p: BodyProfile, activity: ActivityLevel) -> Double {
        bmr(p) * activity.factor
    }

    /// Daily need from measured active energy: BMR + thermic effect of food (~10%) + actual active calories
    public static func tdee(_ p: BodyProfile, activeKcal: Double) -> Double {
        bmr(p) * 1.1 + max(0, activeKcal)
    }

    /// Daily calorie target from the weekly loss rate. Never below BMR, for safety.
    public static func dailyTarget(tdee: Double, bmr: Double, weeklyLossKg: Double) -> Double {
        let deficit = max(0, weeklyLossKg) * kcalPerKg / 7
        return max(bmr, tdee - deficit).rounded()
    }

    /// Step calories (estimate when Health has no active energy): ~0.57 kcal / step / 1000 kg
    /// 10,000 steps at 70 kg ≈ 400 kcal
    public static func stepsKcal(steps: Int, weightKg: Double) -> Double {
        Double(max(0, steps)) * weightKg * 0.00057
    }

    /// MET-based workout calories (net: resting 1 MET subtracted, like Apple's "active energy"):
    /// kcal = (MET − 1) × 3.5 × kg / 200 × minutes. Default: weight session including rest between sets (3.5 MET).
    public static func workoutKcal(minutes: Double, weightKg: Double, met: Double = Met.strengthSession) -> Double {
        max(0, met - 1) * 3.5 * weightKg / 200 * max(0, minutes)
    }

    /// Estimated workout duration from sets when it wasn't measured (minutes): ~40 s work per set + rest
    public static func estimatedMinutes(sets: [(rest: Int, count: Int)]) -> Double {
        let seconds = sets.reduce(0) { $0 + $1.count * (40 + max(0, $1.rest)) }
        return Double(seconds) / 60
    }
    /// With each set's own work time (a 15 min cardio counts 15 min, not one 40 s set)
    public static func estimatedMinutes(sets: [(rest: Int, count: Int, work: Int)]) -> Double {
        let seconds = sets.reduce(0) { $0 + $1.count * (max(0, $1.work) + max(0, $1.rest)) }
        return Double(seconds) / 60
    }

    public enum Met {
        public static let strengthLight = 3.5
        /// Compendium 02054: weight training session including rests
        public static let strengthSession = 3.5
        public static let strengthModerate = 5.0
        public static let strengthVigorous = 6.0
        public static let walking = 3.5
        public static let cardioModerate = 7.0
    }
}

public enum AgeCalc {
    public static func age(birth: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.year], from: birth, to: now).year ?? 0
    }
}
