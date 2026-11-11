import Foundation

/// Weight suggestion (double progression).
/// Rule: `needed` (3) workouts in a row at the same weight with every working set at `repCap` (15) reps or more
/// → raise the weight by equipment (dumbbell +2, bar +2.5, machine/cable +5, kettlebell +4), target reps `resetReps` (8).
/// Otherwise the same weight. Never suggests less than the current working weight.
/// Assisted exercises (machine-assisted pull-up, dip) run the other way: the weight helps,
/// so progress means less assistance and the suggestion steps the weight down.
/// Pure logic: iPhone and watch get the same result.
public enum Progression {

    public struct Session: Sendable, Hashable {
        public var date: String
        public var sets: [Lift]
        public init(date: String, sets: [Lift]) { self.date = date; self.sets = sets }
    }
    public struct Lift: Sendable, Hashable {
        public var kg: Double
        public var reps: Int
        public init(kg: Double, reps: Int) { self.kg = kg; self.reps = reps }
    }
    public struct Suggestion: Sendable, Hashable {
        /// Suggested weight
        public var kg: Double
        /// Target reps after an increase (nil without one)
        public var reps: Int?
        /// Whether it suggests adding weight
        public var up: Bool
        /// Consecutive workouts at this weight that hit the target (15+) (0…needed)
        public var streak: Int
        public var needed: Int
        /// The weight is assistance (less is harder)
        public var assisted: Bool = false
    }

    public static let repCap = 15
    public static let needed = 3
    public static let resetReps = 8

    /// Increment by equipment (kg). nil for bodyweight / bands.
    public static func step(_ name: String) -> Double? {
        switch ExerciseAlternatives.equipment(name) {
        case .dumbbell: return 2
        case .barbell: return 2.5
        case .cable, .machine: return 5
        case .kettlebell: return 4
        case .band, .bodyweight: return nil
        case .other: return 2.5
        }
    }

    /// Assistance machines: the weight is help, so less weight is harder.
    /// "Göğüs destekli kürek" / "chest supported row" are not assisted; kettlebell "assisted" split squats carry the weight.
    public static func isAssisted(_ name: String) -> Bool {
        let n = TextNorm.norm(name)
        if n.contains("kettlebell") { return false }
        if n.contains("assist") { return true }
        guard n.contains("destekli") || n.contains("supported") else { return false }
        return ["barfiks", "pull", "chin", "dip"].contains { n.contains($0) }
    }

    /// Weight that counts as lifted: assisted → bodyweight − assistance (never below 0).
    public static func load(name: String, kg: Double, bodyweight: Double) -> Double {
        isAssisted(name) ? max(0, bodyweight - kg) : kg
    }

    /// Step for assisted exercises: a band has no kg, everything else drops 5 kg (machine plates).
    private static func assistStep(_ name: String) -> Double? {
        ExerciseAlternatives.equipment(name) == .band ? nil : (step(name) ?? 5)
    }

    /// - Parameters:
    ///   - history: earlier workouts of this exercise (oldest first); only completed sets with weight
    ///   - currentKg: weight in the program or entered in this workout (becomes the floor)
    public static func suggest(name: String, history: [Session], currentKg: Double? = nil,
                               repCap: Int = repCap, needed: Int = needed, resetReps: Int = resetReps) -> Suggestion? {
        let sessions = history.filter { !$0.sets.isEmpty }
        let assisted = isAssisted(name)
        // difficulty: heavier is harder, except for assistance (lighter is harder)
        let hard: (Double) -> Double = { assisted ? -$0 : $0 }
        var bases: [Double] = []
        if let last = sessions.last?.sets.map({ hard($0.kg) }).max() { bases.append(last) }
        if let cur = currentKg, cur > 0 { bases.append(hard(cur)) }
        guard let base = bases.max(), assisted || base > 0 else { return nil }
        // walking back: consecutive workouts at (or harder than) the floor weight with every working set at repCap+
        var streak = 0
        for s in sessions.reversed() {
            let top = s.sets.map { hard($0.kg) }.max() ?? 0
            guard top >= base - 0.01 else { break }
            let work = s.sets.filter { hard($0.kg) >= top - 0.01 }
            guard !work.isEmpty, work.allSatisfy({ $0.reps >= repCap }) else { break }
            streak += 1
            if streak >= needed { break }
        }
        let baseKg = hard(base)
        if assisted {
            if streak >= needed, let dec = assistStep(name), baseKg > 0.01 {
                return Suggestion(kg: round(max(0, baseKg - dec)), reps: resetReps, up: true, streak: streak, needed: needed, assisted: true)
            }
            return Suggestion(kg: round(baseKg), reps: nil, up: false, streak: min(streak, needed), needed: needed, assisted: true)
        }
        if streak >= needed, let inc = step(name) {
            return Suggestion(kg: round(baseKg + inc), reps: resetReps, up: true, streak: streak, needed: needed)
        }
        return Suggestion(kg: round(baseKg), reps: nil, up: false, streak: min(streak, needed), needed: needed)
    }

    private static func round(_ v: Double) -> Double { (v * 4).rounded() / 4 }
}
