import Foundation
import Observation
import SwiftData
import GymPaperKit

// SwiftData models. For CloudKit sync: every field has a default value and there are no unique constraints.
// Complex substructures (blocks, sets, entries) are stored as JSON.

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
    // macros and goals
    var proteinG: Double = 140
    var carbsG: Double = 160
    var fatG: Double = 60
    var manualKcal: Double?            // manually pinned target (computed otherwise)
    var waterMl: Int = 2500
    var waterStepMl: Int = 500
    var stepGoal: Int = 8000
    var mealsRaw: String = "kahvalti,ogle,ara,aksam"
    var scheduleData: Data = Data("[]".utf8)
    var createdAt: Date = Date.now
    /// Intermittent fasting (fixed schedule)
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
            // don't keep exceptions older than 21 days
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
    var programIdRaw: String?              // nil: weekly plan; "": rest; other: program for that day only
    var workoutDone: Bool = false
    var waterMl: Int = 0
    var steps: Int = 0                     // entered by hand; Health wins when available
    var entriesData: Data = Data("[]".utf8)
    var setsData: Data = Data("{}".utf8)
    var exDoneData: Data = Data("{}".utf8)
    var workoutSeconds: Int = 0
    var workoutKcal: Double = 0
    /// Whether the workout was written to Health; syncs via iCloud so a second device/watch doesn't write the same day again
    var hkSaved: Bool = false
    /// Stable id across devices: if a day gets two records, every device keeps the same copy
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
    // optional measurements (hips, chest, arms, thigh, shoulders)
    var hipCm: Double?
    var chestCm: Double?
    var rightArmCm: Double?
    var leftArmCm: Double?
    var thighCm: Double?
    var shoulderCm: Double?
    /// Stable id across devices: when duplicate measurements merge, every device keeps the same copy
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

/// Visuals the user added to an exercise (start + end position). Matched by exercise name; synced with iCloud.
@Model
final class ExerciseMedia {
    var key: String = ""                       // normalized exercise name
    @Attribute(.externalStorage) var frame0: Data?
    @Attribute(.externalStorage) var frame1: Data?
    var updatedAt: Date = Date.now
    init(key: String) { self.key = key }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [UserProfile.self, WorkoutProgram.self, DayLog.self, BodyMeasure.self, SavedFood.self, Recipe.self, ExerciseMedia.self]
    /// Opens with the versioned schema
    static var schema: Schema { Schema(versionedSchema: AppSchemaV1.self) }
}

/// Schema version. Once deployed to CloudKit Production, fields are never deleted or renamed.
/// When models change: bind them to a new AppSchemaV2, add it to AppMigrationPlan.schemas and write a stage if needed.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { AppSchema.models }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}


/// Caches the decoded form of JSON fields (decoding on every access slowed scrolling).
/// Decoded again when the data changes. Not observed; doesn't trigger view updates.
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

/// iPhone → Watch: everything a workout needs (programs, plan, today's sets, last weights)
struct WatchPayload: Codable {
    struct Prog: Codable { var pid: String; var name: String; var blocks: Data; var archived: Bool; var short: String? = nil }
    struct Day: Codable { var date: String; var programIdRaw: String?; var sets: Data; var exDone: Data; var workoutDone: Bool }
    var today: String
    var schedule: Data
    var programs: [Prog]
    var days: [Day]
    var lastKg: [String: Double]
    var lastReps: [String: Int]
    /// Weight suggestion (raised if the target was hit last session)
    var sugKg: [String: Double]
    /// Intermittent fasting (nil when off)
    var fast: FastPlan?
    /// Watch nutrition complication: today's calorie target and eaten (from the iPhone widget snapshot)
    var kcalTarget: Double? = nil
    var kcalEaten: Double? = nil
    /// Watch corner complications: basal metabolism (calorie deficit), active calories, steps and step goal
    var kcalBmr: Double? = nil
    var kcalActive: Double? = nil
    var steps: Int? = nil
    var stepGoal: Int? = nil
    /// Open workout on iPhone: "day|program" (the watch shows a notice and a shortcut)
    var live: String? = nil
}

/// iPhone ⇄ Watch: live state of the open workout. Goes both ways; the newer one (at) wins.
/// The watch keeps going without the phone; the latest state is sent once connected.
struct LiveState: Codable, Equatable {
    var date: String
    var pid: String
    /// Current step: "exerciseId#set"
    var key: String?
    var paused = false
    /// Rest: end time while running, seconds left when paused
    var restEnd: Date?
    var restLeft: Double?
    var restTotal: Double = 0
    var kg: Double = 0
    var reps: Int = 0
    /// Machine taken: exercises moved to the end
    var later: [String] = []
    var finished = false
    var at = Date()
    /// Echo check: compare without the timestamp (dates rounded to the second)
    var sig: String {
        let r = restEnd.map { String(Int($0.timeIntervalSince1970.rounded())) } ?? "-"
        let l = restLeft.map { String(Int($0.rounded())) } ?? "-"
        return "\(date)|\(pid)|\(key ?? "-")|\(paused)|\(r)|\(l)|\(Int(restTotal))|\(kg)|\(reps)|\(later.sorted().joined(separator: ","))|\(finished)"
    }
}

/// Two-way live state channel: send (no echo, coalesced over 0.3 s) and the latest incoming state
@MainActor @Observable
final class LiveBridge {
    static let shared = LiveBridge()
    /// Latest state from the other device
    var remote: LiveState?
    @ObservationIgnored private var lastSig: String?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// The actual send (wired up by WatchSync on iPhone and PhoneSync on the watch)
    @ObservationIgnored var transport: ((Data) -> Void)?

    /// Time of the last local change: older remote state isn't applied (late arrivals after being offline)
    @ObservationIgnored private var localAt = Date.distantPast
    func publish(_ s: LiveState) {
        guard s.sig != lastSig else { return }
        localAt = s.at
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, s.sig != self.lastSig, let d = try? JSONEncoder().encode(s) else { return }
            self.lastSig = s.sig
            self.transport?(d)
        }
    }
    /// Local state after applying a remote one: not sent back (avoids an echo loop between devices)
    func settle(_ s: LiveState) {
        pending?.cancel()
        lastSig = s.sig
    }
    /// From the other device: applied if newer; its echo isn't sent back
    func receive(_ d: Data) {
        guard let s = try? JSONDecoder().decode(LiveState.self, from: d) else { return }
        if let r = remote, r.at >= s.at { return }
        guard s.at > localAt else { return }
        lastSig = s.sig
        remote = s
    }
}

/// Watch → iPhone: set completed / workout saved
struct WatchEvent: Codable {
    var kind: String            // "set" | "complete" | "fastEnd" | "fastSkip" | "sync" | "pick" | "swap"
    var date: String
    var eid: String?
    var si: Int?
    var kg: Double?
    var reps: Int?
    var pid: String?
    var doneIds: [String]?
    var seconds: Int?
    var kcal: Double?
    var at: Date? = nil        // fastEnd: actual end time on the watch
    var name: String? = nil    // swap: alternative exercise
    var muscle: String? = nil
}
