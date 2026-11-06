import Foundation
import SwiftData
import BalliKit

// SwiftData modelleri. CloudKit senkronu için: bütün alanlar varsayılan değerli, benzersiz kısıt yok.
// Karmaşık alt yapılar (bloklar, setler, kayıtlar) JSON olarak saklanır; PWA ile aynı biçim.

@Model
final class UserProfile {
    var name: String = "Ben"
    var startKg: Double?
    var goalsData: Data = Data("[]".utf8)
    var sexRaw: String?
    var birthDate: Date?
    var heightCm: Double?
    var activityRaw: String = ActivityLevel.light.rawValue
    var weeklyLossKg: Double = 0.5
    var useMeasuredActivity: Bool = true
    // makro ve hedefler
    var proteinG: Double = 140
    var carbsG: Double = 160
    var fatG: Double = 60
    var manualKcal: Double?            // elle sabitlenmiş hedef (yoksa hesaplanır)
    var waterMl: Int = 2500
    var waterStepMl: Int = 500
    var stepGoal: Int = 8000
    var mealsRaw: String = "kahvalti,ogle,ara,aksam"
    var scheduleData: Data = Data("[]".utf8)
    var createdAt: Date = Date.now
    /// Aralıklı oruç (sabit program)
    var fastOn: Bool = false
    var fastData: Data = Data("{}".utf8)

    init() {}

