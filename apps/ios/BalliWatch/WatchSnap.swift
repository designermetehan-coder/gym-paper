import Foundation
import BalliKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Saat komplikasyonlarının okuduğu küçük anlık görüntü (App Group). Saat uygulaması yazar, komplikasyon okur (TE-12)
struct WatchSnap: Codable, Equatable {
    var date: String                 // YYYY-MM-DD
    var program: String?             // nil: bugün antrenman yok
    /// Köşe göstergesi için kısa ad (WC-02); nil ise tam ad
    var programShort: String?
    var done: Int = 0
    var total: Int = 0
    var workoutDone = false
    var fast: FastPlan?
    /// Beslenme komplikasyonu (iPhone'dan); nil: henüz gelmedi
    var kcalTarget: Double?
    var kcalEaten: Double?
    /// Köşe göstergeleri (WC-01…03): bugünkü adım, adım hedefi, aktif kalori ve bazal metabolizma
    var steps: Int?
    var stepGoal: Int?
    var kcalActive: Double?
    var kcalBmr: Double?

    static let group = "group.com.metehankaya.balli"
    static let key = "watch.snap"

    var progress: Double { workoutDone ? 1 : total > 0 ? Double(done) / Double(total) : 0 }

    static func load() -> WatchSnap? {
        UserDefaults(suiteName: group)?.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchSnap.self, from: $0) }
    }

    /// Değiştiyse yazar ve komplikasyonları yeniler
    static func save(_ s: WatchSnap) {
        guard s != load(), let d = try? JSONEncoder().encode(s) else { return }
        UserDefaults(suiteName: group)?.set(d, forKey: key)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
