import WidgetKit
import SwiftUI
import GymPaperKit

/// Daily rings (P/C/F like Watch, calories left in the middle)
struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "gympaper.halkalar", provider: SnapProvider()) { e in
            RingsView(e: e).gymPaperBackground().widgetURL(URL(string: "gympaper://tab/food"))
        }
        .configurationDisplayName("Günlük halkalar")
        .description("Protein, karbonhidrat ve yağ halkaları; ortada kalan kalori.")
        .supportedFamilies([.systemMedium, .accessoryCircular])
    }
}

struct RingsView: View {
    @Environment(\.widgetFamily) private var family
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let left = s.remaining
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    // on the single-color Lock Screen the rings are told apart by opacity
                    ZStack {
                        Ring(progress: s.pRatio, lineWidth: 4.5, tint: .wProtein)
                        Ring(progress: s.cRatio, lineWidth: 4.5, tint: .wCarb).opacity(0.75).padding(6)
                        Ring(progress: s.fRatio, lineWidth: 4.5, tint: .wFat).opacity(0.5).padding(12)
                    }
                    .padding(2.25)
                    Text(Fmt.int(abs(left))).font(.system(size: 11, weight: .bold)).minimumScaleFactor(0.5).padding(.horizontal, 20)
                }
            case .systemMedium:
                HStack(spacing: 18) {
                    center(s, left: left).frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        row("Protein", s.eaten.p, s.goal.p, .wProtein)
                        row("Karbonhidrat", s.eaten.c, s.goal.c, .wCarb)
                        row("Yağ", s.eaten.f, s.goal.f, .wFat)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default:
                center(s, left: left)
            }
        }
        .redacted(reason: e.snap == nil ? .placeholder : [])
    }

    private func center(_ s: WidgetSnapshot, left: Double) -> some View {
        ZStack {
            TripleRings(p: s.pRatio, c: s.cRatio, f: s.fRatio, line: 11, gap: 2)
            VStack(spacing: -1) {
                Text(Fmt.int(abs(left))).font(.system(size: 17, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.6)
                Text(left >= 0 ? "kalan" : "aşıldı").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
        }
    }

    private func row(_ name: String, _ v: Double, _ goal: Double, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(tl(name)).font(.caption)
            Spacer(minLength: 4)
            Text("\(Fmt.int(v))/\(Fmt.int(goal)) g").font(.caption.weight(.semibold)).monospacedDigit()
        }
    }
}
