import Foundation
import SwiftUI
import ActivityKit
import AppIntents
import BalliKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Canlı antrenman (Live Activity + Dynamic Island) — uygulama ile widget eklentisi paylaşır
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setText: String          // "Set 2/4"
        var load: String             // "60 kg × 8"
        var restEnd: Date?           // dinlenme sürüyorsa bitiş
        var restTotal: Double = 0
        var paused = false
        var finished = false
        var done: Int = 0
        var total: Int = 0
        var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }
    var program: String
}

/// Aralıklı oruç (Live Activity + Dynamic Island) — oruç süresince kilit ekranında geri sayım
struct FastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Şu anki dönemin başı ve sonu (oruç ya da yeme penceresi)
        var start: Date
        var end: Date
        /// Bu dönem bitince başlayacak dönemin sonu (etkinlik eskidiğinde geri sayım ona geçer)
        var next: Date
        var fasting: Bool
    }
    /// "16:8" gibi protokol
    var label: String
}

// MARK: - Uygulama niyetleri (uygulama + widget eklentisi birlikte derler) (TE-12)

/// Su ekle: widget düğmesi, Kestirmeler ve Siri. Ayarlardaki su adımı kadar ekler; uygulama açılınca kayda işlenir.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Su ekle"
    static let description = IntentDescription("Bugüne bir bardak (ayarlardaki su adımı kadar) su ekler.")

    func perform() async throws -> some IntentResult {
        SharedStore.shared.addWater()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // Uygulama açıksa kuyruğu hemen işlesin (TE-12)
        await MainActor.run { NotificationCenter.default.post(name: .balliWaterAdded, object: nil) }
        return .result()
    }
}

/// Antrenmanı başlat: uygulamayı açar, bugünün antrenmanını oynatıcıda başlatır/açar (TE-12).
/// İstek App Group'a yazılır; uygulama soğuk açılışta da okur (bildirim kaçsa bile).
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Antrenmanı başlat"
    static let description = IntentDescription("GYM Paper'ı açar ve bugünün antrenmanını başlatır.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        StartWorkoutRequest.post()
        return .result()
    }
}

/// Uygulama dışından gelen "antrenmanı başlat" isteği (Kestirme, Denetim Merkezi, gympaper://start) (TE-12)
enum StartWorkoutRequest {
    static let key = "balli.startWorkoutAt"
    static var defaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    static func post() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: key)
        Task { @MainActor in NotificationCenter.default.post(name: .balliStartWorkout, object: nil) }
    }

    /// Bekleyen istek varsa (son 2 dk) siler ve true döner; eski istek sessizce düşer
    static func take() -> Bool {
        let t = defaults.double(forKey: key)
        guard t > 0 else { return false }
        defaults.removeObject(forKey: key)
        return Date.now.timeIntervalSince1970 - t < 120
    }
}

extension Notification.Name {
    static let balliStartWorkout = Notification.Name("balli.startWorkout")
    static let balliWaterAdded = Notification.Name("balli.waterAdded")
}

// MARK: - Oruç evreleri (RA-07)

/// Oruç evreleri izi (RA-07): oruç boyunca dolan çubuk, evre sınırlarında çentik, altta evre adları.
/// Dolum `ProgressView(timerInterval:)` ile kendiliğinden akar; Live Activity güncelleme beklemez.
/// `now` verilirse (uygulama) şu anki evre koyu yazılır; kilit ekranında bütün adlar eşit kalır.
struct FastStageTrack: View {
    let start: Date
    let end: Date
    var tint: Color
    var ink: Color = .primary
    var muted: Color = .secondary
    var now: Date? = nil

    private var segments: [(stage: FastStage, from: Double, to: Double)] {
        FastStage.segments(duration: end.timeIntervalSince(start))
    }
    private var current: FastStage? { now.map { FastStage.at(elapsed: $0.timeIntervalSince(start)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(timerInterval: start...max(end, start.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear).tint(tint)
                .overlay {
                    GeometryReader { g in
                        ForEach(segments.dropFirst(), id: \.stage) { s in
                            Capsule().fill(muted.opacity(0.6))
                                .frame(width: 1.5, height: 8)
                                .position(x: g.size.width * s.from, y: g.size.height / 2)
                        }
                    }
                }
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(segments, id: \.stage) { s in
                        let on = s.stage == current
                        Text(tl(s.stage.title))
                            .font(.caption2.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? ink : muted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: max(0, g.size.width * (s.to - s.from)), alignment: .leading)
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(current.map { tl("Oruç evresi: ") + tl($0.title) } ?? tl("Oruç evreleri")))
    }
}
