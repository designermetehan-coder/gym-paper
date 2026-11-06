import Foundation

// Kalori motoru: günlük ihtiyaç (BMR/TDEE), adım ve antrenman kalorisi, kilo hedefine göre günlük hedef.
// Saf hesap; HealthKit ya da arayüzden bağımsızdır, birim testleriyle doğrulanır.

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
    public var label: String { self == .male ? "Erkek" : "Kadın" }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive
    /// Mifflin-St Jeor ile kullanılan yaygın aktivite katsayıları
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
    /// 1 kg vücut yağı ≈ 7700 kcal
    public static let kcalPerKg = 7700.0

    /// Bazal metabolizma (Mifflin-St Jeor, kcal/gün)
    public static func bmr(_ p: BodyProfile) -> Double {
        10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age) + (p.sex == .male ? 5 : -161)
    }

    /// Tahmini günlük ihtiyaç (TDEE) — aktivite katsayısıyla
    public static func tdee(_ p: BodyProfile, activity: ActivityLevel) -> Double {
        bmr(p) * activity.factor
    }

    /// Ölçülen aktif enerjiyle günlük ihtiyaç: BMR + yemeğin termik etkisi (~%10) + gerçek aktif kalori
    public static func tdee(_ p: BodyProfile, activeKcal: Double) -> Double {
        bmr(p) * 1.1 + max(0, activeKcal)
    }

    /// Haftalık kilo verme hızına göre günlük kalori hedefi. Güvenlik için BMR'nin altına inmez.
    public static func dailyTarget(tdee: Double, bmr: Double, weeklyLossKg: Double) -> Double {
        let deficit = max(0, weeklyLossKg) * kcalPerKg / 7
        return max(bmr, tdee - deficit).rounded()
    }

    /// Adım kalorisi (Sağlık'ta aktif enerji yoksa tahmin): ~0,57 kcal / adım / 1000 kg
    /// 70 kg için 10.000 adım ≈ 400 kcal
    public static func stepsKcal(steps: Int, weightKg: Double) -> Double {
        Double(max(0, steps)) * weightKg * 0.00057
    }

    /// MET tabanlı antrenman kalorisi (net: dinlenik 1 MET düşülür, Apple'ın "aktif enerji"si gibi):
    /// kcal = (MET − 1) × 3,5 × kg / 200 × dakika. Varsayılan: setler arası dinlenme dahil ağırlık seansı (3,5 MET).
    public static func workoutKcal(minutes: Double, weightKg: Double, met: Double = Met.strengthSession) -> Double {
        max(0, met - 1) * 3.5 * weightKg / 200 * max(0, minutes)
    }

    /// Süre ölçülmediyse setlerden tahmini antrenman süresi (dakika): set başına ~40 sn iş + dinlenme
    public static func estimatedMinutes(sets: [(rest: Int, count: Int)]) -> Double {
        let seconds = sets.reduce(0) { $0 + $1.count * (40 + max(0, $1.rest)) }
        return Double(seconds) / 60
    }

    public enum Met {
        public static let strengthLight = 3.5
        /// Compendium 02054: dinlenmeler dahil ağırlık antrenmanı seansı
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
