import Foundation

// Antrenman planı tipleri (PWA ile aynı yapı; JSON olarak saklanır)

public struct Exercise: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var sets: Int
    public var reps: Int
    public var unit: String      // "tekrar" | "sn" | "dk"
    public var rest: Int
    public var kg: Double?
    public var muscle: String
    public var note: String
    public init(id: String = UUID().uuidString, name: String, sets: Int = 3, reps: Int = 10, unit: String = "tekrar", rest: Int = 60, kg: Double? = nil, muscle: String = "", note: String = "") {
        self.id = id; self.name = name; self.sets = sets; self.reps = reps; self.unit = unit; self.rest = rest; self.kg = kg; self.muscle = muscle; self.note = note
    }
    enum CodingKeys: String, CodingKey { case id, name, sets, reps, unit, rest, kg, muscle, note }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Hareket"
        sets = Lenient.int(c, .sets) ?? 3
        reps = Lenient.int(c, .reps) ?? 10
        unit = (try? c.decode(String.self, forKey: .unit)) ?? "tekrar"
        rest = Lenient.int(c, .rest) ?? 60
        kg = Lenient.double(c, .kg).flatMap { $0 > 0 ? $0 : nil }
        muscle = (try? c.decode(String.self, forKey: .muscle)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

public struct Block: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case single, superset }
    public var id: String
    public var kind: Kind
    public var ex: Exercise?          // single
    public var exs: [Exercise]        // superset
    public var rounds: Int
    public var rest: Int
    public var tag: String?           // "warm" | "cool"
    public init(id: String = UUID().uuidString, single ex: Exercise) {
        self.id = id; kind = .single; self.ex = ex; exs = []; rounds = ex.sets; rest = ex.rest; tag = nil
    }
    public init(id: String = UUID().uuidString, superset exs: [Exercise], rounds: Int, rest: Int, tag: String? = nil) {
        self.id = id; kind = .superset; ex = nil; self.exs = exs; self.rounds = rounds; self.rest = rest; self.tag = tag
    }
    public var exercises: [Exercise] { kind == .single ? (ex.map { [$0] } ?? []) : exs }
    enum CodingKeys: String, CodingKey { case id, kind, ex, exs, rounds, rest, tag }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .single
        ex = try? c.decode(Exercise.self, forKey: .ex)
        exs = (try? c.decode([Exercise].self, forKey: .exs)) ?? []
        rounds = Lenient.int(c, .rounds) ?? max(1, ex?.sets ?? 3)
        rest = Lenient.int(c, .rest) ?? 60
        tag = try? c.decode(String.self, forKey: .tag)
    }
}

/// Bir programın toplam set sayısı ve tahmini süre girdisi
public extension Array where Element == Block {
    var allExercises: [Exercise] { flatMap(\.exercises) }
    var setCount: Int { reduce(0) { $0 + ($1.kind == .single ? ($1.ex?.sets ?? 0) : $1.rounds * $1.exs.count) } }
    var restProfile: [(rest: Int, count: Int)] {
        map { b in b.kind == .single ? (b.ex?.rest ?? 60, b.ex?.sets ?? 0) : (b.rest, b.rounds * b.exs.count) }
    }
}

/// Haftalık plan geçmişi: tarihten itibaren gün → program
public struct ScheduleEntry: Codable, Hashable, Sendable {
    public var from: String               // "YYYY-MM-DD"
    public var days: [String: String?]    // "0".."6" (Pzt=0) → programId
    public init(from: String, days: [String: String?]) { self.from = from; self.days = days }
}

public enum Schedule {
    public static func at(_ hist: [ScheduleEntry], date: String) -> [String: String?] {
        var cur = hist.first?.days ?? [:]
        for h in hist.sorted(by: { $0.from < $1.from }) where h.from <= date { cur = h.days }
        return cur
    }
    public static func programId(_ hist: [ScheduleEntry], date: String) -> String? {
        let dow = DayKey.weekday(date)
        return at(hist, date: date)[String(dow)] ?? nil
    }
    /// `from` tarihinden itibaren `dow` gününü değiştirir; önceki tarihler etkilenmez
    public static func set(_ hist: inout [ScheduleEntry], from: String, dow: Int, programId: String?) {
        if !hist.contains(where: { $0.from == from }) {
            hist.append(ScheduleEntry(from: from, days: at(hist, date: from)))
            hist.sort { $0.from < $1.from }
        }
        for i in hist.indices where hist[i].from >= from { hist[i].days[String(dow)] = programId }
        var i = hist.count - 1
        while i > 0 { if hist[i].days == hist[i - 1].days { hist.remove(at: i) }; i -= 1 }
    }
}

/// Sonsuz/NaN ya da çok büyük sayıda Int(...) çöker; güvenli dönüşüm (CR-31, NU-44)
public func safeInt(_ v: Double?) -> Int? {
    guard let v, v.isFinite, abs(v) < 1_000_000_000 else { return nil }
    return Int(v)
}

enum Lenient {
    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Int? {
        if let v = try? c.decode(Int.self, forKey: k) { return v }
        if let v = try? c.decode(Double.self, forKey: k) { return safeInt(v) }
        if let s = try? c.decode(String.self, forKey: k) { return Int(s.replacingOccurrences(of: ",", with: ".").split(separator: ".").first ?? "") }
        return nil
    }
    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Double? {
        if let v = try? c.decode(Double.self, forKey: k) { return v }
        if let s = try? c.decode(String.self, forKey: k) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}
