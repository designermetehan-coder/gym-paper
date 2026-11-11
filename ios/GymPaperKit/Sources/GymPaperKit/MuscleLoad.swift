import Foundation

/// Muscle load: how much each area works.
/// The primary muscle counts 1 per set, secondary ½. Levels: light / moderate / hard / max.
/// Pure logic; workout detail, builder, finished workout and the weekly view share the result.
public enum MuscleLoad {

    /// Areas painted on the map (same as the library's muscle names)
    public static let groups = ["Göğüs", "Sırt", "Omuz", "Biceps", "Triceps", "Ön kol", "Karın", "Bacak", "Kalça", "Baldır", "Boyun"]

    public enum Level: Int, Sendable, Comparable, CaseIterable {
        case none = 0, light, moderate, hard, max
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public enum Scope: Sendable { case workout, week }

    public struct Item: Sendable, Hashable {
        public var name: String
        public var muscle: String
        public var sets: Double
        public init(name: String, muscle: String, sets: Double) { self.name = name; self.muscle = muscle; self.sets = sets }
    }

    public struct Entry: Sendable, Hashable, Identifiable {
        public var muscle: String
        public var sets: Double
        public var level: Level
        public var id: String { muscle }
    }

    /// Secondary muscles of an exercise (keyword rules on the name + primary muscle)
    public static func secondary(name: String, muscle: String) -> [String] {
        let n = " " + TextNorm.norm(name) + " "
        func has(_ k: [String]) -> Bool { k.contains { n.contains($0) } }
        let m = canonical(muscle)
        var out: [String] = []
        switch m {
        case "Göğüs":
            if has(["fly", "crossover", "pec deck", "kelebek", "pullover"]) { out = ["Omuz"] }
            else if has(["dip"]) { out = ["Triceps", "Omuz"] }
            else { out = ["Triceps", "Omuz"] }      // press, push-up
        case "Sırt":
            if has(["deadlift", "olu ", "good morning", "back extension", "hyperextension", "superman"]) { out = ["Kalça", "Bacak"] }
            else if has(["shrug"]) { out = ["Ön kol"] }
            else if has(["pullover", "straight arm"]) { out = [] }
            else { out = ["Biceps", "Ön kol"] }     // row, pulldown, barfiks
        case "Omuz":
            if has(["press", "pres", "push press", "arnold", "handstand"]) { out = ["Triceps"] }
            else if has(["upright", "dik cekis"]) { out = ["Sırt"] }
            else if has(["face pull", "rear", "reverse fly", "arka"]) { out = ["Sırt"] }
        case "Biceps":
            if has(["hammer", "cekic", "reverse", "zottman"]) { out = ["Ön kol"] }
            else if has(["chin up", "chinup"]) { out = ["Sırt"] }
        case "Triceps":
            if has(["close grip", "dar tutus", "dip", "diamond", "elmas"]) { out = ["Göğüs", "Omuz"] }
        case "Bacak":
            if has(["leg extension", "extension", "leg curl", "curl", "adductor", "abductor"]) { out = [] }
            else if has(["romanian", "rdl", "stiff", "deadlift", "good morning"]) { out = ["Kalça", "Sırt"] }
            else { out = ["Kalça"] }                // squat, lunge, leg press, step up
        case "Kalça":
            if has(["kickback", "abduction", "abductor", "clam", "fire hydrant"]) { out = [] }
            else { out = ["Bacak"] }                // hip thrust, bridge, split squat
        default: break
        }
        return out.filter { $0 != m }
    }

    /// Muscle name → map group ("Gogus", "gögüs" etc. → "Göğüs"); unknown returns empty
    public static func canonical(_ muscle: String) -> String {
        let k = TextNorm.norm(muscle)
        if let g = groups.first(where: { TextNorm.norm($0) == k }) { return g }
        return aliases[k] ?? ""
    }
    /// Hand-typed or English muscle names in programs
    static let aliases: [String: String] = [
        "chest": "Göğüs", "pecs": "Göğüs", "back": "Sırt", "lats": "Sırt", "bel": "Sırt", "lower back": "Sırt", "traps": "Sırt",
        "shoulder": "Omuz", "shoulders": "Omuz", "delts": "Omuz", "forearm": "Ön kol", "forearms": "Ön kol",
        "kol": "Biceps", "arms": "Biceps", "arm": "Biceps", "pazu": "Biceps", "arka kol": "Triceps",
        "abs": "Karın", "core": "Karın",
        "legs": "Bacak", "leg": "Bacak", "quads": "Bacak", "quadriceps": "Bacak", "on bacak": "Bacak", "arka bacak": "Bacak", "hamstring": "Bacak", "hamstrings": "Bacak",
        "glutes": "Kalça", "glute": "Kalça", "calves": "Baldır", "calf": "Baldır", "neck": "Boyun",
    ]

