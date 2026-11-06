import WidgetKit
import SwiftUI
import BalliKit

/// WG-03 · Bugünün antrenmanı (büyük boyda önümüzdeki günler)
struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "balli.antrenman", provider: SnapProvider()) { e in
            WorkoutWidgetView(e: e).balliBackground().widgetURL(URL(string: "gympaper://tab/workout"))
        }
        .configurationDisplayName("Bugünün antrenmanı")
        .description("Günün programı, hareketler ve tahmini süre.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])   // büyük boy kaldırıldı (2 Kas)
    }
}

struct WorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let today = s.workout(on: e.day)
        if e.snap == nil {
            OpenAppNote()
        } else {
            switch family {
            case .accessoryCircular:
                // Adım halkasıyla aynı dil: antrenman günü set ilerlemesi + dambıl; dinlenme gününde yatak
                if case .some(.some(let w)) = today {
                    let done = s.workoutDone ? w.sets : min(s.setsDone, w.sets)
                    Gauge(value: w.sets > 0 ? Double(done) / Double(w.sets) : 0) {
                        Image(systemName: "dumbbell.fill")
                    } currentValueLabel: {
                        if s.workoutDone {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                        } else {
                            Text("\(done)/\(w.sets)").font(.system(size: 17, weight: .heavy).italic().monospacedDigit())
                                .minimumScaleFactor(0.5).lineLimit(1)
                        }
                    }
                    .gaugeStyle(.accessoryCircular)
                    .widgetAccentable()
                } else {
                    Gauge(value: 0) {
                        Text("Dinlen").font(.system(size: 9, weight: .semibold))
                    } currentValueLabel: {
                        Image(systemName: "bed.double.fill").font(.system(size: 17, weight: .semibold))
                    }
                    .gaugeStyle(.accessoryCircular)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Bugün", systemImage: "dumbbell").font(.caption).widgetAccentable()
                    Text(title(today)).font(.headline).lineLimit(1)
                    if case .some(.some(let w)) = today { Text("\(w.minutes) dk · \(w.sets) set").font(.caption) }
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 6) {
                    header(s)
                    Spacer(minLength: 0)
                    Text(title(today)).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    if case .some(.some(let w)) = today {
                        Text("\(w.minutes) dk · \(w.sets) set").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    header(s)
                    Text(title(today)).font(.title3.weight(.semibold)).lineLimit(1)
                    if case .some(.some(let w)) = today {
                        let max = family == .systemLarge ? 6 : 2
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(w.exercises.prefix(max).enumerated()), id: \.offset) { _, n in
                                Text("• \(n)").font(.caption).lineLimit(1)
                            }
                            if w.exercises.count > max {
                                Text("+\(w.exercises.count - max) hareket").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("\(w.minutes) dk · \(w.sets) set").font(.caption).foregroundStyle(.secondary)
                    } else if case .some(.none) = today {
                        Text("Dinlen, toparlan. Su ve uyku bugünün işi.").font(.caption).foregroundStyle(.secondary)
                    }
                    if family == .systemLarge {
                        Divider()
                        upcoming(s)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        HStack {
            Image(systemName: "dumbbell.fill").foregroundStyle(Color.wBrand).widgetAccentable()   // (TE-05)
            Text("Bugün").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if s.workoutDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }

    private func title(_ w: WidgetWorkout??) -> String {
        switch w {
        case .some(.some(let x)): x.name
        case .some(.none): tl("Dinlenme günü")
        case .none: tl("Plan yok")
        }
    }

    private func upcoming(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(1..<5, id: \.self) { i in
                let k = DayKey.shift(e.day, days: i)
                if let w = s.workout(on: k) {
                    HStack {
                        Text(i == 1 ? tl("Yarın") : DayKey.dayLong[DayKey.weekday(k)]).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(w?.name ?? tl("Dinlenme")).font(.caption).lineLimit(1)
                    }
                }
            }
        }
    }
}
