import Foundation

/// Machine taken: alternative exercises for the same area and a "today only" swap.
/// Pure logic; iPhone and watch get the same result (ids are deterministic).
public enum ExerciseAlternatives {

    public enum Equipment: String, Sendable, CaseIterable {
        case barbell, dumbbell, kettlebell, cable, machine, band, bodyweight, other
    }

    /// A library exercise (English name + Turkish equivalent)
    public struct Candidate: Sendable, Hashable {
        public let name: String
        public let alias: String?
        public let muscle: String
        public let unit: String
        public init(name: String, alias: String? = nil, muscle: String, unit: String = "tekrar") {
            self.name = name; self.alias = alias; self.muscle = muscle; self.unit = unit
        }
        public var equipment: Equipment { ExerciseAlternatives.equipment(name) }
    }

    /// Equipment from the exercise name (English names; base keywords for Turkish names too)
    public static func equipment(_ name: String) -> Equipment {
        let n = " " + TextNorm.norm(name) + " "
        // whole-word match: "bar" ≠ "barfiks"
        func has(_ k: [String]) -> Bool { k.contains { n.contains(" \($0) ") } }
        if has(["barbell", "ez bar", "trap bar", "bar", "landmine"]) { return .barbell }
        if has(["dumbbell", "dumbbells", "dambil"]) { return .dumbbell }
        if has(["kettlebell"]) { return .kettlebell }
        if has(["cable", "kablo", "pulldown", "pushdown", "face pull", "rope"]) { return .cable }
        if has(["machine", "makine", "smith", "lever", "pec deck", "kelebek", "leg press", "leg extension", "leg curl", "hack squat", "seated row machine"]) { return .machine }
        if has(["band", "lastik"]) { return .band }
        if has(["push up", "push ups", "pushup", "pushups", "sinav", "pull up", "pull ups", "pullup", "pullups", "chin up", "chin ups", "barfiks",
                "dip", "dips", "plank", "crunch", "crunches", "sit up", "sit ups", "burpee", "burpees", "mountain climber", "mountain climbers",
                "hollow", "superman", "inverted row", "glute bridge", "leg raise", "leg raises", "bodyweight", "air squat", "lunge", "lunges"]) { return .bodyweight }
        return .other
    }

    /// Same area, not the taken equipment, done before, same unit first.
    /// - Parameters:
    ///   - current: name of the taken exercise
    ///   - muscle: its area (looked up in the library when empty)
    ///   - done: names of exercises done before (TextNorm)
    ///   - exclude: exercises already in the program (TextNorm)
    public static func rank(current: String, muscle: String, unit: String, library: [Candidate],
                            done: Set<String> = [], exclude: Set<String> = [], limit: Int? = nil) -> [Candidate] {
        let cur = TextNorm.norm(current)
        let region = muscle.isEmpty ? (library.first { TextNorm.norm($0.name) == cur || ($0.alias.map(TextNorm.norm) == cur) }?.muscle ?? "") : muscle
        guard !region.isEmpty else { return [] }
        let curEq = equipment(current)
        let pool = library.filter { c in
            let k = TextNorm.norm(c.name)
            return c.muscle == region && k != cur && c.alias.map(TextNorm.norm) != cur && !exclude.contains(k)
        }
        func score(_ c: Candidate) -> Int {
            var s = 0
            if c.equipment != curEq { s += 4 }                  // not the taken equipment
            if done.contains(TextNorm.norm(c.name)) { s += 2 }  // ones you've done before on top
            if c.unit == unit { s += 1 }                        // don't mix reps ↔ time
            return s
        }
        // stable order: score, then library order (common exercises first)
        let ranked = pool.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element), score(b.element))
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
        // avoid many suggestions in a row with the same equipment: one per equipment first on the first page
        var seen = Set<Equipment>(), first: [Candidate] = [], rest: [Candidate] = []
        for c in ranked {
            if seen.insert(c.equipment).inserted || c.equipment == .other { first.append(c) } else { rest.append(c) }
        }
        let out = first + rest
        return limit.map { Array(out.prefix($0)) } ?? out
    }

    // MARK: Today only

    /// Id of the day copy: same on both devices ("<program>@<day>"); itself if already a copy
    public static func dayCopyPid(_ pid: String, date: String) -> String {
        let base = pid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? pid
        return "\(base)@\(date)"
    }

    /// Id of the new exercise: same on both devices
    public static func swappedId(_ eid: String, name: String) -> String {
        "\(eid)~\(TextNorm.norm(name).replacingOccurrences(of: " ", with: "-"))"
    }

    /// Swaps the exercise. If sets were done, the old exercise stays with that many sets (history visible)
    /// and the new one follows right after with the remaining sets. Sets, reps, unit and rest are kept; weight starts empty.
    public static func swap(_ blocks: [Block], eid: String, doneSets: Int, to name: String, muscle: String) -> [Block] {
        var out: [Block] = []
        for b in blocks {
            if b.kind == .single, let e = b.ex, e.id == eid {
                var n = e
                n.id = swappedId(eid, name: name); n.name = name; n.kg = nil; n.muscle = muscle.isEmpty ? e.muscle : muscle; n.note = ""
                let done = max(0, min(doneSets, e.sets))
                if done == 0 {
                    out.append(Block(id: b.id, single: n))
                } else if done >= e.sets {
                    out.append(b)   // a finished exercise doesn't change
                } else {
                    var old = e; old.sets = done
                    n.sets = e.sets - done
                    out.append(Block(id: b.id, single: old))
                    out.append(Block(id: "\(b.id)~alt", single: n))
                }
            } else if b.kind == .superset, let k = b.exs.firstIndex(where: { $0.id == eid }) {
                // in a superset the round count is shared: the exercise changes in place
                var x = b, n = b.exs[k]
                n.id = swappedId(eid, name: name); n.name = name; n.kg = nil; n.muscle = muscle.isEmpty ? n.muscle : muscle; n.note = ""
                x.exs[k] = n
                out.append(x)
            } else {
                out.append(b)
            }
        }
        return out
    }
}