    var sex: Sex? { get { sexRaw.flatMap(Sex.init(rawValue:)) } set { sexRaw = newValue?.rawValue } }
    var activity: ActivityLevel { get { ActivityLevel(rawValue: activityRaw) ?? .light } set { activityRaw = newValue.rawValue } }
    var goals: [Double] {
        get { JSONCache.decode([Double].self, from: goalsData, owner: self, slot: "goalsData") ?? [] }
        set { goalsData = (try? JSONEncoder().encode(newValue.sorted(by: >))) ?? Data("[]".utf8) }
    }
    var meals: [Meal] {
        get { let m = mealsRaw.split(separator: ",").compactMap { Meal(rawValue: String($0)) }; return m.isEmpty ? Meal.allCases : m }
        set { mealsRaw = (newValue.isEmpty ? Meal.allCases : newValue).map(\.rawValue).joined(separator: ",") }
    }
    var fast: FastPlan {
        get { JSONCache.decode(FastPlan.self, from: fastData, owner: self, slot: "fastData") ?? FastPlan() }
        set {
            // 21 günden eski istisnalar birikmesin
            var v = newValue
            let cut = DayKey.shift(DayKey.today, days: -21)
            v.skipped = v.skipped.filter { $0 >= cut }
            v.endedAt = v.endedAt.filter { $0.key >= cut }
            v.startAt = v.startAt.filter { $0.key >= cut }
            fastData = (try? JSONEncoder().encode(v)) ?? Data("{}".utf8)
        }
    }
    var schedule: [ScheduleEntry] {
        get { JSONCache.decode([ScheduleEntry].self, from: scheduleData, owner: self, slot: "scheduleData") ?? [] }
        set { scheduleData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}

@Model
final class WorkoutProgram {
    var pid: String = UUID().uuidString
    var name: String = "Program"
    var short: String?
    var blocksData: Data = Data("[]".utf8)
    var archived: Bool = false
    var createdAt: Date = Date.now

    init(pid: String = UUID().uuidString, name: String, blocks: [Block] = []) {
        self.pid = pid; self.name = name; self.blocks = blocks
    }
    var blocks: [Block] {
        get { JSONCache.decode([Block].self, from: blocksData, owner: self, slot: "blocksData") ?? [] }
        set { blocksData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}

@Model
final class DayLog {
    var date: String = ""                 // YYYY-MM-DD
    var programIdRaw: String?              // nil: haftalık plan; "" : dinlenme; diğer: o güne özel program
    var workoutDone: Bool = false
    var waterMl: Int = 0
    var steps: Int = 0                     // elle girilen; Sağlık varsa o kullanılır
    var entriesData: Data = Data("[]".utf8)
    var setsData: Data = Data("{}".utf8)
    var exDoneData: Data = Data("{}".utf8)
    var workoutSeconds: Int = 0
    var workoutKcal: Double = 0
    /// Antrenman Sağlık'a yazıldı mı; iCloud'la eşitlenir, ikinci cihaz/saat aynı günü tekrar yazmaz (CR-22)
    var hkSaved: Bool = false
    /// Cihazlar arası sabit kimlik: aynı güne iki kayıt düşerse her cihaz aynı kopyayı tutar (CR-20)
    var uid: String = ""

    init(date: String) { self.date = date; self.uid = UUID().uuidString }

    var entries: [FoodEntry] {
        get { JSONCache.decode([FoodEntry].self, from: entriesData, owner: self, slot: "entriesData") ?? [] }
        set { entriesData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
    var sets: [String: [SetLog]] {
        get { JSONCache.decode([String: [SetLog]].self, from: setsData, owner: self, slot: "setsData") ?? [:] }
        set { setsData = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }
    var exDone: [String: Bool] {
        get { JSONCache.decode([String: Bool].self, from: exDoneData, owner: self, slot: "exDoneData") ?? [:] }
        set { exDoneData = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }
    var eaten: Macros { entries.reduce(.zero) { $0 + $1.macros } }
}

@Model
final class BodyMeasure {
    var date: Date = Date.now
    var kg: Double?
    var waistCm: Double?
    // PWA ölçü alanları (kalça, göğüs, kollar, bacak, omuz) — isteğe bağlı
    var hipCm: Double?
    var chestCm: Double?
    var rightArmCm: Double?
    var leftArmCm: Double?
    var thighCm: Double?
    var shoulderCm: Double?
    /// Cihazlar arası sabit kimlik: çift ölçü birleşirken her cihaz aynı kopyayı tutar (CK-11)
    var uid: String = ""
    init(date: Date, kg: Double?, waistCm: Double? = nil) { self.date = date; self.kg = kg; self.waistCm = waistCm; self.uid = UUID().uuidString }
}

@Model
final class SavedFood {
    var name: String = ""
    var per100Data: Data = Data("{}".utf8)
    var portionsData: Data = Data("{}".utf8)
    var barcode: String?
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var imageData: Data?
    init(name: String, per100: Macros, portions: [String: Double] = [:], barcode: String? = nil) {
        self.name = name; self.per100 = per100; self.portions = portions; self.barcode = barcode
    }
    var per100: Macros {
        get { JSONCache.decode(Macros.self, from: per100Data, owner: self, slot: "per100Data") ?? .zero }
        set { per100Data = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }
    var portions: [String: Double] {
        get { JSONCache.decode([String: Double].self, from: portionsData, owner: self, slot: "portionsData") ?? [:] }
        set { portionsData = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }
}

struct RecipeItem: Codable, Hashable { var name: String; var g: Double; var per100: Macros }

@Model
final class Recipe {
    var name: String = ""
    var servings: Int = 1
    var itemsData: Data = Data("[]".utf8)
    var createdAt: Date = Date.now
    init(name: String, servings: Int, items: [RecipeItem]) { self.name = name; self.servings = servings; self.items = items }
    var items: [RecipeItem] {
        get { JSONCache.decode([RecipeItem].self, from: itemsData, owner: self, slot: "itemsData") ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }
}

/// Kullanıcının harekete eklediği görseller (başlangıç + bitiş pozisyonu). Hareket adına göre eşlenir; iCloud ile eşitlenir.
@Model
final class ExerciseMedia {
    var key: String = ""                       // normalize hareket adı
    @Attribute(.externalStorage) var frame0: Data?
    @Attribute(.externalStorage) var frame1: Data?
    var updatedAt: Date = Date.now
    init(key: String) { self.key = key }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [UserProfile.self, WorkoutProgram.self, DayLog.self, BodyMeasure.self, SavedFood.self, Recipe.self, ExerciseMedia.self]
    /// Sürümlü şema ile açılır (CR-25)
    static var schema: Schema { Schema(versionedSchema: AppSchemaV1.self) }
}

/// Şema sürümü (CR-25). CloudKit Production'a dağıtıldıktan sonra alan silme/yeniden adlandırma yapılmaz.
/// Model değişince: modelleri yeni bir AppSchemaV2'ye bağla, AppMigrationPlan.schemas'a ekle, gerekiyorsa aşama yaz.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { AppSchema.models }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}


/// JSON alanlarının çözülmüş hâlini önbellekte tutar (her erişimde yeniden çözmek kaydırmayı yavaşlatıyordu).
/// Veri değişince (Data farklı) yeniden çözülür. Gözlemlenmez; görünüm güncellemesini tetiklemez.
final class JSONCache: @unchecked Sendable {
    private static let lock = NSLock()
    private static var store: [String: (Data, Any)] = [:]
    private static let decoder = JSONDecoder()
    static func decode<T: Decodable>(_ t: T.Type, from data: Data, owner: AnyObject, slot: String) -> T? {
        let key = "\(ObjectIdentifier(owner).hashValue)|\(slot)"
        lock.lock()
        if let (d, v) = store[key], d == data, let x = v as? T { lock.unlock(); return x }
        lock.unlock()
        guard let v = try? decoder.decode(T.self, from: data) else { return nil }
        lock.lock()
        if store.count > 4000 { store.removeAll(keepingCapacity: true) }
        store[key] = (data, v)
        lock.unlock()
        return v
    }
}


// MARK: - iPhone ⇄ Watch (WatchConnectivity)

/// iPhone → Watch: antrenman için gereken her şey (program, plan, bugünkü setler, son kilolar)
struct WatchPayload: Codable {
    struct Prog: Codable { var pid: String; var name: String; var blocks: Data; var archived: Bool; var short: String? = nil }
    struct Day: Codable { var date: String; var programIdRaw: String?; var sets: Data; var exDone: Data; var workoutDone: Bool }
    var today: String
    var schedule: Data
    var programs: [Prog]
    var days: [Day]
    var lastKg: [String: Double]
    var lastReps: [String: Int]
    /// Ağırlık önerisi (son seansta hedef tutturulduysa artırılmış)
    var sugKg: [String: Double]
    /// Aralıklı oruç (kapalıysa nil)
    var fast: FastPlan?
    /// Saat beslenme komplikasyonu: bugünkü kalori hedefi ve yenen (iPhone widget anlık durumundan)
    var kcalTarget: Double? = nil
    var kcalEaten: Double? = nil
    /// Saat köşe göstergeleri (WC-01…03): bazal metabolizma (kalori açığı), aktif kalori, adım ve adım hedefi
    var kcalBmr: Double? = nil
    var kcalActive: Double? = nil
    var steps: Int? = nil
    var stepGoal: Int? = nil
    /// iPhone'da açık antrenman: "gün|program" (saat bildirim gösterir, kısayol açar)
    var live: String? = nil
}

/// Watch → iPhone: set tamamlandı / antrenman kaydedildi
struct WatchEvent: Codable {
    var kind: String            // "set" | "complete" | "fastEnd" | "fastSkip" | "sync" | "pick"
    var date: String
    var eid: String?
    var si: Int?
    var kg: Double?
    var reps: Int?
    var pid: String?
    var doneIds: [String]?
    var seconds: Int?
    var kcal: Double?
    var at: Date? = nil        // fastEnd: saatteki gerçek bitiş anı (CR-33)
}
