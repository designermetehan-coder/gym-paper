import WidgetKit
import SwiftUI
import AppIntents
import GymPaperKit

/// Water (+1 glass button adds without opening the app)
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "gympaper.su", provider: SnapProvider()) { e in
            WaterView(e: e).gymPaperBackground()
        }
        .configurationDisplayName("Su")
        .description("Günlük su ilerlemen; tek dokunuşla su ekle.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct WaterView: View {
    @Environment(\.widgetFamily) private var family
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let progress = s.waterGoalMl > 0 ? Double(s.waterMl) / Double(s.waterGoalMl) : 0
        switch family {
        case .accessoryInline:
            // if the app was never opened, sample values must not look real
            Text("Su \(Fmt.liters(s.waterMl)) / \(Fmt.liters(s.waterGoalMl)) L")
                .redacted(reason: e.snap == nil ? .placeholder : [])
        case .accessoryCircular:
            Button(intent: AddWaterIntent()) {
                Gauge(value: min(progress, 1)) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .redacted(reason: e.snap == nil ? .placeholder : [])
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(s.waterStepMl) ml su ekle")
        default:
            if e.snap == nil {
                OpenAppNote()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "drop.fill").foregroundStyle(.cyan).widgetAccentable()
                        Text("Su").font(.headline)
                        Spacer()
                    }
                    Text("\(Fmt.liters(s.waterMl)) / \(Fmt.liters(s.waterGoalMl)) L")
                        .font(.system(size: 18, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    ProgressView(value: min(1, progress)).tint(.cyan)
                    Spacer(minLength: 0)
                    Button(intent: AddWaterIntent()) {
                        Label("\(s.waterStepMl) ml", systemImage: "plus")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                            .foregroundStyle(Color.wOnBrand)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.wBrand)   // ink button, inverted text
                    .accessibilityLabel("\(s.waterStepMl) ml su ekle")
                }
            }
        }
    }
}
