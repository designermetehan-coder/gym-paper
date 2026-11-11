import WidgetKit
import SwiftUI
import AppIntents
import GymPaperKit

// MARK: - Timeline

struct SnapEntry: TimelineEntry {
    let date: Date
    let day: String
    let snap: WidgetSnapshot?          // nil: the app has never been opened
    var s: WidgetSnapshot { (snap ?? .placeholder).on(day) }
}

struct SnapProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry { SnapEntry(date: .now, day: DayKey.today, snap: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : (SharedStore.shared.read() ?? .placeholder)
        completion(SnapEntry(date: .now, day: DayKey.today, snap: snap))
    }

    /// Now + midnight (daily counters reset, the new day's workout shows)
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let snap = SharedStore.shared.read()
        let now = Date.now
        // next day by calendar: the correct midnight on 23/25-hour (DST) days too
        let cal = Calendar.current
        let midnight = (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)).addingTimeInterval(60)
        var entries = [
            SnapEntry(date: now, day: DayKey.of(now), snap: snap),
            SnapEntry(date: midnight, day: DayKey.of(midnight), snap: snap),
        ]
        // intermittent fasting: the widget switches state when a fast starts/ends
        if let f = snap?.fast {
            var t = now
            for _ in 0..<4 {
                switch f.phase(at: t) {
                case .fasting(_, let e, _): t = e.addingTimeInterval(1)
                case .eating(_, let n, _): t = n.addingTimeInterval(1)
                }
                if t < midnight.addingTimeInterval(86_400) { entries.append(SnapEntry(date: t, day: DayKey.of(t), snap: snap)) }
            }
            entries.sort { $0.date < $1.date }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// Add water / Start workout intents live in Shared/SessionActivity.swift so the app compiles them too

// MARK: - Shared view parts
// Large numbers: SF Pro Heavy Italic + fixed-width digits

enum Fmt {
    static func int(_ x: Double) -> String { guard x.isFinite, abs(x) < 1e15 else { return "–" }; return Int(x.rounded()).formatted() }
    static func liters(_ ml: Int) -> String {
        (Double(ml) / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(.current))
    }
}

struct Ring: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = .wBrand
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}

struct OpenAppNote: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap").font(.title2).foregroundStyle(Color.wBrand)   // ink instead of decorative orange
            Text("GYM Paper'ı bir kez aç").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

extension View {
    func gymPaperBackground() -> some View { containerBackground(.fill.tertiary, for: .widget) }
}

// MARK: - App colors (Watch rings)

extension Color {
    static let wProtein = Color(red: 0xFA / 255, green: 0x11 / 255, blue: 0x4F / 255)
    static let wCarb = Color(red: 0x92 / 255, green: 0xE8 / 255, blue: 0x2A / 255)
    static let wFat = Color(red: 0x1E / 255, green: 0xEA / 255, blue: 0xEF / 255)
    static let wSteps = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    /// Ink: near-black #1C1C1E in light, off-white #E5E5E7 in dark; no pure black/white
    static let wBrand = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE7 / 255, alpha: 1) : UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) })
    /// Text on ink (inverted)
    static let wOnBrand = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) : UIColor(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE7 / 255, alpha: 1) })
    /// Fixed off-white for dark-fill live activities / Dynamic Island
    static let wOnDark = Color(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE7 / 255)
    /// Brand color: neon lime (live activities on dark)
    static let wLime = Color(red: 0xC6 / 255, green: 0xFF / 255, blue: 0x3D / 255)
    /// Fasting purple, eating window green (same as the app's fitPurple / fitGreen)
    static let wFast = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0xA9 / 255, green: 0x7C / 255, blue: 0xFF / 255, alpha: 1) : UIColor(red: 0x7A / 255, green: 0x3F / 255, blue: 0xF2 / 255, alpha: 1) })
    static let wEat = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x5F / 255, green: 0xE0 / 255, blue: 0x7A / 255, alpha: 1) : UIColor(red: 0x1E / 255, green: 0x9E / 255, blue: 0x3E / 255, alpha: 1) })
}

/// Three nested rings (outer to inner: protein, carbs, fat)
struct TripleRings: View {
    var p: Double, c: Double, f: Double
    var line: CGFloat = 10
    var gap: CGFloat = 2
    var body: some View {
        ZStack {
            Ring(progress: p, lineWidth: line, tint: .wProtein)
            Ring(progress: c, lineWidth: line, tint: .wCarb).padding(line + gap)
            Ring(progress: f, lineWidth: line, tint: .wFat).padding((line + gap) * 2)
        }
        .padding(line / 2)
    }
}

extension WidgetSnapshot {
    func ratio(_ v: Double, _ goal: Double) -> Double { goal > 0 ? v / goal : 0 }
    var pRatio: Double { ratio(eaten.p, goal.p) }
    var cRatio: Double { ratio(eaten.c, goal.c) }
    var fRatio: Double { ratio(eaten.f, goal.f) }
    var stepRatio: Double { stepGoal > 0 ? Double(steps) / Double(stepGoal) : 0 }   // goal 0 → no NaN ring
}
