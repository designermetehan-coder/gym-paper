import SwiftUI
import SwiftData
import GymPaperKit

// Progress tab (Figma "Progress · Overview"): weight hero, muscles worked this week, measurements, activity history, team.

struct ProgressScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    @Query private var logs: [DayLog]

    var body: some View {
        let p = profiles.first ?? UserProfile()
        let G = GoalState(startKg: p.startKg, goals: p.goals, measures: measures)
        BScreen {
            BHeader(title: "İlerleme") {
                BRoundIcon(icon: "ruler", label: "Ölçüm ekle") { app.open(.measure(quick: false)) }
            }
            ProgressWeightCard(G: G, measures: measures) { app.open(.measure(quick: true)) }
            // weight goals moved here from Profile (tap edits them)
            if !G.goals.isEmpty {
                NavigationLink { ProfileGoalsSheet().environment(\.bSheetPushed, true) } label: { WeightGoalsCard(G: G, showCurrent: false) }
                    .buttonStyle(.press)
            }
            NavigationLink { MuscleMapScreen() } label: { ProgressMuscleCard(logs: logs) }
                .buttonStyle(.press)
            VStack(spacing: 0) {
                NavigationLink { ProfileMeasuresScreen() } label: {
                    ProgressRow(icon: "ruler", title: "Ölçümlerim", sub: measuresSub)
                }
                ProgressDivider()
                NavigationLink { ActivityHistoryScreen() } label: {
                    ProgressRow(icon: "history", title: "Aktivite geçmişi", sub: tl("Son 365 gün: adım ve antrenman"))
                }
                ProgressDivider()
                NavigationLink { MilestonesScreen() } label: {
                    ProgressRow(icon: "trophy", title: "Rozetler", sub: tl("Seri ve kilometre taşları"))
                }
            }
            .buttonStyle(.press)
            .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        }
    }

    private var measuresSub: String {
        guard !measures.isEmpty else { return tl("Henüz ölçüm yok") }
        let waist = measures.compactMap(\.waistCm)
        if waist.count >= 2, let last = waist.first, let first = waist.last, abs(last - first) >= 0.5 {
            return String(localized: "\(measures.count) ölçüm · bel \(last < first ? "−" : "+")\(fmt1(abs(last - first))) cm")
        }
        return String(localized: "\(measures.count) ölçüm")
    }
}

// MARK: - Weight hero

struct ProgressWeightCard: View {
    let G: GoalState
    let measures: [BodyMeasure]
    var add: () -> Void

