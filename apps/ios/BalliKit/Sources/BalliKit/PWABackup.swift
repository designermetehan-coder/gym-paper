import Foundation

/// PWA'dan (balli-two.vercel.app) dışa aktarılan JSON yedeğini okur.
/// Biçim: { app: "balli", db: { profile, targets, programs, scheduleHist, log, measures, myFoods, recipes, mealTemplates }, imgs }
public struct PWABackup: Sendable {
    public struct Profile: Sendable { public var name: String; public var startKg: Double?; public var sex: Sex? }
    public struct Targets: Sendable {
        public var kcal = 1800.0, p = 120.0, c = 180.0, f = 60.0, water = 2500, steps = 8000, waterStep = 500
        public var goals: [Double] = []
        public var meals: [Meal] = Meal.allCases
    }
    public struct Program: Sendable { public var id: String; public var name: String; public var short: String?; public var blocks: [Block]; public var archived: Bool }
    public struct Day: Sendable {
        public var date: String
        public var programId: String??         // nil: atanmamış, .some(nil): dinlenme seçilmiş
        public var workoutDone: Bool
        public var water: Int
        public var steps: Int
        public var entries: [FoodEntry]
        public var sets: [String: [SetLog]]
        public var exDone: [String: Bool]
        public var durationSec: Int?
    }
    /// PWA ölçüsü: anahtarlar Türkçe (bel, kalca, gogus, sagkol, solkol, bacak, omuz) (CK-10)
    public struct Measure: Sendable {
        public var id: String; public var date: String; public var kg: Double?; public var waist: Double?
        public var hip: Double? = nil, chest: Double? = nil, rightArm: Double? = nil, leftArm: Double? = nil, thigh: Double? = nil, shoulder: Double? = nil
        /// Hiç değer yoksa aktarılmaz
        public var isEmpty: Bool { [kg, waist, hip, chest, rightArm, leftArm, thigh, shoulder].allSatisfy { $0 == nil } }
    }
    public struct Food: Sendable { public var id: String; public var name: String; public var per100: Macros; public var portions: [String: Double]; public var barcode: String? }
    public struct Recipe: Sendable { public var id: String; public var name: String; public var servings: Int; public var items: [(name: String, g: Double, per100: Macros)] }

    public var profile: Profile
    public var targets: Targets
    public var programs: [Program]
    public var schedule: [ScheduleEntry]
    public var days: [Day]
    public var measures: [Measure]
    public var foods: [Food]
    public var recipes: [Recipe]

    public enum Failure: Error, LocalizedError {
        case notBalli, unreadable
        public var errorDescription: String? {
            switch self { case .notBalli: "Bu dosya bir Ballı yedeği değil."; case .unreadable: "Dosya okunamadı." }
        }
    }

