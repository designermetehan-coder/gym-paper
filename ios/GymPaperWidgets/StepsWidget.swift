import WidgetKit
import SwiftUI
import GymPaperKit
import CoreMotion

/// Steps (Home Screen + Lock Screen)
struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "gympaper.adim", provider: StepsProvider()) { e in
            StepsView(e: e).gymPaperBackground()
        }
        .configurationDisplayName("Adım")
        .description("Bugünkü adımın ve hedefin.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Keeps the steps widget current without opening the app: iPhone's pedometer (CMPedometer) is read inside the widget,
/// refreshed about every 15 min. Health's latest value (Apple Watch included) wins when larger.
/// Health data can't be read while locked; the pedometer can.
struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapEntry { SnapProvider().placeholder(in: context) }
    func getSnapshot(in context: Context, completion: @escaping (SnapEntry) -> Void) { SnapProvider().getSnapshot(in: context, completion: completion) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapEntry>) -> Void) {
        let now = Date.now, today = DayKey.of(now)
        let cal = Calendar.current
        let next = now.addingTimeInterval(15 * 60)
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? next
        let snap = SharedStore.shared.read()
        Self.pedometer(from: cal.startOfDay(for: now), to: now) { ped in
            var s = snap?.on(today)
            if let ped, var x = s, ped > x.steps { x.stepsRaw = ped; s = x }
            var entries = [SnapEntry(date: now, day: today, snap: s)]
            // reset at midnight without waiting for the refresh budget
            if midnight < next, let x = snap { entries.append(SnapEntry(date: midnight, day: DayKey.of(midnight), snap: x)) }
            completion(Timeline(entries: entries, policy: .after(min(next, midnight.addingTimeInterval(60)))))
        }
    }

    /// Today's steps (nil without permission or device support)
    static func pedometer(from: Date, to: Date, done: @escaping (Int?) -> Void) {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized else { done(nil); return }
        let p = CMPedometer()
        p.queryPedometerData(from: from, to: to) { d, _ in
            withExtendedLifetime(p) { done(d.map { $0.numberOfSteps.intValue }) }
        }
    }
}

struct StepsView: View {
    @Environment(\.widgetFamily) private var family
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let n = Double(s.steps)
        Group {
            switch family {
            case .accessoryInline:
                Label("\(Fmt.int(n)) adım", systemImage: "figure.walk")
            case .accessoryCircular:
                // open arc + whole number in the middle (6,088) + icon below — Apple Fitness/Health style
                Gauge(value: min(s.stepRatio, 1)) {
                    Image(systemName: "shoe.fill")
                } currentValueLabel: {
                    Text(Fmt.int(n)).font(.system(size: 20, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.45).lineLimit(1)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(Fmt.int(n)) adım", systemImage: "figure.walk").font(.headline).widgetAccentable()
                    Gauge(value: min(s.stepRatio, 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                    Text("Hedef \(Fmt.int(Double(s.stepGoal)))").font(.caption).foregroundStyle(.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "figure.walk").foregroundStyle(Color.wSteps).widgetAccentable()
                        Text("Adım").font(.headline)
                        Spacer()
                        if s.steps >= s.stepGoal { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wSteps) }
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.int(n)).font(.system(size: 32, weight: .heavy).italic().monospacedDigit())
                        .minimumScaleFactor(0.6).contentTransition(.numericText())
                    ProgressView(value: min(1, s.stepRatio)).tint(Color.wSteps)
                    Text("Hedef \(Fmt.int(Double(s.stepGoal)))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .redacted(reason: e.snap == nil ? .placeholder : [])
    }
}