    var body: some View {
        let weeks = weeklyKg()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Kilo").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Spacer()
                if let d = change3m() { trend(d) }
            }
            if let cur = G.cur {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fmt1(cur)).font(.bNum(52, relativeTo: .largeTitle))
                    Text("kg").font(.bSm).foregroundStyle(Color.bHeroMuted)
                }
                bars(weeks)
                if let goal = G.active, let start = G.start {
                    VStack(alignment: .leading, spacing: 8) {
                        BProgress(value: G.pct, tint: .bHeroHi, height: 6, track: .bHeroFill, label: "Kilo hedefi")
                        HStack {
                            Text("Başlangıç \(fmt1(start))").foregroundStyle(Color.bHeroMuted)
                            Spacer()
                            Text(G.done ? tl("Hedefe ulaştın") : String(localized: "Hedefe \(fmt1(G.left)) kg"))
                                .font(.geist(12, .semibold, relativeTo: .caption))
                            Spacer()
                            Text("Hedef \(fmt1(goal))").foregroundStyle(Color.bHeroMuted)
                        }
                        .font(.bXs).monospacedDigit()
                    }
                }
            } else {
                Text("Kilonu ekle, değişimi burada gör.").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Button(action: add) { Text("Kilo gir") }.buttonStyle(.b(.primary, full: true))
            }
        }
        .bHeroCard()
    }

    private func trend(_ d: Double) -> some View {
        HStack(spacing: 4) {
            Ti(d <= 0 ? "trending-down" : "trending-up", size: 14)
            Text(String(localized: "\(fmt1(abs(d))) kg · 3 ay")).font(.geist(12, .medium, relativeTo: .caption)).monospacedDigit()
        }
        .foregroundStyle(Color.bVolume3)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.bVolume3.opacity(0.18), in: Capsule())
    }

    private func bars(_ w: [Double?]) -> some View {
        let vals = w.compactMap { $0 }
        let lo = (vals.min() ?? 0) - 1, hi = max((vals.max() ?? 1), lo + 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(w.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(i == w.count - 1 ? Color.bHeroHi : Color.bHeroFill)
                    .frame(height: v.map { 14 + 40 * ($0 - lo) / (hi - lo) } ?? 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56, alignment: .bottom)
        .accessibilityHidden(true)
    }

    /// Last weigh-in of each of the last 12 weeks (nil: no weigh-in that week)
    private func weeklyKg() -> [Double?] {
        let cal = Calendar.current
        let now = Date.now
        return (0..<12).reversed().map { i in
            guard let end = cal.date(byAdding: .day, value: -7 * i, to: now), let start = cal.date(byAdding: .day, value: -7, to: end) else { return nil }
            return measures.first { $0.kg != nil && $0.date > start && $0.date <= end }?.kg
        }
    }
    private func change3m() -> Double? {
        guard let cur = measures.first(where: { $0.kg != nil })?.kg,
              let from = Calendar.current.date(byAdding: .month, value: -3, to: .now) else { return nil }
        let old = measures.last { $0.kg != nil && $0.date >= from }?.kg
        guard let old, abs(cur - old) >= 0.1 else { return nil }
        return cur - old
    }
}

// MARK: - Muscles this week (compact)

struct ProgressMuscleCard: View {
    @Environment(\.modelContext) private var ctx
    let logs: [DayLog]
    var body: some View {
        let w = MuscleData.week(ctx, logs: logs)
        let entries = MuscleLoad.load(w.items, scope: .week)
        let levels = Dictionary(entries.map { ($0.muscle, $0.level) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bu hafta çalışan kaslar").font(.geist(16, .semibold, relativeTo: .headline))
                Spacer(minLength: 8)
                Text(String(localized: "\(w.workouts) antrenman · \(w.sets) set")).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
            }
            if entries.isEmpty {
                HStack(spacing: 16) {
                    MuscleMapView(levels: [:], figureHeight: 120).frame(width: 150)
                    Text("Bu hafta henüz antrenman yok. İlk antrenmandan sonra kaslar burada renklenir.")
                        .font(.bSm).foregroundStyle(Color.bMutedFg)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    MuscleMapView(levels: levels, figureHeight: 130).frame(width: 150)
                    VStack(spacing: 10) {
                        ForEach(entries.prefix(5)) { e in
                            HStack(spacing: 8) {
                                Circle().fill(Color.bHeat(e.level)).frame(width: 8, height: 8)
                                Text(tl(e.muscle)).font(.bSm).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(String(localized: "\(MuscleLoad.format(e.sets)) set")).font(.bDisplay(14, relativeTo: .subheadline)).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.bFg)
        .bCard()
    }
}

// MARK: - Muscle map screen (This week · Last week · 4 weeks)

struct MuscleMapScreen: View {
    @Environment(\.modelContext) private var ctx
    @Query private var logs: [DayLog]
    enum Period: String, CaseIterable, Hashable { case thisWeek, lastWeek, fourWeeks }
    @State private var period = Period.thisWeek

    var body: some View {
        let r = range(period)
        let w = MuscleData.range(ctx, logs: logs, from: r.from, to: r.to)
        let weeks: Double = period == .fourWeeks ? 4 : 1
        let entries = MuscleLoad.load(w.items, scope: .week).map { e -> MuscleLoad.Entry in
            var e = e; e.level = MuscleLoad.level(e.sets / weeks, .week); return e
        }
        let levels = Dictionary(entries.map { ($0.muscle, $0.level) }, uniquingKeysWith: { a, _ in a })
        BScreen(pinHeader: false) {
            WkPushedHeader(title: "Kas haritası", sub: String(localized: "\(w.workouts) antrenman · \(w.sets) set"))
            HStack(spacing: 8) {
                ForEach(Period.allCases, id: \.self) { p in
                    Button { haptic(); withAnimation(.snappy) { period = p } } label: {
                        Text(title(p)).font(.geist(14, .medium, relativeTo: .subheadline))
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .foregroundStyle(period == p ? Color.bSelFg : Color.bFg)
                            .background(period == p ? AnyShapeStyle(Color.bSel) : AnyShapeStyle(Color.bCard.opacity(0.6)), in: Capsule())
                    }
                    .buttonStyle(.press)
                    .accessibilityAddTraits(period == p ? .isSelected : [])
                }
            }
            VStack(spacing: 16) {
                MuscleMapView(levels: levels).padding(.vertical, 4)
                HeatLegend(scope: .week)
            }
            .bCard()
            VStack(alignment: .leading, spacing: 16) {
                if entries.isEmpty {
                    Text("Bu dönemde kayıtlı set yok.").font(.bSm).foregroundStyle(Color.bMutedFg)
                } else {
                    ForEach(entries) { e in MuscleTargetRow(entry: e, perWeek: e.sets / weeks) }
                    Text("Çizgiler haftalık hedef aralığı: 10–20 set").font(.bXs).foregroundStyle(Color.bMutedFg)
                }
            }
            .bCard()
        }
    }

    private func title(_ p: Period) -> String {
        switch p { case .thisWeek: tl("Bu hafta"); case .lastWeek: tl("Geçen hafta"); case .fourWeeks: tl("4 hafta") }
    }
    private func range(_ p: Period) -> (from: String, to: String) {
        let today = DayKey.today, monday = DayKey.shift(today, days: -DayKey.weekday(today))
        switch p {
        case .thisWeek: return (monday, today)
        case .lastWeek: return (DayKey.shift(monday, days: -7), DayKey.shift(monday, days: -1))
        case .fourWeeks: return (DayKey.shift(monday, days: -21), today)
        }
    }
}

/// Muscle row with the 10–20 weekly target band shaded behind the bar
struct MuscleTargetRow: View {
    let entry: MuscleLoad.Entry
    let perWeek: Double
    private let scaleMax = 24.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.bHeat(entry.level)).frame(width: 8, height: 8)
                Text(tl(entry.muscle)).font(.geist(15, .medium, relativeTo: .body))
                Spacer(minLength: 6)
                status
                Text(MuscleLoad.format(perWeek.rounded(toPlaces: 1))).font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
                Text("set").font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            // one track + fill; the 10–20 target band is two thin ticks (a shaded band read as a third color)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.bFg.opacity(0.08))
                        Capsule().fill(Color.bHeat(entry.level)).frame(width: g.size.width * min(1, perWeek / scaleMax))
                    }
                    .frame(height: 8)
                    .clipShape(Capsule())
                    ForEach([10.0, 20.0], id: \.self) { t in
                        Capsule().fill(Color.bFg.opacity(0.45)).frame(width: 2, height: 14)
                            .offset(x: g.size.width * t / scaleMax - 1)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var status: some View {
        let (t, on): (String, Bool) = perWeek > 20 ? (tl("Fazla"), false) : perWeek >= 10 ? (tl("Hedefte"), true) : (tl("Az"), false)
        Text(t).font(.geist(12, .semibold, relativeTo: .caption))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(perWeek > 20 ? Color.bSelFg : on ? Color.bVolume3 : Color.bFg)
            .background {
                if perWeek > 20 { Capsule().fill(Color.bSel) }
                else if on { Capsule().fill(Color.bVolume3.opacity(0.16)) }
                else { Capsule().strokeBorder(Color.bBorder, lineWidth: 1) }
            }
    }
}

// MARK: - Activity history (365 days)

struct ActivityHistoryScreen: View {
    var body: some View {
        BScreen(pinHeader: false) {
            WkPushedHeader(title: "Aktivite geçmişi", sub: tl("Son 365 gün"))
            TodayYearCard()
        }
    }
}

// MARK: - Shared rows

struct ProgressRow: View {
    let icon: String; let title: String; let sub: String
    var body: some View {
        HStack(spacing: 12) {
            Ti(icon, size: 20)
                .frame(width: 40, height: 40)
                .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tl(title)).font(.geist(16, .semibold, relativeTo: .headline))
                Text(sub).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1)
            }
            Spacer(minLength: 8)
            Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
        }
        .foregroundStyle(Color.bFg)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct ProgressDivider: View {
    var body: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 68) }
}
