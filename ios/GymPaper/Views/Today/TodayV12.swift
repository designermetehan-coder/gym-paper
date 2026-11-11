import SwiftUI
import SwiftData
import GymPaperKit

// Today (v1.2): week strip, today's workout hero, rest of the day list, weekly muscle card.

// MARK: - Week strip

struct TodayWeekStrip: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    let profile: UserProfile
    let logs: [DayLog]

    private enum DayState { case done, today, planned, rest }

    var body: some View {
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = DayKey.shift(monday, days: i)
                let st = state(d, today: today)
                VStack(spacing: 8) {
                    Text(String(DayKey.dayShort[i].prefix(1)))
                        .font(.geist(11, d == today ? .bold : .medium, relativeTo: .caption2))
                        .foregroundStyle(d == today ? Color.bFg : Color.bMutedFg)
                    circle(st, day: Int(d.suffix(2)) ?? 0)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DayKey.dayLong[i])
                .accessibilityValue(label(st))
            }
        }
        // display only (no jump to Workout on tap)
    }

    @ViewBuilder private func circle(_ st: DayState, day: Int) -> some View {
        ZStack {
            switch st {
            case .done:
                Circle().fill(Color.bRingWorkout)
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.bActionFg)
            case .today:
                Circle().fill(Color.bSel)
                Text("\(day)").font(.geist(14, .semibold)).foregroundStyle(Color.bSelFg)
            case .planned:
                Circle().fill(Color.bFg.opacity(0.08))
                Text("\(day)").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
            case .rest:
                Circle().strokeBorder(Color.bBorder, lineWidth: 1)
                Text("\(day)").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
            }
        }
        .frame(width: 40, height: 40)
        .monospacedDigit()
    }

    private func state(_ d: String, today: String) -> DayState {
        let log = logs.first { $0.date == d }
        let prog = Wk.programFor(d, profile: profile, ctx: ctx)
        if let log, log.workoutDone || (prog.map { workoutProgress($0, day: log).complete } ?? false) { return .done }
        if d == today { return .today }
        return prog == nil ? .rest : .planned
    }
    private func label(_ s: DayState) -> String {
        switch s { case .done: tl("Tamamlandı"); case .today: tl("Bugün"); case .planned: tl("Antrenman var"); case .rest: tl("Dinlenme") }
    }
}

// MARK: - Today's workout hero

struct TodayWorkoutHero: View {
    @Environment(AppState.self) private var app
    let prog: WorkoutProgram?
    let day: DayLog?
    let hasPrograms: Bool
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let prog, !prog.blocks.allExercises.isEmpty {
                let wp = workoutProgress(prog, day: day)
                let exs = prog.blocks.allExercises
                let mins = Int(CalorieEngine.estimatedMinutes(sets: prog.blocks.restProfile).rounded())
                HStack {
                    Text(wp.complete ? "Bugünkü antrenman tamam" : "Bugünkü antrenman").font(.bSm).foregroundStyle(Color.bHeroMuted)
                    Spacer()
                    if wp.complete { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.bHeroAccent) }
                    else { Text("~\(mins) dk").font(.bSm).monospacedDigit().foregroundStyle(Color.bHeroMuted) }
                }
                Text(prog.name.isEmpty ? tl("Antrenman") : prog.name)
                    .font(.bDisplay(34, relativeTo: .largeTitle)).tracking(-0.6).lineLimit(2).minimumScaleFactor(0.7)
                HStack(alignment: .top, spacing: 0) {
                    stat("Hareket", "\(exs.count)", nil)
                    stat("Set", wp.complete || wp.done > 0 ? "\(wp.done)/\(wp.total)" : "\(wp.total)", nil)
                    let vol = volume(exs)
                    if vol > 0 { stat("Hacim", fmt0(vol), "kg") } else { stat("Süre", "~\(mins)", tl("dk")) }
                }
                chips(prog)
                if wp.complete {
                    if let line = completedLine { Text(line).font(.bSm).monospacedDigit().foregroundStyle(Color.bHeroMuted) }
                } else {
                    Button { haptic(); app.openSession(.init(pid: prog.pid, date: date)) } label: {
                        HStack(spacing: 8) {
                            Text(app.session?.date == date ? "Antrenmana dön" : wp.done > 0 ? "Devam et" : "Antrenmanı başlat")
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.b(.primary, .large, full: true))
                }
            } else if !hasPrograms {
                Text("Başlarken").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Text("Henüz programın yok").font(.bDisplay(28, relativeTo: .title))
                Text("Hazır bir programla başla ya da kendininkini kur; günün antrenmanı burada çıkar.").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Button { haptic(); app.setTab(.workout); if app.workoutPath.last != .programs { app.workoutPath.append(.programs) } } label: {
                    HStack(spacing: 8) { Text("Program seç"); Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.b(.primary, .large, full: true))
            } else {
                Text("Bugün").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Text("Dinlenme günü").font(.bDisplay(34, relativeTo: .largeTitle))
                Text("Kasların bugün toparlanıyor. Yürüyüş ve su iyi gelir.").font(.bSm).foregroundStyle(Color.bHeroMuted)
                Button { haptic(); app.setTab(.workout) } label: {
                    HStack(spacing: 8) { Text("Yine de antrenman seç"); Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.b(.secondary, .large, full: true))
            }
        }
        .bHeroCard()
    }

