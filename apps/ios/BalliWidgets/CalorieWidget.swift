import WidgetKit
import SwiftUI
import BalliKit

/// WG-01 · Kalan kalori
struct CalorieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "balli.kalori", provider: SnapProvider()) { e in
            CalorieView(e: e).balliBackground().widgetURL(URL(string: "gympaper://tab/food"))
        }
        .configurationDisplayName("Kalan kalori")
        .description("Bugün kalan kalori, yakılan enerji ve makrolar.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CalorieView: View {
    @Environment(\.widgetFamily) private var family
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let left = s.remaining
        let progress = s.kcalTarget > 0 ? s.kcalEaten / s.kcalTarget : 0
        let leftText = left >= 0 ? Fmt.int(left) : "+" + Fmt.int(-left)
        let leftLabel = left >= 0 ? tl("kalan") : tl("aşıldı")
        Group {
            switch family {
            case .accessoryInline:
                Text(left >= 0 ? "\(leftText) kcal kaldı" : "\(Fmt.int(-left)) kcal aşıldı")
            case .accessoryCircular:
                Gauge(value: min(s.kcalEaten, s.kcalTarget), in: 0...max(1, s.kcalTarget)) {
                    Image(systemName: "fork.knife")
                } currentValueLabel: {
                    Text(leftText).font(.system(size: 20, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.45).lineLimit(1)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(leftText) kcal \(leftLabel)").font(.headline).widgetAccentable()
                    Gauge(value: min(progress, 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                    Text("P \(Fmt.int(s.eaten.p))/\(Fmt.int(s.goal.p)) g").font(.caption).foregroundStyle(.secondary)
                }
            case .systemMedium:
                // Solda büyük kalan kalori + çizgi; sağda makrolar ya da (açıksa) aralıklı oruç (2 Kas)
                HStack(alignment: .top, spacing: 16) {
                    summary(s, progress: progress, left: left, big: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(.secondary.opacity(0.2)).frame(width: 1)
                    if let f = s.fast {
                        FastPanel(plan: f, at: e.date)
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            macro("Protein", s.eaten.p, s.goal.p, .wProtein)
                            macro("Karbonhidrat", s.eaten.c, s.goal.c, .wCarb)
                            macro("Yağ", s.eaten.f, s.goal.f, .wFat)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            default:
                summary(s, progress: progress, left: left, big: 36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .redacted(reason: e.snap == nil ? .placeholder : [])
    }

    /// Başlık, büyük kalan kalori, ilerleme çizgisi ve yenen / hedef (2 Kas: halka yerine okunaklı sayı)
    private func summary(_ s: WidgetSnapshot, progress: Double, left: Double, big: CGFloat) -> some View {
        let over = left < 0
        return VStack(alignment: .leading, spacing: 0) {
            Label("Kalan kalori", systemImage: "fork.knife")
                .font(.caption.weight(.semibold).italic()).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Text(Fmt.int(abs(left)))
                .font(.system(size: big, weight: .heavy).italic().monospacedDigit())
                .foregroundStyle(over ? Color.red : Color.wBrand)
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(over ? "kcal aşıldı" : "kcal kaldı").font(.caption.italic()).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ProgressView(value: min(1, max(0, progress)))
                .tint(over ? .red : .wBrand)
                .widgetAccentable()
            HStack {
                Text("\(Fmt.int(s.kcalEaten)) yenen")
                Spacer(minLength: 4)
                Text("hedef \(Fmt.int(s.kcalTarget))")
            }
            .font(.caption2.italic()).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .padding(.top, 5)
        }
    }

    private func macro(_ name: String, _ v: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(tl(name)).font(.caption2)
                Spacer()
                Text("\(Fmt.int(v))/\(Fmt.int(goal)) g").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, goal > 0 ? v / goal : 0)).tint(tint)
        }
    }
}


/// Widget içinde oruç bölümü: durum, geri sayım, ilerleme, bitiş saati
struct FastPanel: View {
    let plan: FastPlan
    let at: Date
    var body: some View {
        let (from, to, fasting): (Date, Date, Bool) = {
            switch plan.phase(at: at) {
            case let .fasting(s, e, _): return (s, e, true)
            case let .eating(s, n, _): return (s, n, false)
            }
        }()
        VStack(alignment: .leading, spacing: 5) {
            Label(fasting ? "Oruç · \(plan.label)" : "Yeme aralığı", systemImage: fasting ? "moon.stars.fill" : "fork.knife")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.wBrand)   // yazı mürekkep, çubuk marka rengi (2 Kas)
            Text(timerInterval: Date.now...max(to, .now), countsDown: true)
                .monospacedDigit().font(.system(size: 24, weight: .heavy).italic().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            ProgressView(timerInterval: from...max(to, from.addingTimeInterval(1)), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(Color.wLime)
            Text(fasting ? "Bitiş \(to.formatted(date: .omitted, time: .shortened))" : "Oruç \(to.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
