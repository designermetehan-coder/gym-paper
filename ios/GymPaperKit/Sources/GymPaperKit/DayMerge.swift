import Foundation

/// Merges two records of the same day after iCloud sync without losing data
public enum DayMerge {
    /// Food entries: union by id (same id → first value), order kept
    public static func entries(_ a: [FoodEntry], _ b: [FoodEntry]) -> [FoodEntry] {
        var seen = Set(a.map(\.id))
        var out = a
        for e in b where !seen.contains(e.id) { out.append(e); seen.insert(e.id) }
        return out
    }

    /// Set logs: per exercise, set by set; the done (or fuller) one wins
    public static func sets(_ a: [String: [SetLog]], _ b: [String: [SetLog]]) -> [String: [SetLog]] {
        var out = a
        for (k, bs) in b {
            let as_ = out[k] ?? []
            var m: [SetLog] = []
            for i in 0..<max(as_.count, bs.count) {
                let x = i < as_.count ? as_[i] : nil, y = i < bs.count ? bs[i] : nil
                switch (x, y) {
                case let (x?, y?): m.append(x.done || !y.done ? x : y)
                case let (x?, nil): m.append(x)
                case let (nil, y?): m.append(y)
                default: break
                }
            }
            out[k] = m
        }
        return out
    }

    public static func flags(_ a: [String: Bool], _ b: [String: Bool]) -> [String: Bool] {
        a.merging(b) { $0 || $1 }
    }
}