    private func stat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tl(label)).font(.bXs).foregroundStyle(Color.bHeroMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.bNum(24, relativeTo: .title2))
                if let unit { Text(tl(unit)).font(.bXs).foregroundStyle(Color.bHeroMuted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func chips(_ prog: WorkoutProgram) -> some View {
        let muscles = MuscleLoad.load(MuscleData.plan(prog.blocks), scope: .workout).prefix(3).map(\.muscle)
        if !muscles.isEmpty {
            HStack(spacing: 6) {
                ForEach(muscles, id: \.self) { m in
                    Text(tl(m)).font(.geist(12, .medium, relativeTo: .caption))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.bHeroFill, in: Capsule())
                }
            }
        }
    }

    private func volume(_ exs: [Exercise]) -> Double {
        exs.reduce(0) { $0 + ($1.unit == "tekrar" ? Double($1.sets * $1.reps) * ($1.kg ?? 0) : 0) }
    }
    private var completedLine: String? {
        var parts: [String] = []
        if let sec = day?.workoutSeconds, sec > 0 { parts.append(String(localized: "\(sec / 60) dk")) }
        if let k = day?.workoutKcal, k > 0 { parts.append(String(localized: "\(fmt0(k)) kcal")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Rest of the day

struct TodayRestOfDay: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    let profile: UserProfile
    let day: DayLog?
    let energy: EnergySummary
    var showEnergy: () -> Void
    var showFast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Günün geri kalanı").font(.bDisplay(20, relativeTo: .title3)).foregroundStyle(Color.bFg)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Button(action: showEnergy) {
                    row(icon: "flame", tint: .fitKcal, title: "Kalori",
                        sub: String(localized: "\(fmt0(energy.eaten)) yendi · hedef \(fmt0(energy.target))")) {
                        Text(energy.remaining >= 0 ? String(localized: "\(fmt0(energy.remaining)) kaldı") : String(localized: "\(fmt0(-energy.remaining)) fazla"))
                            .font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
                    }
                }
                if let meal = nextMeal {
                    divider
                    Button { haptic(); app.open(.addFood(date: DayKey.today, meal: meal)) } label: {
                        row(icon: "tools-kitchen-2", tint: Color(uiColor: .dyn(UIColor(hex: 0xD73F00), UIColor(hex: 0xFE7802))),
                            title: meal.label, sub: tl("Henüz eklenmedi")) { plus }
                    }
                }
                divider
                Button { addWater() } label: {
                    row(icon: "droplet", tint: .fitBlue, title: "Su",
                        sub: "\(fmt1(Double(day?.waterMl ?? 0) / 1000)) / \(fmt1(Double(profile.waterMl) / 1000)) L") { plus }
                }
                .accessibilityHint(Text("\(max(50, profile.waterStepMl)) ml ekler"))
                divider
                row(icon: "walk", tint: .fitGreen, title: "Adım",
                    sub: String(localized: "hedef \(fmt0(Double(profile.stepGoal)))")) {
                    Text(fmt0(Double(max(health.stepsToday, day?.steps ?? 0)))).font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
                }
                if profile.fastOn {
                    divider
                    Button(action: showFast) { fastRow }
                }
            }
            .buttonStyle(.press)
            .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        }
    }

    private var fastRow: some View {
        TimelineView(.periodic(from: .now, by: 30)) { t in
            let f = profile.fast
            switch f.phase(at: t.date) {
            case let .fasting(_, end, _):
                row(icon: "moon", tint: .fitPurple, title: "Oruç", sub: "\(f.endText) – \(f.startText) · \(f.label)") {
                    Text(FastCard.dur(end.timeIntervalSince(t.date))).font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
                }
            case let .eating(_, next, _):
                row(icon: "moon", tint: .fitPurple, title: "Yeme aralığı", sub: "\(f.endText) – \(f.startText) · \(f.label)") {
                    Text(FastCard.dur(next.timeIntervalSince(t.date))).font(.bDisplay(16, relativeTo: .body)).monospacedDigit()
                }
            }
        }
    }

    private var plus: some View { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.bFg).frame(width: 28, height: 28) }
    private var divider: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 64) }

    private func row<T: View>(icon: String, tint: Color, title: String, sub: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Ti(icon, size: 18).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(tl(title)).font(.geist(16, .semibold, relativeTo: .headline)).foregroundStyle(Color.bFg)
                Text(sub).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing().foregroundStyle(Color.bFg)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// First enabled meal from now on that has nothing logged yet
    private var nextMeal: Meal? {
        let on = profile.meals
        let cur = Meal.default(enabled: on)
        let order = Meal.allCases.filter { on.contains($0) }
        guard let i = order.firstIndex(of: cur) else { return nil }
        let logged = Set((day?.entries ?? []).map(\.meal))
        return order[i...].first { !logged.contains($0) }
    }

    private func addWater() {
        haptic()
        guard let d = Store.day(ctx, DayKey.today) else { return }
        d.waterMl = min(20_000, d.waterMl + max(50, profile.waterStepMl))
        Store.save(ctx)
    }
}