    public static func parse(_ data: Data) throws -> PWABackup {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        guard (root["app"] as? String) == "balli", let db = root["db"] as? [String: Any] else { throw Failure.notBalli }
        let dec = JSONDecoder()
        func decode<T: Decodable>(_ t: T.Type, _ any: Any?) -> T? {
            guard let any, JSONSerialization.isValidJSONObject(any) || any is String || any is NSNumber,
                  let d = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]) else { return nil }
            return try? dec.decode(T.self, from: d)
        }
        func num(_ a: Any?) -> Double? {
            let v = (a as? NSNumber)?.doubleValue ?? (a as? String).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            return v.flatMap { $0.isFinite && abs($0) < 1e9 ? $0 : nil }
        }

        let p = db["profile"] as? [String: Any] ?? [:]
        let profile = Profile(name: p["name"] as? String ?? "Profil", startKg: num(p["startKg"]), sex: (p["sex"] as? String).flatMap { $0 == "f" || $0 == "female" ? .female : $0 == "m" || $0 == "male" ? .male : nil })

        let t = db["targets"] as? [String: Any] ?? [:]
        var targets = Targets()
        if let v = num(t["kcal"]), v > 0 { targets.kcal = v }
        if let v = num(t["p"]), v > 0 { targets.p = v }
        if let v = num(t["c"]), v > 0 { targets.c = v }
        if let v = num(t["f"]), v > 0 { targets.f = v }
        if let v = num(t["water"]), v > 0 { targets.water = Int(v) }
        if let v = num(t["steps"]), v > 0 { targets.steps = Int(v) }
        if let v = num(t["waterStep"]), v > 0 { targets.waterStep = Int(v) }
        targets.goals = (t["goals"] as? [Any] ?? []).compactMap(num)
        if let m = t["meals"] as? [String] { let ms = m.compactMap(Meal.init(rawValue:)); if !ms.isEmpty { targets.meals = ms } }

        let programs: [Program] = (db["programs"] as? [[String: Any]] ?? []).compactMap { x in
            guard let id = x["id"] as? String, (x["temp"] as? Bool) != true else { return nil }
            return Program(id: id, name: x["name"] as? String ?? "Program", short: x["short"] as? String,
                           blocks: decode([Block].self, x["blocks"]) ?? [], archived: (x["archived"] as? Bool) ?? false)
        }

        var schedule: [ScheduleEntry] = (db["scheduleHist"] as? [[String: Any]] ?? []).compactMap { h in
            guard let from = h["from"] as? String, let days = h["days"] as? [String: Any] else { return nil }
            var m: [String: String?] = [:]
            for k in 0..<7 { m[String(k)] = days[String(k)] as? String }
            return ScheduleEntry(from: from, days: m)
        }
        if schedule.isEmpty, let s = db["schedule"] as? [String: Any] {
            var m: [String: String?] = [:]
            for k in 0..<7 { m[String(k)] = s[String(k)] as? String }
            schedule = [ScheduleEntry(from: "0000-01-01", days: m)]
        }

        let log = db["log"] as? [String: Any] ?? [:]
        let days: [Day] = log.compactMap { key, v in
            guard let L = v as? [String: Any], DayKey.date(key) != nil else { return nil }
            var sets: [String: [SetLog]] = [:]
            for (eid, arr) in L["sets"] as? [String: Any] ?? [:] {
                sets[eid] = (arr as? [Any] ?? []).map { decode(SetLog.self, $0) ?? SetLog() }
            }
            let entries = ((L["entries"] as? [Any] ?? []) + (L["extras"] as? [Any] ?? [])).compactMap { decode(FoodEntry.self, $0) }
            let pid: String?? = L.keys.contains("programId") ? .some(L["programId"] as? String) : .none
            return Day(date: key, programId: pid, workoutDone: (L["workoutDone"] as? Bool) ?? false,
                       water: Int(num(L["water"]) ?? 0), steps: Int(num(L["steps"]) ?? 0), entries: entries, sets: sets,
                       exDone: (L["exDone"] as? [String: Bool]) ?? [:], durationSec: num(L["duration"]).map { Int($0 / 1000) })
        }.sorted { $0.date < $1.date }

        let measures: [Measure] = (db["measures"] as? [[String: Any]] ?? []).compactMap { m in
            guard let d = m["date"] as? String, !d.isEmpty else { return nil }
            // PWA sıfır/boş değeri kaydetmez; yine de yalnız pozitifler alınır (CK-10)
            func cm(_ k: String) -> Double? { num(m[k]).flatMap { $0 > 0 ? $0 : nil } }
            let x = Measure(id: m["id"] as? String ?? UUID().uuidString, date: d, kg: cm("kg"), waist: cm("bel") ?? cm("waist"),
                            hip: cm("kalca"), chest: cm("gogus"), rightArm: cm("sagkol"), leftArm: cm("solkol"), thigh: cm("bacak"), shoulder: cm("omuz"))
            return x.isEmpty ? nil : x
        }
        let foods: [Food] = (db["myFoods"] as? [[String: Any]] ?? []).compactMap { f in
            guard let n = f["name"] as? String, let per = decode(Macros.self, f["per100"]) else { return nil }
            let portions = (f["portions"] as? [String: Any] ?? [:]).compactMapValues(num)
            return Food(id: f["id"] as? String ?? UUID().uuidString, name: n, per100: per, portions: portions, barcode: f["barcode"] as? String)
        }
        let recipes: [Recipe] = (db["recipes"] as? [[String: Any]] ?? []).compactMap { r in
            guard let n = r["name"] as? String else { return nil }
            let items = (r["items"] as? [[String: Any]] ?? []).compactMap { i -> (String, Double, Macros)? in
                guard let nm = i["name"] as? String, let per = decode(Macros.self, i["per100"]) else { return nil }
                return (nm, num(i["g"]) ?? 0, per)
            }
            return Recipe(id: r["id"] as? String ?? UUID().uuidString, name: n, servings: max(1, Int(num(r["servings"]) ?? 1)), items: items.map { (name: $0.0, g: $0.1, per100: $0.2) })
        }
        return PWABackup(profile: profile, targets: targets, programs: programs, schedule: schedule, days: days, measures: measures, foods: foods, recipes: recipes)
    }
}
