import SwiftUI
import SwiftData
import BalliKit

/// Son 365 gün (YR-01): GitHub katkı tablosu gibi her gün bir nokta.
/// Tek grafik; segmented ile Adım (3 bin+, 5 bin+, 10 bin+) ↔ Spor (antrenman günleri) geçişi (2 Kas).
/// Kendi sorgusunu yapar; Özet'in 31 günlük sorgusu büyümesin.
struct TodayYearCard: View {
    @Environment(HealthService.self) private var health
    @Query private var logs: [DayLog]
    @State private var hkSteps: [String: Int] = [:]
    enum Mode: Hashable { case steps, workout }
    @State private var mode = Mode.steps
    private let first: String     // tablonun ilk pazartesisi

    init() {
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let start = DayKey.shift(monday, days: -52 * 7)
        first = start
        _logs = Query(filter: #Predicate<DayLog> { $0.date >= start })
    }

    private static let stepTiers = [3_000, 5_000, 10_000]

    var body: some View {
        let today = DayKey.today
        let dict = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { a, b in a.workoutDone ? a : b })
        let from = DayKey.shift(today, days: -364)
        let keys = (0..<(53 * 7)).map { DayKey.shift(first, days: $0) }
        let workout: [Int] = keys.map { k in k > today ? -1 : (dict[k]?.workoutDone == true ? 1 : 0) }
        let steps: [Int] = keys.map { k in
            guard k <= today else { return -1 }
            let n = max(dict[k]?.steps ?? 0, hkSteps[k] ?? 0, k == today ? health.stepsToday : 0)
            return Self.stepTiers.lastIndex(where: { n >= $0 }).map { $0 + 1 } ?? 0
        }
        let inYear = keys.enumerated().filter { $0.element >= from && $0.element <= today }.map(\.offset)
        let wDays = inYear.filter { workout[$0] == 1 }.count
        let tenK = inYear.filter { steps[$0] == 3 }.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TodayColorCaption("Son 365 gün", symbol: "square.grid.3x3.fill", tint: .bPrimary)
                Spacer()
                Text(mode == .steps ? "\(tenK) gün 10 bin+" : "\(wDays) gün spor")
                    .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
            }
            BSegmented(selection: $mode, options: [(.steps, "Adım"), (.workout, "Spor")], neutral: true)
                .padding(.top, 12)
            Group {
                if mode == .steps {
                    YearDots(levels: steps) { l in Color.fitGreen.opacity([0, 0.35, 0.65, 1][l]) }
                        .accessibilityLabel("Son 365 günde \(tenK) gün 10 binden fazla adım")
                } else {
                    YearDots(levels: workout) { _ in Color.fitBlue }
                        .accessibilityLabel("Son 365 günde \(wDays) gün antrenman yapıldı")
                }
            }
            .accessibilityElement(children: .ignore)
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.2), value: mode)

            // Açıklama grafiğin altında
            HStack(spacing: 10) {
                Text(Self.monthYear(first)).font(.geist(10)).foregroundStyle(Color.bMutedFg)
                Spacer(minLength: 4)
                if mode == .steps {
                    legend("3 bin+", .fitGreen, 0.35); legend("5 bin+", .fitGreen, 0.65); legend("10 bin+", .fitGreen, 1)
                } else {
                    legend("Antrenman", .fitBlue, 1)
                }
                Spacer(minLength: 4)
                Text("Bugün").font(.geist(10)).foregroundStyle(Color.bMutedFg)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bCard()
        .task { await load() }
    }

    private static func monthYear(_ k: String) -> String {
        let m = DayKey.monthShort
        let p = k.split(separator: "-")
        guard p.count == 3, let mo = Int(p[1]), (1...12).contains(mo) else { return "" }
        return "\(m[mo - 1]) \(p[0])"
    }

    private func legend(_ t: String, _ c: Color, _ o: Double) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c.opacity(o)).frame(width: 7, height: 7)
            Text(tl(t)).font(.geist(10)).foregroundStyle(Color.bMutedFg)
        }
    }

    private func load() async {
        guard health.available, health.authorized else { return }
        hkSteps = await health.dailySteps(from: first)
    }
}

/// 53 sütun × 7 satır nokta; sütun = hafta (pazartesi üstte), -1 = gelecek gün (çizilmez), 0 = boş
private struct YearDots: View {
    let levels: [Int]
    let color: (Int) -> Color
    var body: some View {
        GeometryReader { g in
            let cell = g.size.width / 53
            let d = cell * 0.78
            Canvas { ctx, _ in
                let empty = Color.bFg.opacity(0.08)
                for (i, l) in levels.enumerated() where l >= 0 {
                    let c = i / 7, r = i % 7
                    let rect = CGRect(x: CGFloat(c) * cell + (cell - d) / 2, y: CGFloat(r) * cell + (cell - d) / 2, width: d, height: d)
                    ctx.fill(Path(ellipseIn: rect), with: .color(l == 0 ? empty : color(l)))
                }
            }
        }
        .aspectRatio(53.0 / 7.0, contentMode: .fit)
    }
}
