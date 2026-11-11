import Foundation
import SwiftUI
import ActivityKit
import AppIntents
import GymPaperKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Live workout (Live Activity + Dynamic Island) — shared by the app and the widget extension
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setText: String          // "Set 2/4"
        var load: String             // "60 kg × 8"
        var restEnd: Date?           // rest end while resting
        var restTotal: Double = 0
        var paused = false
        var finished = false
        var done: Int = 0
        var total: Int = 0
        var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }
    var program: String
}

/// Intermittent fasting (Live Activity + Dynamic Island) — Lock Screen countdown while fasting
struct FastActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Start and end of the current phase (fast or eating window)
        var start: Date
        var end: Date
        /// End of the phase that follows this one (the countdown moves to it when the activity goes stale)
        var next: Date
        var fasting: Bool
    }
    /// Protocol such as "16:8"
    var label: String
}

// MARK: - App intents (compiled by both the app and the widget extension)

/// Add water: widget button, Shortcuts and Siri. Adds the water step from Settings; written to the log when the app opens.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Su ekle"
    static let description = IntentDescription("Bugüne bir bardak (ayarlardaki su adımı kadar) su ekler.")

    func perform() async throws -> some IntentResult {
        SharedStore.shared.addWater()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // if the app is open, handle the queue right away
        await MainActor.run { NotificationCenter.default.post(name: .gymPaperWaterAdded, object: nil) }
        return .result()
    }
}

/// Start workout: opens the app and starts/opens today's workout in the player.
/// The request is written to the App Group; the app reads it on a cold start too (even if the notification is missed).
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Antrenmanı başlat"
    static let description = IntentDescription("GYM Paper'ı açar ve bugünün antrenmanını başlatır.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        StartWorkoutRequest.post()
        return .result()
    }
}

/// "Start workout" request from outside the app (Shortcut, Control Center, gympaper://start)
enum StartWorkoutRequest {
    static let key = "gympaper.startWorkoutAt"
    static var defaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    static func post() {
        defaults.set(Date.now.timeIntervalSince1970, forKey: key)
        Task { @MainActor in NotificationCenter.default.post(name: .gymPaperStartWorkout, object: nil) }
    }

    /// If there's a pending request (last 2 min), deletes it and returns true; older requests are dropped silently
    static func take() -> Bool {
        let t = defaults.double(forKey: key)
        guard t > 0 else { return false }
        defaults.removeObject(forKey: key)
        return Date.now.timeIntervalSince1970 - t < 120
    }
}

extension Notification.Name {
    static let gymPaperStartWorkout = Notification.Name("gympaper.startWorkout")
    static let gymPaperWaterAdded = Notification.Name("gympaper.waterAdded")
}

// MARK: - Fasting stages

/// Fasting stage track: a bar filling over the fast, notches at stage boundaries, stage names below.
/// The fill runs on its own with `ProgressView(timerInterval:)`; the Live Activity needs no updates.
/// With `now` (in the app) the current stage is bold; on the Lock Screen all names look the same.
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