    /// Exercise list → sets per muscle (primary 1, secondary ½), highest first
    public static func load(_ items: [Item], scope: Scope) -> [Entry] {
        var by: [String: Double] = [:]
        for it in items where it.sets > 0 {
            let m = canonical(it.muscle)
            guard !m.isEmpty else { continue }
            by[m, default: 0] += it.sets
            for s in secondary(name: it.name, muscle: m) { by[s, default: 0] += it.sets * 0.5 }
        }
        return by.map { Entry(muscle: $0.key, sets: $0.value, level: level($0.value, scope)) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : (groups.firstIndex(of: $0.muscle) ?? 99) < (groups.firstIndex(of: $1.muscle) ?? 99) }
    }

    /// Level thresholds. Workout: ≤1½ light, 2–2½ moderate, 3–4 hard, 4½+ max.
    /// Week (Figma volume legend): 1–4, 5–9, 10–20, 20+ sets
    public static func level(_ sets: Double, _ scope: Scope) -> Level {
        guard sets > 0 else { return .none }
        switch scope {
        case .workout: return sets <= 1.5 ? .light : sets <= 2.5 ? .moderate : sets <= 4 ? .hard : .max
        case .week: return sets < 5 ? .light : sets < 10 ? .moderate : sets <= 20 ? .hard : .max
        }
    }

    /// "1½", "3", "½"
    public static func format(_ v: Double) -> String {
        let whole = Int(v.rounded(.down)), half = v - Double(whole) >= 0.5
        if whole == 0 { return half ? "½" : "0" }
        return half ? "\(whole)½" : "\(whole)"
    }

    // MARK: Missing area

    public struct Gap: Sendable, Hashable {
        public var muscle: String
        /// Reason: this area is empty/light while its antagonist is loaded
        public var because: String?
    }

    /// Missing area (at most one suggestion).
    /// - Workout: no core at all with at least 6 sets; or one side empty while its antagonist is hard (Chest↔Back, Biceps↔Triceps, Legs→Glutes).
    ///   With `week` (the week's plan including this workout), an area that gets work on another day of the week is not suggested:
    ///   a leg day without core is fine when core has its own day (split programs).
    /// - Week: a main area with no work after at least 2 workouts (priority: Legs, Back, Chest, Shoulders, Glutes, Core, Calves).
    public static func gap(_ entries: [Entry], scope: Scope, workouts: Int = 1, week: [Entry]? = nil) -> Gap? {
        let v = Dictionary(uniqueKeysWithValues: entries.map { ($0.muscle, $0.sets) })
        let total = entries.reduce(0) { $0 + $1.sets }
        let elsewhere = Dictionary(uniqueKeysWithValues: (week ?? []).map { ($0.muscle, $0.sets) })
        func trainedThisWeek(_ m: String) -> Bool { (elsewhere[m] ?? 0) > 0 }
        switch scope {
        case .workout:
            for (a, b) in [("Göğüs", "Sırt"), ("Sırt", "Göğüs"), ("Bacak", "Kalça"), ("Biceps", "Triceps"), ("Triceps", "Biceps")]
            where (v[a] ?? 0) >= 3 && (v[b] ?? 0) == 0 && !trainedThisWeek(b) { return Gap(muscle: b, because: a) }
            if total >= 6 && (v["Karın"] ?? 0) == 0 && !trainedThisWeek("Karın") { return Gap(muscle: "Karın", because: nil) }
            return nil
        case .week:
            guard workouts >= 2 else { return nil }
            return ["Bacak", "Sırt", "Göğüs", "Omuz", "Kalça", "Karın", "Baldır"].first { (v[$0] ?? 0) == 0 }.map { Gap(muscle: $0, because: nil) }
        }
    }

    /// Exercise to suggest for a missing area: done before → known default → first in the library
    public static let defaults: [String: [String]] = [
        "Karın": ["Plank", "Crunch", "Hanging Leg Raise"],
        "Sırt": ["Seated Cable Row", "Lat Pulldown", "Dumbbell Row"],
        "Göğüs": ["Push Up", "Dumbbell Bench Press"],
        "Omuz": ["Dumbbell Lateral Raise", "Lateral Raise", "Dumbbell Shoulder Press"],
        "Biceps": ["Dumbbell Curl", "Hammer Curl"],
        "Triceps": ["Triceps Pushdown", "Cable Triceps Pushdown", "Overhead Triceps Extension"],
        "Bacak": ["Goblet Squat", "Leg Press"],
        "Kalça": ["Hip Thrust", "Glute Bridge"],
        "Baldır": ["Standing Calf Raise", "Seated Calf Raise"],
    ]

    public static func pick(for muscle: String, library: [ExerciseAlternatives.Candidate], done: Set<String> = [], exclude: Set<String> = []) -> ExerciseAlternatives.Candidate? {
        let pool = library.filter { canonical($0.muscle) == muscle && !exclude.contains(TextNorm.norm($0.name)) }
        if let d = pool.first(where: { done.contains(TextNorm.norm($0.name)) }) { return d }
        for n in defaults[muscle] ?? [] { if let d = pool.first(where: { TextNorm.norm($0.name) == TextNorm.norm(n) }) { return d } }
        return pool.first
    }
}
