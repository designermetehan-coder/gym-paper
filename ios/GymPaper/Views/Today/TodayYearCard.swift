import SwiftUI
import SwiftData
import GymPaperKit

/// Last 365 days: one dot per day, like the GitHub contribution graph.
/// One chart; a segmented control switches Steps ↔ Workouts.
/// Steps: 6 levels relative to the goal on one green ramp; Workouts: workout days in green.
/// Runs its own query so Today's 31-day query stays small.
struct TodayYearCard: View {
    @Environment(HealthService.self) private var health
    @Query private var logs: [DayLog]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
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

    /// Level thresholds as a share of the step goal: 1 = under 25% (but some steps), 6 = goal or more
    private static let stepShares = [0.25, 0.5, 0.65, 0.8, 1.0]
    static func tone(_ l: Int) -> Color {
        [Color.clear, .stepTier1, .stepTier2, .stepTier3, .stepTier4, .stepTier5, .stepTier6][max(0, min(6, l))]
    }
    private var goal: Int { max(1_000, profiles.first?.stepGoal ?? 8_000) }
    private var thresholds: [Int] { Self.stepShares.map { Int((Double(goal) * $0).rounded()) } }
    private static func kStr(_ n: Int) -> String {
        let v = (Double(n) / 100).rounded() / 10
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    var body: some View {
        let today = DayKey.today
        let dict = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { a, b in a.workoutDone ? a : b })
        let from = DayKey.shift(today, days: -364)
        let keys = (0..<(53 * 7)).map { DayKey.shift(first, days: $0) }
        let workout: [Int] = keys.map { k in k > today ? -1 : (dict[k]?.workoutDone == true ? 1 : 0) }
        let th = thresholds
        let steps: [Int] = keys.map { k in
            guard k <= today else { return -1 }
            let n = max(dict[k]?.steps ?? 0, hkSteps[k] ?? 0, k == today ? health.stepsToday : 0)
            guard n > 0 else { return 0 }
            return th.lastIndex(where: { n >= $0 }).map { $0 + 2 } ?? 1
        }
        let inYear = keys.enumerated().filter { $0.element >= from && $0.element <= today }.map(\.offset)
        let wDays = inYear.filter { workout[$0] == 1 }.count
        let hit = inYear.filter { steps[$0] == 6 }.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                TodayColorCaption("Son 365 gün", symbol: "square.grid.3x3.fill", tint: .bPrimary)
                Spacer()
                Text(mode == .steps ? "\(hit) gün hedef" : "\(wDays) gün spor")
                    .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
            }
            BSegmented(selection: $mode, options: [(.steps, "Adım"), (.workout, "Spor")], neutral: true)
                .padding(.top, 12)
            Group {
                if mode == .steps {
                    YearDots(levels: steps) { l in Self.tone(l) }
                        .accessibilityLabel("Son 365 günde \(hit) gün adım hedefine ulaşıldı")
                } else {
                    YearDots(levels: workout) { _ in Color.stepTier6 }
                        .accessibilityLabel("Son 365 günde \(wDays) gün antrenman yapıldı")
                }
            }
            .accessibilityElement(children: .ignore)
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.2), value: mode)

            // legend below the chart
            HStack(spacing: 10) {
                Text(Self.monthYear(first)).font(.geist(10)).foregroundStyle(Color.bMutedFg)
                Spacer(minLength: 4)
                if mode == .workout { legend("Antrenman", .stepTier6, 1) }
                Spacer(minLength: 4)
                Text("Bugün").font(.geist(10)).foregroundStyle(Color.bMutedFg)
            }
            .padding(.top, 8)

            // step levels: dot + threshold, as in the grid (relative to the goal)
            if mode == .steps {
                HStack(spacing: 0) {
                    ForEach(1...6, id: \.self) { l in
                        let t = l == 1 ? "<\(Self.kStr(th[0]))" : l == 6 ? "\(Self.kStr(th[4])) " + tl("bin") + "+" : "\(Self.kStr(th[l - 2]))+"
                        legend(t, Self.tone(l), 1)
                        if l < 6 { Spacer(minLength: 4) }
                    }
                }
                .padding(.top, 10)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .bCard()
        // Health access may be unknown at launch: past steps reload once it's settled
        .task(id: health.authorized) { await load() }
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
        guard health.available else { return }
        let v = await health.dailySteps(from: first)
        if !v.isEmpty { hkSteps = v }
    }
}

/// 53 columns × 7 rows of dots; column = week (Monday on top), -1 = future day (not drawn), 0 = empty
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