// MARK: - Muscles this week (Today)

struct TodayMuscleCompact: View {
    @Environment(\.modelContext) private var ctx
    let logs: [DayLog]
    var body: some View {
        let w = MuscleData.week(ctx, logs: logs)
        let entries = MuscleLoad.load(w.items, scope: .week)
        let levels = Dictionary(entries.map { ($0.muscle, $0.level) }, uniquingKeysWith: { a, _ in a })
        NavigationLink { MuscleMapScreen() } label: {
            HStack(spacing: 14) {
                MuscleMapView(levels: levels, figureHeight: 110).frame(width: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bu hafta kaslar").font(.bDisplay(17, relativeTo: .headline))
                    Text(sub(entries, w.sets)).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(2)
                    // never wider than the card: one row when it fits, otherwise two
                    ViewThatFits(in: .horizontal) {
                        HeatLegend(scope: .week, spacing: 10, alignment: .leading).fixedSize()
                        HeatLegend(scope: .week, spacing: 10, alignment: .leading, twoRows: true).fixedSize()
                    }
                }
                Spacer(minLength: 0)
                Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
            }
            .foregroundStyle(Color.bFg)
            .bCard()
        }
        .buttonStyle(.press)
    }
    private func sub(_ e: [MuscleLoad.Entry], _ sets: Int) -> String {
        guard !e.isEmpty else { return tl("Bu hafta henüz antrenman yok") }
        if let low = e.filter({ $0.sets < 10 }).max(by: { $0.sets < $1.sets }) {
            return String(localized: "\(tl(low.muscle)) hedefin altında · \(MuscleLoad.format(low.sets))/10 set")
        }
        return String(localized: "\(sets) set · tüm gruplar hedefte")
    }
}
