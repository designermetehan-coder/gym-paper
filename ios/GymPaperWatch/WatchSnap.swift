import Foundation
import GymPaperKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small snapshot read by the watch complications (App Group). The watch app writes, complications read
struct WatchSnap: Codable, Equatable {
    var date: String                 // YYYY-MM-DD
    var program: String?             // nil: no workout today
    /// Short name for the corner complication; full name when nil
    var programShort: String?
    var done: Int = 0
    var total: Int = 0
    var workoutDone = false
    var fast: FastPlan?
    /// Nutrition complication (from iPhone); nil: not received yet
    var kcalTarget: Double?
    var kcalEaten: Double?
    /// Corner complications: today's steps, step goal, active calories and basal metabolism
    var steps: Int?
    var stepGoal: Int?
    var kcalActive: Double?
    var kcalBmr: Double?

    static let group = AppConfig.appGroup
    static let key = "watch.snap"

    var progress: Double { workoutDone ? 1 : total > 0 ? Double(done) / Double(total) : 0 }

    static func load() -> WatchSnap? {
        UserDefaults(suiteName: group)?.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchSnap.self, from: $0) }
    }

    /// Writes if changed and reloads the complications
    static func save(_ s: WatchSnap) {
        guard s != load(), let d = try? JSONEncoder().encode(s) else { return }
        UserDefaults(suiteName: group)?.set(d, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
