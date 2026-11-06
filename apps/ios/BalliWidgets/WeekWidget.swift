import WidgetKit
import SwiftUI
import BalliKit

/// WG-06 · Haftalık antrenman takvimi
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "balli.hafta", provider: SnapProvider()) { e in
            WeekView(e: e).balliBackground().widgetURL(URL(string: "gympaper://tab/workout"))
        }
        .configurationDisplayName("Bu hafta")
        .description("Haftanın antrenmanları: yapılan, planlanan ve dinlenme günleri.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekView: View {
    let e: SnapEntry

    var body: some View {
        let s = e.s
        let week = currentWeek(s)
        let planned = week.filter { $0.name != nil }.count
        let done = week.filter { $0.name != nil && ($0.done || ($0.date == e.day && s.workoutDone)) }.count
        let today = week.first { $0.date == e.day }
        if e.snap == nil || week.isEmpty {
            OpenAppNote()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "dumbbell.fill").foregroundStyle(Color.wBrand).widgetAccentable()
                    Text("Bu hafta").font(.headline)
                    Spacer()
                    Text("\(done)/\(planned) antrenman").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { i, d in
                        day(i, d, isToday: d.date == e.day, doneToday: d.date == e.day && s.workoutDone)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
                Group {
                    if let t = today?.name {
                        let w = s.workout(on: e.day)
                        let extra: String = { if case .some(.some(let x)) = w { return String(localized: " · \(x.minutes) dk") }; return "" }()
                        Text("Bugün: ").foregroundStyle(.secondary) + Text(t + extra).fontWeight(.semibold)
                    } else {
                        Text("Bugün dinlenme").foregroundStyle(.secondary)
                    }
                }
                .font(.caption).lineLimit(1)
            }
        }
    }

    /// Pazartesi gece yarısı uygulama açılmadan: yeni haftayı bilinen plandan kur (WG-08)
    private func currentWeek(_ s: WidgetSnapshot) -> [WidgetWeekDay] {
        let w = s.week ?? []
        if w.contains(where: { $0.date == e.day }) { return w }
        let monday = DayKey.shift(e.day, days: -DayKey.weekday(e.day))
        return (0..<7).map { i in
            let k = DayKey.shift(monday, days: i)
            let name: String? = { if case .some(.some(let x)) = s.workout(on: k) { return x.name }; return nil }()
            return WidgetWeekDay(date: k, name: name, done: false)
        }
    }

    private func day(_ i: Int, _ d: WidgetWeekDay, isToday: Bool, doneToday: Bool) -> some View {
        let past = d.date < e.day
        let isDone = d.done || doneToday
        return VStack(spacing: 5) {
            Text(String(DayKey.dayShort[i].prefix(2))).font(.caption2.weight(isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.primary : .secondary)
            ZStack {
                if d.name == nil {
                    Circle().fill(Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
                } else if isDone {
                    Circle().fill(Color.wBrand)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.wOnBrand)   // (TE-05)
                } else if past {
                    Circle().stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                } else {
                    Circle().stroke(Color.wBrand, lineWidth: 2)
                }
            }
            .frame(width: 26, height: 26)
            .widgetAccentable()
            .overlay { if isToday { Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1).padding(-4) } }
        }
    }
}
