import Foundation

public struct Macros: Codable, Hashable, Sendable {
    public var kcal: Double, p: Double, c: Double, f: Double
    public init(kcal: Double = 0, p: Double = 0, c: Double = 0, f: Double = 0) { self.kcal = kcal; self.p = p; self.c = c; self.f = f }
    public static let zero = Macros()
    public static func + (a: Macros, b: Macros) -> Macros { Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, c: a.c + b.c, f: a.f + b.f) }
    public func scaled(_ k: Double) -> Macros { Macros(kcal: kcal * k, p: p * k, c: c * k, f: f * k) }
    enum CodingKeys: String, CodingKey { case kcal, p, c, f }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) -> Double { let x = Lenient.double(c, k) ?? 0; return x.isFinite ? max(0, x) : 0 }
        kcal = v(.kcal); p = v(.p); self.c = v(.c); f = v(.f)
    }
}

public enum Meal: String, Codable, CaseIterable, Sendable {
    case kahvalti, ogle, ara, aksam
    public var label: String {
        switch self { case .kahvalti: "Sabah"; case .ogle: "Öğle"; case .ara: "Ara öğün"; case .aksam: "Akşam" }
    }
    /// Default meal by time of day, among enabled meals only
    public static func `default`(at date: Date = .now, enabled: [Meal] = Meal.allCases) -> Meal {
        let h = Calendar.current.component(.hour, from: date)
        let pref: Meal = h < 11 ? .kahvalti : h < 15 ? .ogle : h < 18 ? .ara : .aksam
        if enabled.contains(pref) || enabled.isEmpty { return pref }
        let order = Meal.allCases
        let pi = order.firstIndex(of: pref)!
        return enabled.min { abs(order.firstIndex(of: $0)! - pi) < abs(order.firstIndex(of: $1)! - pi) }!
    }
}

public struct FoodEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var meal: Meal
    public var name: String
    public var foodName: String
    public var g: Double
    public var per100: Macros
    /// Items added from a saved meal: the same group id shows as one row in the log ("Breakfast plate")
    public var group: String?
    public var groupName: String?
    public init(id: String = UUID().uuidString, meal: Meal, name: String, foodName: String, g: Double, per100: Macros, group: String? = nil, groupName: String? = nil) {
        self.id = id; self.meal = meal; self.name = name; self.foodName = foodName; self.g = g; self.per100 = per100
        self.group = group; self.groupName = groupName
    }
    public var macros: Macros { per100.scaled(g / 100) }
    enum CodingKeys: String, CodingKey { case id, meal, name, foodName, g, per100, kcal, p, c, f, group, groupName }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        meal = (try? c.decode(Meal.self, forKey: .meal)) ?? .ara
        name = (try? c.decode(String.self, forKey: .name)) ?? "Besin"
        foodName = (try? c.decode(String.self, forKey: .foodName)) ?? name
        group = try? c.decodeIfPresent(String.self, forKey: .group)
        groupName = try? c.decodeIfPresent(String.self, forKey: .groupName)
        let rawG = Lenient.double(c, .g) ?? 0
        g = rawG.isFinite ? min(10_000, max(0, rawG)) : 0      // a broken backup value must not crash
        if let p = try? c.decode(Macros.self, forKey: .per100) { per100 = p }
        else {
            // old "type it in" entries only carry total macros → convert to 100 g
            let tot = Macros(kcal: Lenient.double(c, .kcal) ?? 0, p: Lenient.double(c, .p) ?? 0, c: Lenient.double(c, .c) ?? 0, f: Lenient.double(c, .f) ?? 0)
            if g <= 0 { g = 100 }
            per100 = tot.scaled(100 / g)
        }
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(meal, forKey: .meal); try c.encode(name, forKey: .name)
        try c.encode(foodName, forKey: .foodName); try c.encode(g, forKey: .g); try c.encode(per100, forKey: .per100)
        try c.encodeIfPresent(group, forKey: .group); try c.encodeIfPresent(groupName, forKey: .groupName)
    }
}

public struct SetLog: Codable, Hashable, Sendable {
    public var kg: Double?
    public var reps: Int?
    public var done: Bool
    public init(kg: Double? = nil, reps: Int? = nil, done: Bool = false) { self.kg = kg; self.reps = reps; self.done = done }
    enum CodingKeys: String, CodingKey { case kg, reps, done }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kg = Lenient.double(c, .kg); reps = Lenient.int(c, .reps); done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}
