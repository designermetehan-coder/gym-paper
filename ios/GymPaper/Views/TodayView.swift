import SwiftUI
import SwiftData
import GymPaperKit
import TipKit

// Today

struct TodayView: View {
    /// Store screenshot mode (-demo -year); no DemoData in Release builds
    private static var demoYear: Bool {
        #if DEBUG
        DemoData.active && ProcessInfo.processInfo.arguments.contains("-year")
        #else
        false
        #endif
    }
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var phase
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    /// Only the latest measurement with weight, not the whole history
    @Query private var measures: [BodyMeasure]
    /// Only the last 3 weeks, so the whole history isn't scanned on every render
    @Query private var logs: [DayLog]
    init() {
        let from = DayKey.shift(DayKey.today, days: -31)   // 30 days for the monthly energy balance view
        _logs = Query(filter: #Predicate<DayLog> { $0.date >= from })
        var m = FetchDescriptor<BodyMeasure>(predicate: #Predicate { $0.kg != nil }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        m.fetchLimit = 1
        _measures = Query(m)
    }
    @Query(sort: \WorkoutProgram.createdAt) private var programs: [WorkoutProgram]
    @State private var date = DayKey.today
    @State private var showEnergy = false
    @State private var showList = false
    /// Shared height of small and wide widgets; grows with the text size
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 164
    @State private var fastSettings = false
    @State private var game: GameSummary?
    @State private var showStreak = false

    var body: some View {
        let profile = profiles.first ?? UserProfile()
        let day = logs.day(date)
        let prog: WorkoutProgram? = {
            let id: String?
            if let raw = day?.programIdRaw { id = raw.isEmpty ? nil : raw } else { id = Schedule.programId(profile.schedule, date: date) }
            return id.flatMap { id in programs.first { $0.pid == id } }
        }()
        BScreen {
            BHeader(title: "Bugün") {
                // streak: a meal or a workout a day keeps it; tap opens the streak sheet
                if let g = game, g.streak.count > 0 {
                    Button { haptic(); showStreak = true } label: { StreakChip(count: g.streak.count) }
                        .buttonStyle(.press)
                }
                BRoundIcon(icon: "user-circle", label: "Profil") { app.open(.profile) }
            }
            WeeklyCheckInCard(profile: profile)
            // Getting started
            StartChecklist(hasProgram: !programs.isEmpty,
                           didWorkout: logs.contains { $0.workoutDone },
                           didFood: logs.contains { $0.entriesData.count > 2 },
                           didWeight: !measures.isEmpty)
            TodayWorkoutHero(prog: prog, day: day, hasPrograms: programs.contains { !$0.archived }, date: date)
            // nutrition open below the workout; steps and water side by side (same height, like widgets)
            TodayNutritionCard(profile: profile, day: day, latestKg: measures.first?.kg, showEnergy: $showEnergy)
            HStack(spacing: 12) {
                TodayStepsCard(profile: profile, date: date, logged: day?.steps ?? 0)
                TodayWaterCard(profile: profile, date: date, ml: day?.waterMl ?? 0)
            }
            .frame(height: cellHeight)
            TodayMuscleCompact(logs: logs)
        }
        .sheet(isPresented: $fastSettings) { FastSettingsSheet(profile: profile) }
        .sheet(isPresented: $showStreak) { if let g = game { StreakSheet(g: g) } }
        .onAppear { game = GameSummary.build(ctx: ctx, profile: profile, todaySteps: health.stepsToday) }
        .onChange(of: gameKey) {
            game = GameSummary.build(ctx: ctx, profile: profile, todaySteps: health.stepsToday)
        }
        .goalCelebration()
        .badgeCelebrations()
        .gymPaperTheme()
        .sheet(isPresented: $showEnergy) {
            TodayEnergySheet(e: energy(profile, day))
        }
        .shot("today.energy") { showEnergy = true }
        .shot("today.fast") { fastSettings = true }
        .shot("today.streak") { showStreak = true }
        .shot("today.profile") { app.sheet = .profile }
        .onAppear { syncDate() }
        .onChange(of: phase) { _, p in if p == .active { syncDate() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in syncDate() }
    }

    /// Changes when a meal or a workout is logged (recomputes the streak)
    private var gameKey: Int { logs.reduce(0) { $0 + ($1.workoutDone ? 100_000 : 0) + $1.entriesData.count } }

    private func syncDate() { if date != DayKey.today { date = DayKey.today } }

    /// Draws a single widget
    @ViewBuilder
    private func widget(_ it: TodayLayout.Item, profile: UserProfile, day: DayLog?, hasFast: Bool) -> some View {
        // like iOS widgets: small and wide cards share a height; rich cards (workout, nutrition…) size themselves
        if it.kind.fixedHeight {
            widgetBody(it, profile: profile, day: day, hasFast: hasFast).frame(height: cellHeight)
        } else {
            widgetBody(it, profile: profile, day: day, hasFast: hasFast)
        }
    }

    @ViewBuilder
    private func widgetBody(_ it: TodayLayout.Item, profile: UserProfile, day: DayLog?, hasFast: Bool) -> some View {
        switch it.kind {
        case .workout: workoutCard(profile: profile, day: day)
        case .nutrition: TodayNutritionCard(profile: profile, day: day, latestKg: measures.first?.kg, showEnergy: $showEnergy, showFast: !hasFast)
        case .fasting:
            if profile.fastOn { FastCard(profile: profile) }
            else {
                VStack(alignment: .leading, spacing: 8) {
                    TodayColorCaption("Aralıklı oruç", symbol: "moon.stars.fill", tint: .bPrimary)
                    Text("Kapalı. Yeme aralığını seçince süreyi burada tutarız.").font(.bSm).foregroundStyle(Color.bMutedFg)
                    Button("Aç") { fastSettings = true }.buttonStyle(.b(.outline))
                }
                .frame(maxWidth: .infinity, alignment: .leading).bCard()
            }
        case .water: TodayWaterCard(profile: profile, date: date, ml: day?.waterMl ?? 0)
        case .steps: TodayStepsCard(profile: profile, date: date, logged: day?.steps ?? 0)
        case .week:
            VStack(spacing: 12) {
                TodayWeekCard(profile: profile, logs: logs, programs: programs)
                TodayMuscleWeekCard(profile: profile, logs: logs)
            }
        case .weekWorkouts: TodayWeekWorkoutsCard(profile: profile, logs: logs, programs: programs, wide: it.size == .wide)
        case .deficit: TodayDeficitCard(profile: profile, day: day, latestKg: measures.first?.kg, wide: it.size == .wide)
        case .protein: TodayProteinCard(profile: profile, day: day, wide: it.size == .wide)
        case .weight: TodayWeightCard(profile: profile, kg: measures.first?.kg, wide: it.size == .wide)
        case .year: TodayYearCard()
        case .energy: TodayEnergyBalanceCard(profile: profile, logs: logs, programs: programs, latestKg: measures.first?.kg)
        }
    }

    private func energy(_ p: UserProfile, _ day: DayLog?) -> EnergySummary {
        Energy.summary(profile: p, health: health, day: day, latestMeasureKg: measures.first?.kg, isToday: true)
    }

    // MARK: Today's workout

    @ViewBuilder
    private func workoutCard(profile: UserProfile, day: DayLog?) -> some View {
        // the program comes from the queries already loaded; no two fetches per render
        let prog: WorkoutProgram? = {
            let id: String?
            if let raw = day?.programIdRaw { id = raw.isEmpty ? nil : raw } else { id = Schedule.programId(profile.schedule, date: date) }
            return id.flatMap { id in programs.first { $0.pid == id } }
        }()
        VStack(alignment: .leading, spacing: 16) {
            if let prog, !prog.blocks.allExercises.isEmpty {
                let wp = workoutProgress(prog, day: day)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            TodayIconBadge(symbol: "dumbbell.fill", tint: .bPrimary)
                            Text("Bugünkü antrenman").font(.bXs).foregroundStyle(Color.bMutedFg)
                        }
                        .padding(.bottom, 4)
                        Text(prog.name).font(.bDisplay(24, relativeTo: .title2)).tracking(-0.4).foregroundStyle(Color.bFg)   // TE-06
                        Text("\(prog.blocks.allExercises.count) hareket · \(wp.done)/\(wp.total) set").font(.bSm).foregroundStyle(Color.bMutedFg).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if wp.complete {
                        BBadge(variant: .success) { Ti("circle-check-filled", size: 12); Text("Tamamlandı") }
                    }
                }
                BProgress(value: wp.complete ? 1 : wp.pct, tint: wp.complete ? .bSuccess : .bPrimary, label: "Antrenman ilerlemesi")
                // side by side (Duo inner screen) the buttons align with the nutrition card's: pinned to the bottom
                VStack(spacing: 0) {
                Spacer(minLength: 0)
                if wp.complete {
                    // done: a summary instead of the continue button
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Color.bSuccess)
                            .symbolEffect(.bounce, value: wp.complete)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bugünkü antrenman tamam").font(.geist(15, .semibold)).foregroundStyle(Color.bFg)
                            Text(completedLine(day)).font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        listToggle
                    }
                } else {
                    HStack(spacing: 8) {
                        Button { haptic(); app.openSession(.init(pid: prog.pid, date: date)) } label: {
                            BLabel(app.session?.date == date ? "Antrenmana dön" : wp.done > 0 ? "Devam et" : "Başlat").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.b(.primary, .large, full: true))
                        listToggle
                    }
                }
                }
                // exercise list: the card grows downward from the button
                if showList {
                    VStack(spacing: 0) {
                        ForEach(Array(prog.blocks.allExercises.enumerated()), id: \.element.id) { i, e in
                            let done = exDoneCount(e, day: day) >= e.sets
                            HStack(spacing: 12) {
                                MotionThumb(name: e.name, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1)
                                        .foregroundStyle(done ? Color.bMutedFg : Color.bFg).strikethrough(done, color: Color.bMutedFg)
                                    Text(Wk.meta(e)).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.bSuccess) }
                            }
                            .padding(.vertical, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            if i < prog.blocks.allExercises.count - 1 { Rectangle().fill(Color.bBorder).frame(height: 1) }
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
                }
            } else if !programs.contains(where: { !$0.archived }) {
                // no program at all: not a rest day, but getting started
                BEmpty(symbol: "dumbbell", title: "Henüz programın yok",
                       text: "Hazır bir programla başla ya da kendininkini kur; günün antrenmanı burada çıkar.",
                       action: "Program seç", framed: false) {
                    app.setTab(.workout)
                    if app.workoutPath.last != .programs { app.workoutPath.append(.programs) }
                }
            } else {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).fill(Color.bMuted).frame(width: 40, height: 40)
                        .overlay(Ti("moon", size: 20).foregroundStyle(Color.bFg))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dinlenme günü").font(.geist(16, .medium)).foregroundStyle(Color.bFg)
                        Text("Program atanmadı.").font(.bSm).foregroundStyle(Color.bMutedFg)
                    }
                    Spacer(minLength: 0)
                    Button("Program seç") { app.setTab(.workout) }.buttonStyle(.b(.outline))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)   // equal height when side by side
        .bCard()
    }

    /// List button (icon): tap to grow the card, tap again to shrink
    private var listToggle: some View {
        Button {
            haptic()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showList.toggle() }
        } label: {
            Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                .rotationEffect(.degrees(showList ? 180 : 0))
        }
        .buttonStyle(.b(.outline, .iconLarge))
        .accessibilityLabel(showList ? "Hareket listesini kapat" : "Hareket listesini aç")
    }

    private func completedLine(_ day: DayLog?) -> String {
        var parts: [String] = []
        if let sec = day?.workoutSeconds, sec > 0 { parts.append(String(localized: "\(sec / 60) dk")) }
        if let k = day?.workoutKcal, k > 0 { parts.append(String(localized: "\(fmt0(k)) kcal")) }
        return parts.isEmpty ? String(localized: "Tebrikler, harika iş.") : parts.joined(separator: " · ")
    }

}


// MARK: - Nutrition card
/// Separate view: Health data (steps, active calories) refreshes only this card and the week card,
/// not all of Today
private struct TodayNutritionCard: View {
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    let profile: UserProfile
    let day: DayLog?
    let latestKg: Double?
    @Binding var showEnergy: Bool
    /// Not shown again here if fasting was added as its own widget
    var showFast = true
    @State private var showFood = false

    var body: some View {
        let e = Energy.summary(profile: profile, health: health, day: day, latestMeasureKg: latestKg, isToday: true)
        let eat = day?.eaten ?? .zero
        let left = e.target - eat.kcal
        let plan = Macros(kcal: e.target, p: profile.proteinG, c: profile.carbsG, f: profile.fatG)
        // white version of the Nutrition summary (Figma "Nutrition day"): left, eaten · goal, bar, macros
        return VStack(alignment: .leading, spacing: 16) {
            Button { showEnergy = true } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(left >= 0 ? "Kalan" : "Hedefin üstünde").font(.bSm).foregroundStyle(Color.bMutedFg)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(left < 0 ? "+" + fmt0(-left) : fmt0(left)).font(.bNum(40, relativeTo: .largeTitle))
                                    .foregroundStyle(left < 0 ? Color.bDestructive : Color.bFg).contentTransition(.numericText(value: left))
                                Text("kcal").font(.bSm).foregroundStyle(Color.bMutedFg)
                            }
                            .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(localized: "\(fmt0(eat.kcal)) yendi")).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                            Text("hedef \(fmt0(e.target))").font(.bXs).foregroundStyle(Color.bMutedFg)
                        }
                        .monospacedDigit().padding(.bottom, 6)
                    }
                    TodayBar(value: eat.kcal / max(1, e.target), tint: left < 0 ? .bDestructive : .bFg)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.press)
            .accessibilityHint("Kalori hesabının ayrıntıları")
            HStack(alignment: .top, spacing: 14) {
                TodayMacroBar(label: "Protein", value: eat.p, goal: plan.p, tint: .bProtein)
                TodayMacroBar(label: "Karbonhidrat", value: eat.c, goal: plan.c, tint: .bCarb)
                TodayMacroBar(label: "Yağ", value: eat.f, goal: plan.f, tint: .bFat)
            }
            VStack(spacing: 0) {
            Spacer(minLength: 0)   // side by side, buttons align with the workout card
            HStack(spacing: 8) {
                Button { app.open(.addFood(date: DayKey.today, meal: nil)) } label: { BLabel("Yediğini ekle").frame(maxWidth: .infinity) }
                    .buttonStyle(.b(.primary, .large, full: true))
                    .popoverTip(TipAddFood())
                Button {
                    haptic()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { showFood.toggle() }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                        .rotationEffect(.degrees(showFood ? 180 : 0))
                }
                .buttonStyle(.b(.outline, .iconLarge))
                .accessibilityLabel(showFood ? "Bugün yediklerini gizle" : "Bugün yediklerini göster")
            }
            }
            // what you ate today: by meal, expands downward
            if showFood {
                foodList(day?.entries ?? [], meals: profile.meals)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
            }
            // intermittent fasting (when on in Profile) in the same card
            if profile.fastOn && showFast {
                Rectangle().fill(Color.bBorder).frame(height: 1)
                FastCard(profile: profile, embedded: true, actions: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)   // equal height when side by side
        .bCard()
    }

    @ViewBuilder
    private func foodList(_ entries: [FoodEntry], meals: [Meal]) -> some View {
        if entries.isEmpty {
            Text("Bugün henüz bir şey eklemedin.").font(.bSm).foregroundStyle(Color.bMutedFg)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            let order = meals + Meal.allCases.filter { !meals.contains($0) }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(order, id: \.self) { m in
                    let items = entries.filter { $0.meal == m }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(tl(m.label)).font(.geist(13, .semibold, relativeTo: .footnote)).foregroundStyle(Color.bFg)
                                Spacer()
                                Text("\(fmt0(items.reduce(0) { $0 + $1.macros.kcal })) kcal").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                            }
                            ForEach(items) { e in
                                HStack(spacing: 10) {
                                    NutThumb(size: 32, name: e.foodName.isEmpty ? e.name : e.foodName)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.name).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg).lineLimit(1)
                                        Text("\(fmt0(e.g)) g").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                                    }
                                    Spacer(minLength: 0)
                                    (Text(fmt0(e.macros.kcal)).font(.bSm) + Text(" kcal").font(.bXs).foregroundStyle(Color.bMutedFg))
                                        .monospacedDigit().foregroundStyle(Color.bFg)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}

// MARK: - This week card
private struct TodayWeekCard: View {
    @Environment(HealthService.self) private var health
    let profile: UserProfile
    let logs: [DayLog]
    let programs: [WorkoutProgram]

    var body: some View {
        let today = DayKey.today
        // the week always starts on Monday; future days are empty rings
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let keys = (0..<7).map { DayKey.shift(monday, days: $0) }
        let dict = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let progs = Dictionary(programs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let schedule = profile.schedule
        var planned = 0, done = 0
        var wkFrac: [String: Double] = [:]
        for k in keys {
            let raw = dict[k]?.programIdRaw
            let id: String? = raw != nil ? (raw!.isEmpty ? nil : raw) : Schedule.programId(schedule, date: k)
            guard let id, let prog = progs[id], !prog.blocks.allExercises.isEmpty else { continue }
            planned += 1
            let wp = workoutProgress(prog, day: dict[k])
            if wp.complete { done += 1 }
            wkFrac[k] = wp.complete ? 1 : wp.pct
        }
        let past = keys.filter { $0 <= today }
        let eatenDays = past.compactMap { dict[$0] }.filter { !$0.entries.isEmpty }
        let avgP = eatenDays.isEmpty ? 0 : eatenDays.reduce(0) { $0 + $1.eaten.p } / Double(eatenDays.count)
        let kcals = keys.map { dict[$0]?.eaten.kcal ?? 0 }
        // average steps: elapsed days of this week (Health for today if larger)
        let stepVals = keys.map { k -> Int in
            guard k <= today else { return 0 }
            let logged = dict[k]?.steps ?? 0
            return max(logged, k == today ? health.stepsToday : (health.weekSteps[k] ?? 0))
        }
        let stepDays = stepVals.filter { $0 > 0 }
        let avgSteps = stepDays.isEmpty ? 0 : Double(stepDays.reduce(0, +)) / Double(stepDays.count)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                TodayIconBadge(symbol: "calendar", tint: .bPrimary)
                Text("Bu hafta").font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            // 7 days like Apple Activity rings: outer steps, middle workout, inner protein
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                    let isToday = k == today
                    VStack(spacing: 6) {
                        DayRings(steps: Double(stepVals[i]) / Double(max(1, profile.stepGoal)),
                                 workout: wkFrac[k],
                                 protein: profile.proteinG > 0 ? (dict[k]?.eaten.p ?? 0) / profile.proteinG : 0)
                        Text(String(DayKey.dayShort[DayKey.weekday(k)].prefix(1))).font(.geist(11, isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Color.bFg : Color.bMutedFg)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(DayKey.dayLong[DayKey.weekday(k)]): \(stepVals[i]) adım, \(fmt0(dict[k]?.eaten.p ?? 0)) g protein\(wkFrac[k] == 1 ? tl(", antrenman tamam") : "")")
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: kcals)
            // legend below the chart, same order as the rings: outer steps · middle workout · inner protein
            HStack(alignment: .top, spacing: 16) {
                weekRing("Ort. adım", fmt0(avgSteps), " / \(fmt0(Double(profile.stepGoal)))",
                         progress: profile.stepGoal > 0 ? avgSteps / Double(profile.stepGoal) : 0, tint: .bRingSteps)
                weekRing("Antrenman", "\(done)", planned > 0 ? " / \(planned)" : " / –",
                         progress: planned > 0 ? Double(done) / Double(planned) : 0, tint: .bRingWorkout)
                weekRing("Ort. protein", fmt0(avgP), " / \(fmt0(profile.proteinG)) g",
                         progress: profile.proteinG > 0 ? avgP / profile.proteinG : 0, tint: .bRingProtein)
            }
        }
        .bCard()
    }

    /// Macro row style: small ring + label, big value + small goal
    private func weekRing(_ title: String, _ value: String, _ suffix: String, progress: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) { MacroMiniRing(value: progress, tint: tint); Text(tl(title)).lineLimit(1).minimumScaleFactor(0.8) }
                .font(.bXs).foregroundStyle(Color.bMutedFg)
            TodayValue(value: value, suffix: suffix, size: 16).padding(.top, 4).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Thin progress bar (Today nutrition card)
struct TodayBar: View {
    let value: Double
    var tint: Color = .bFg
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.bFg.opacity(0.08))
                if value > 0 { Capsule().fill(tint).frame(width: max(6, g.size.width * min(1, value))) }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Macro column: value / goal, bar, label (as in the Nutrition summary)
struct TodayMacroBar: View {
    let label: String; let value: Double; let goal: Double; let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(fmt0(value)).font(.bNum(18, relativeTo: .headline)).foregroundColor(Color.bFg)
             + Text(" /\(fmt0(goal)) g").font(.bXs).foregroundColor(Color.bMutedFg))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            TodayBar(value: goal > 0 ? value / goal : 0, tint: tint, height: 5)
            Text(tl(label)).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(tl(label)) \(fmt0(value)) / \(fmt0(goal)) g"))
    }
}

// MARK: - Macro row

struct TodayMacroRow: View {
    let eat: Macros; let plan: Macros
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            item("Protein", eat.p, plan.p, .bProtein)
            item("Karb.", eat.c, plan.c, .bCarb)
            item("Yağ", eat.f, plan.f, .bFat)
        }
    }
    private func item(_ l: String, _ v: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) { MacroMiniRing(value: goal > 0 ? v / goal : 0, tint: tint); Text(tl(l)).lineLimit(1).minimumScaleFactor(0.7) }.font(.bXs).foregroundStyle(Color.bMutedFg)
            TodayValue(value: fmt0(v), suffix: " / \(fmt0(goal)) g", size: 16).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Su

private struct TodayWaterCard: View {
    @Environment(\.modelContext) private var ctx
    let profile: UserProfile
    let date: String
    let ml: Int
    var body: some View {
        let step = max(50, profile.waterStepMl)
        VStack(alignment: .leading, spacing: 0) {
            TodayColorCaption("Su", symbol: "drop.fill", tint: .bPrimary)
            TodayValue(value: fmt1(Double(ml) / 1000), suffix: " / \(fmt1(Double(profile.waterMl) / 1000)) L").padding(.top, 4)
            BProgress(value: profile.waterMl > 0 ? Double(ml) / Double(profile.waterMl) : 0, label: "Su hedefi").padding(.top, 8)
            HStack(spacing: 8) {
                Button { change(-step) } label: { Ti("minus").frame(maxWidth: .infinity) }
                    .buttonStyle(.b(.outline, .regular, full: true)).disabled(ml <= 0).accessibilityLabel("\(step) ml çıkar")
                Button { haptic(); change(step) } label: { Ti("plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.b(.outline, .regular, full: true)).accessibilityLabel("\(step) ml ekle")
            }
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bCard()
        .animation(.easeOut(duration: 0.3), value: ml)
        .bPop(ml)
    }
    /// The date is taken at tap time: a screen left open past midnight doesn't write to yesterday
    private func change(_ d: Int) {
        guard let day = Store.day(ctx, DayKey.today) else { return }
        day.waterMl = min(20_000, max(0, day.waterMl + d))   // upper bound
        Store.save(ctx)
    }
}

// MARK: - Steps (edited in place on tap)

private struct TodayStepsCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    let profile: UserProfile
    let date: String
    let logged: Int
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focus: Bool

    private func parse(_ s: String) -> Int { min(200_000, Int(s.filter(\.isNumber)) ?? 0) }

    var body: some View {
        let fromHealth = health.stepsToday > 0
        let steps = fromHealth ? max(health.stepsToday, logged) : logged
        let goal = max(1, profile.stepGoal)
        Group {
            if editing {
                VStack(alignment: .leading, spacing: 0) {
                    TodayColorCaption("Adım", symbol: "figure.walk", tint: .bPrimary)
                    TextField("0", text: $text)
                        .keyboardType(.numberPad).focused($focus).submitLabel(.done)
                        .font(.bNum(20))
                        .frame(height: 32)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.bPrimary).frame(height: 2) }
                        .padding(.top, 2)
                        .onChange(of: text) { _, v in let f = String(v.filter(\.isNumber).prefix(6)); if f != v { text = f } }
                        .onSubmit(save)
                        .accessibilityLabel("Bugünkü adım")
                    Text("Hedef \(fmt0(Double(profile.stepGoal))) · bitince Bitti'ye dokun").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 6)
                    Spacer(minLength: 12)
                    BProgress(value: Double(parse(text)) / Double(goal), label: "Adım hedefi")
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Bitti", action: save).font(.geist(16, .semibold)) }
                }
                .onChange(of: focus) { _, f in if !f { save() } }
            } else {
                Button(action: start) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            TodayColorCaption("Adım", symbol: "figure.walk", tint: .bPrimary)
                            Spacer()
                            if !fromHealth { Ti("pencil", size: 14).foregroundStyle(Color.bMutedFg).opacity(0.7) }
                        }
                        TodayValue(value: fmt0(Double(steps)), suffix: " / \(fmt0(Double(profile.stepGoal)))").padding(.top, 4)
                        // the pencil icon is enough; the empty state keeps its hint
                        if fromHealth || logged == 0 {
                            Text(fromHealth ? "Apple Sağlık'tan" : "Girmek için dokun")
                                .font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 6)
                        }
                        Spacer(minLength: 12)
                        // chart at the bottom of the card, aligned with the Water card's buttons
                        BProgress(value: Double(steps) / Double(goal), label: "Adım hedefi")
                            .padding(.bottom, 19)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .buttonStyle(.press)
                .disabled(fromHealth)
                .accessibilityLabel(fromHealth ? "Adım \(steps), Sağlık'tan" : "Adım sayısını gir")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .bCard()
        .onChange(of: date) { _, _ in editing = false }
    }

    private func start() { text = logged > 0 ? String(logged) : ""; editing = true; focus = true }
    private func save() {
        guard editing else { return }
        let v = parse(text)
        if v != logged, let d = Store.day(ctx, DayKey.today) { d.steps = v; Store.save(ctx) }
        editing = false; focus = false
    }
}

// MARK: - Calorie detail

private struct TodayEnergySheet: View {
    let e: EnergySummary
    var body: some View {
        BSheet(title: "Kalori", description: "Günlük ihtiyacın ve hedefin nasıl hesaplanıyor") {
            VStack(spacing: 0) {
                if let bmr = e.bmr { row("Bazal metabolizma", bmr) }
                if let n = e.need { row("Günlük ihtiyaç", n) }
                row("Hedef", e.target, bold: true)
                row("Yenen", e.eaten)
            }
            .bCard(padding: 0)
            if !e.missing.isEmpty {
                Text("Hesap için eksik: \(e.missing.joined(separator: ", ")). Profil › Vücut ve kalori'den girebilirsin.").font(.bSm).foregroundStyle(Color.bFg)
            }
            Text("Bazal metabolizma Mifflin-St Jeor formülüyle (kilo, boy, yaş, cinsiyet) hesaplanır. Günlük ihtiyaç = bazal × aktivite seviyesi; adım, antrenman ve aktif kalori hedefe eklenmez. Hedef, haftalık kilo verme hızına göre ihtiyaçtan düşülür ve bazal metabolizmanın altına inmez.")
                .font(.bXs).foregroundStyle(Color.bMutedFg)
        }
        .presentationDetents([.medium, .large])
    }
    private func row(_ l: String, _ v: Double, bold: Bool = false) -> some View {
        HStack {
            Text(tl(l)).font(.bSm).foregroundStyle(Color.bMutedFg)
            Spacer()
            Text("\(fmt0(v)) kcal").font(.geist(14, bold ? .semibold : .medium)).monospacedDigit().foregroundStyle(Color.bFg)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 16) }
    }
}

// MARK: - Renkli ikon rozeti

extension Color {
    static let todayBlue = Color(red: 0.0, green: 0.6, blue: 1.0)
    static let todayGreen = Color(red: 0.2, green: 0.75, blue: 0.35)
}

/// SF icon inside a 24 pt rounded colored badge
struct TodayIconBadge: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Card caption with badge (Water, Steps, fasting); badges share the neutral color of the workout/nutrition cards
struct TodayColorCaption: View {
    let title: String; let symbol: String; let tint: Color
    init(_ title: String, symbol: String, tint: Color) { self.title = title; self.symbol = symbol; self.tint = tint }
    var body: some View {
        HStack(spacing: 8) {
            TodayIconBadge(symbol: symbol, tint: tint)
            Text(tl(title)).font(.bXs).foregroundStyle(Color.bMutedFg)
        }
    }
}


// MARK: - Intermittent fasting

/// Fixed-schedule fasting: elapsed/remaining while fasting, the eating window otherwise; dots for the last 7 days
struct FastCard: View {
    @Environment(\.modelContext) private var ctx
    let profile: UserProfile
    /// Inside another card (nutrition summary): no card or action button of its own
    var embedded = false
    /// Show the end/skip button even when embedded (Today)
    var actions = false
    @State private var settings = false

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 30)) { t in
            if embedded { content(profile.fast, now: t.date) } else { content(profile.fast, now: t.date).bCard() }
        }
        .sheet(isPresented: $settings) { FastSettingsSheet(profile: profile) }
        .onChange(of: profile.fastData) { _, _ in LiveFast.sync(profile) }
    }

    @ViewBuilder private func content(_ f: FastPlan, now: Date) -> some View {
        let ph = f.phase(at: now)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                switch ph {
                case .fasting: TodayColorCaption("Oruçtasın", symbol: "moon.stars.fill", tint: .bPrimary)
                case .eating: TodayColorCaption("Yeme aralığı", symbol: "fork.knife", tint: .bPrimary)
                }
                Spacer()
                Button { settings = true } label: {
                    Text("\(f.endText) – \(f.startText)").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Color.bFg.opacity(0.06), in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())   // 28 pt visible, 44 pt touch
                }
                .accessibilityLabel("Oruç saatlerini değiştir")
            }
            // time left + the day's timeline: green segment is the eating window, the line is now
            VStack(alignment: .leading, spacing: 4) {
                switch ph {
                case let .fasting(start, end, _):
                    Self.durText(end.timeIntervalSince(now))
                    Text("Oruç \(Self.hm(end))'da bitiyor").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                    // stage track: lime bar, ink text; the current stage is darker
                    FastStageTrack(start: start, end: end, tint: .bAction, ink: .bFg, muted: .bMutedFg, now: now)
                        .padding(.top, 10)
                case let .eating(_, next, _):
                    Self.durText(next.timeIntervalSince(now))
                    Text("Yeme aralığı \(Self.hm(next))'a kadar açık").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                }
            }
            .padding(.top, 10)
            if !embedded || actions {
            switch ph {
            case let .fasting(_, _, key):
                // the fast ends and the eating window opens now; today's fasting time shifts accordingly
                Button { update { $0.endEarly(key) } } label: { BLabel("Orucu şimdi bitir") }
                    .buttonStyle(.b(.outline, .regular, full: true)).padding(.top, 12)
            case .eating: EmptyView()
            }
            }
        }
    }

    private func update(_ f: (inout FastPlan) -> Void) {
        haptic()
        var p = profile.fast; f(&p); profile.fast = p
        Store.save(ctx)
    }

    static func hm(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
    /// "3 h 6 min left": big italic numbers, small units, tight spacing
    static func durText(_ s: TimeInterval) -> some View {
        let m = max(0, Int(s / 60)), h = m / 60, mm = m % 60
        let unit: (String) -> Text = { Text(tl($0)).font(.geist(14, .semibold, relativeTo: .subheadline)).foregroundColor(Color.bMutedFg) }
        var t = Text("")
        if h > 0 { t = t + Text("\(h)").font(.bNum(26)) + unit("sa") }
        if h == 0 || mm > 0 { t = t + Text(h > 0 ? " " : "") + Text("\(mm)").font(.bNum(26)) + unit("dk") }
        return (t + unit(" kaldı")).foregroundStyle(Color.bFg).lineLimit(1).minimumScaleFactor(0.7)
    }
    static func dur(_ s: TimeInterval) -> String {
        let m = max(0, Int(s / 60)); return m >= 60 ? (m % 60 == 0 ? String(localized: "\(m / 60) sa") : String(localized: "\(m / 60) sa \(m % 60) dk")) : String(localized: "\(m) dk")
    }
}

/// Intermittent fasting settings (from Profile and Nutrition): on/off, start and end time, quick picks
struct FastSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let profile: UserProfile
    @State private var on = false
    @State private var start = 20 * 60
    @State private var end = 12 * 60
    @State private var loaded = false

    private var plan: FastPlan { FastPlan(startMin: start, endMin: end) }

    var body: some View {
        BSheet(title: "Aralıklı oruç", description: "Her gün hangi saatte yemeye başlayıp hangi saatte bırakacağını seç; arada kalan süre oruç. Süreyi senin yerine tutarız.") {
            Toggle(isOn: $on.animation(.snappy)) { Text("Aralıklı oruç").font(.geist(16, .medium)) }.tint(.green)
            if on {
                VStack(spacing: 0) {
                    // as an eating window: start eating (fast ends) → stop eating (fast starts)
                    timeRow("Yemeye başla", $end)
                    Rectangle().fill(Color.bBorder).frame(height: 1)
                    timeRow("Yemeyi bırak", $start)
                }
                .bCard(padding: 0)
                Text("\(FastSettingsSheet.dur(plan.eatingMin)) yeme aralığı · \(FastSettingsSheet.dur(plan.durMin)) oruç")
                    .font(.bSm).foregroundStyle(Color.bMutedFg)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hızlı seçim").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
                    HStack(spacing: 8) {
                        ForEach(FastPlan.presets, id: \.hours) { p in
                            let sel = plan.durMin == p.hours * 60
                            Button { haptic(); start = (end + (24 - p.hours) * 60) % 1440 } label: {
                                Text(p.label).font(.bNum(15))
                                    .foregroundStyle(sel ? Color.bBg : Color.bFg)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(sel ? Color.bFg : Color.bCard, in: Capsule())
                                    .overlay { if !sel { Capsule().strokeBorder(Color.bBorder) } }
                            }
                            .buttonStyle(.press)
                            .accessibilityAddTraits(sel ? [.isSelected] : [])
                        }
                    }
                }
            }
        } footer: {
            Button("Kaydet", action: save).buttonStyle(.b(.primary, .large, full: true))
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            on = profile.fastOn
            start = profile.fast.startMin; end = profile.fast.endMin
        }
    }

    private func timeRow(_ title: String, _ m: Binding<Int>) -> some View {
        HStack {
            Text(tl(title)).font(.geist(16, .medium))
            Spacer()
            DatePicker(tl(title), selection: Binding(
                get: { DayKey.calendar.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                set: { let c = DayKey.calendar.dateComponents([.hour, .minute], from: $0); m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden().environment(\.locale, .current)
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
    }

    static func dur(_ m: Int) -> String { m % 60 == 0 ? String(localized: "\(m / 60) saat") : String(localized: "\(m / 60) sa \(m % 60) dk") }

    private func save() {
        var f = profile.fast
        let p = plan
        f.startMin = p.startMin; f.durMin = p.durMin
        profile.fast = f
        profile.fastOn = on
        Store.save(ctx)
        LiveFast.sync(profile)
        Notifier.reschedule(ctx)
        dismiss()
    }
}


/// Daily triple ring (like Activity rings): outer steps red · middle workout green · inner protein teal.
/// A ring continues into a second lap once the goal is exceeded (BRings).
struct DayRings: View {
    var steps: Double
    var workout: Double?
    var protein: Double
    var size: CGFloat = 38
    var body: some View {
        BRings(rings: [(steps, .bRingSteps), (workout ?? 0, .bRingWorkout), (protein, .bRingProtein)], size: size, stroke: 4, gap: 1.5) { EmptyView() }
    }
}


// MARK: - Today layout

/// Widgets that can be added to Today
enum TodayWidget: String, Codable, CaseIterable, Identifiable {
    case workout, nutrition, energy, fasting, water, steps, week, weekWorkouts, deficit, protein, weight, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .workout: "Bugünkü antrenman"
        case .nutrition: "Beslenme"
        case .energy: "Enerji dengesi"
        case .fasting: "Aralıklı oruç"
        case .water: "Su"
        case .steps: "Adım"
        case .week: "Bu hafta"
        case .weekWorkouts: "Haftalık antrenman"
        case .deficit: "Kalori açığı"
        case .protein: "Protein"
        case .weight: "Kilo"
        case .year: "Son 365 gün"
        }
    }
    var subtitle: String {
        switch self {
        case .workout: "Günün programı, başlat ve ilerleme"
        case .nutrition: "Kalan kalori, makrolar, yediklerin"
        case .energy: "Bazal, hareket, antrenman, yenen; gün · hafta · ay"
        case .fasting: "Oruç ve yeme aralığı sayacı"
        case .water: "Su hedefi, tek dokunuşla ekle"
        case .steps: "Bugünkü adım ve hedef"
        case .week: "Son 7 günün halkaları"
        case .weekWorkouts: "Bu hafta yapılan / planlanan"
        case .deficit: "Yakılan − yenen, şu ana kadar"
        case .protein: "Bugün alınan protein ve hedef"
        case .weight: "Güncel kilo ve sıradaki hedef"
        case .year: "Spor günleri ve adım kademeleri, nokta nokta"
        }
    }
    var symbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .nutrition: "fork.knife"
        case .energy: "chart.bar.xaxis"
        case .fasting: "moon.stars.fill"
        case .water: "drop.fill"
        case .steps: "figure.walk"
        case .week: "calendar"
        case .weekWorkouts: "checkmark.circle.fill"
        case .deficit: "flame.fill"
        case .protein: "bolt.heart.fill"
        case .weight: "scalemass.fill"
        case .year: "square.grid.3x3.fill"
        }
    }
    var tint: Color {
        switch self {
        case .workout: .fitBlue
        case .nutrition: .orange
        case .energy: .fitKcal
        case .fasting: .fitPurple
        case .water: .bSky
        case .steps: .fitGreen
        case .week: .bPrimary
        case .weekWorkouts: .fitBlue
        case .deficit: .fitKcal
        case .protein: .bProtein
        case .weight: .fitTime
        case .year: .fitGreen
        }
    }
    /// Small/wide widgets have a fixed, equal height
    var fixedHeight: Bool { sizes.contains(.small) }
    /// Supported sizes; the first is the default
    var sizes: [TodayWidgetSize] {
        switch self {
        case .workout, .nutrition, .energy, .fasting, .week, .year: [.wide]
        default: [.small, .wide]
        }
    }
}

enum TodayWidgetSize: String, Codable { case small, wide }

enum TodayLayout {
    struct Item: Codable, Hashable, Identifiable {
        var kind: TodayWidget
        var size: TodayWidgetSize
        var id: TodayWidget { kind }
    }
    struct Row: Identifiable { var items: [Item]; var id: String { items.map(\.kind.rawValue).joined(separator: "+") } }

    /// First launch: same as the old fixed Today
    static let defaults: [Item] = [
        .init(kind: .workout, size: .wide), .init(kind: .nutrition, size: .wide),
        .init(kind: .water, size: .small), .init(kind: .steps, size: .small),
        .init(kind: .week, size: .wide),
    ]

    /// Unknown (future version) widgets and duplicates are skipped; unsupported sizes fall back to the default
    static func decode(_ raw: String) -> [Item] {
        guard !raw.isEmpty, let arr = try? JSONDecoder().decode([[String: String]].self, from: Data(raw.utf8)) else { return defaults }
        var seen = Set<TodayWidget>(), out: [Item] = []
        for d in arr {
            guard let k = d["kind"].flatMap(TodayWidget.init(rawValue:)), !seen.contains(k) else { continue }
            let s = d["size"].flatMap(TodayWidgetSize.init(rawValue:)).flatMap { k.sizes.contains($0) ? $0 : nil } ?? k.sizes[0]
            seen.insert(k); out.append(Item(kind: k, size: s))
        }
        return out
    }
    static func encode(_ items: [Item]) -> String {
        let arr = items.map { ["kind": $0.kind.rawValue, "size": $0.size.rawValue] }
        return (try? JSONEncoder().encode(arr)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Splits into rows: two consecutive small side by side; two consecutive wide in a BPair (side by side on wide screens)
    static func rows(_ items: [Item]) -> [Row] {
        var rows: [Row] = [], pending: Item?
        var i = 0
        while i < items.count {
            let it = items[i]
            if it.size == .small {
                if let p = pending { rows.append(Row(items: [p, it])); pending = nil } else { pending = it }
                i += 1
            } else {
                if let p = pending { rows.append(Row(items: [p])); pending = nil }
                if i + 1 < items.count, items[i + 1].size == .wide, (it.kind == .workout && items[i + 1].kind == .nutrition) {
                    rows.append(Row(items: [it, items[i + 1]])); i += 2
                } else { rows.append(Row(items: [it])); i += 1 }
            }
        }
        if let p = pending { rows.append(Row(items: [p])) }
        return rows
    }
}

private struct TodayWeekWorkoutsCard: View {
    let profile: UserProfile
    let logs: [DayLog]
    let programs: [WorkoutProgram]
    var wide = false
    var body: some View {
        let today = DayKey.today
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let keys = (0..<7).map { DayKey.shift(monday, days: $0) }
        let dict = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let progs = Dictionary(programs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let states: [Int] = keys.map { k in   // 0 rest · 1 planned · 2 done
            let raw = dict[k]?.programIdRaw
            let id: String? = raw != nil ? (raw!.isEmpty ? nil : raw) : Schedule.programId(profile.schedule, date: k)
            guard let id, let p = progs[id], !p.blocks.allExercises.isEmpty else { return 0 }
            return workoutProgress(p, day: dict[k]).complete ? 2 : 1
        }
        let planned = states.filter { $0 > 0 }.count, done = states.filter { $0 == 2 }.count
        VStack(alignment: .leading, spacing: 0) {
            TodayColorCaption("Bu hafta", symbol: "checkmark.circle.fill", tint: .bPrimary)
            TodayValue(value: "\(done)", suffix: planned > 0 ? String(localized: " / \(planned) antrenman") : String(localized: " antrenman")).padding(.top, 4)
            Spacer(minLength: 12)
            HStack(spacing: wide ? 10 : 5) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(states[i] == 2 ? Color.bSuccess : Color.clear)
                            .overlay(Circle().strokeBorder(states[i] == 1 ? Color.bFg.opacity(0.5) : (states[i] == 0 ? Color.bFg.opacity(0.12) : .clear), lineWidth: 2))
                            .overlay { if k == today { Circle().strokeBorder(Color.bFg, lineWidth: 1).padding(-3) } }
                            .frame(width: wide ? 18 : 14, height: wide ? 18 : 14)
                        if wide { Text(String(DayKey.dayShort[DayKey.weekday(k)].prefix(1))).font(.geist(10)).foregroundStyle(Color.bMutedFg) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bu hafta \(done) antrenman yapıldı, \(planned) planlı")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bCard()
    }
}

/// Calorie deficit: basal (accrues over the day) + active − eaten (same math as the watch complication)
private struct TodayDeficitCard: View {
    @Environment(HealthService.self) private var health
    let profile: UserProfile
    let day: DayLog?
    let latestKg: Double?
    var wide = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { t in
            let e = Energy.summary(profile: profile, health: health, day: day, latestMeasureKg: latestKg, isToday: true)
            VStack(alignment: .leading, spacing: 0) {
                TodayColorCaption("Kalori açığı", symbol: "flame.fill", tint: .bPrimary)
                if let bmr = e.bmr {
                    let start = DayKey.calendar.startOfDay(for: t.date)
                    let frac = min(1, max(0, t.date.timeIntervalSince(start) / 86_400))
                    let burned = bmr * frac + e.activeKcal
                    let d = burned - e.eaten
                    let planned = max(0, (e.need ?? 0) - e.target)
                    TodayValue(value: fmt0(abs(d)), suffix: d >= 0 ? String(localized: " kcal açık") : String(localized: " kcal fazla")).padding(.top, 4)
                    Text("Yakılan \(fmt0(burned)) · yenen \(fmt0(e.eaten))").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 6)
                    Spacer(minLength: 12)
                    if planned > 0 {
                        BProgress(value: max(0, d) / planned, tint: d >= 0 ? .bSuccess : .bDestructive, label: "Günlük açık hedefi")
                        if wide { Text("Günlük hedef açık \(fmt0(planned)) kcal").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 6) }
                    }
                } else {
                    Text("Hesap için Profil'de \(e.missing.joined(separator: ", ")) eksik.").font(.bSm).foregroundStyle(Color.bMutedFg).padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .bCard()
        }
    }
}

/// Protein eaten today and the goal
private struct TodayProteinCard: View {
    let profile: UserProfile
    let day: DayLog?
    var wide = false
    var body: some View {
        let p = day?.eaten.p ?? 0, goal = max(1, profile.proteinG)
        VStack(alignment: .leading, spacing: 0) {
            TodayColorCaption("Protein", symbol: "bolt.heart.fill", tint: .bPrimary)
            TodayValue(value: fmt0(p), suffix: " / \(fmt0(goal)) g").padding(.top, 4)
            Text(p >= goal ? "Hedef tamam" : "\(fmt0(goal - p)) g kaldı").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 6)
            Spacer(minLength: 12)
            BProgress(value: p / goal, tint: .bProtein, label: "Protein hedefi")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bCard()
    }
}

/// Current weight, change since the start and the next goal
private struct TodayWeightCard: View {
    let profile: UserProfile
    let kg: Double?
    var wide = false
    var body: some View {
        let goals = profile.goals.sorted(by: >)
        let next = kg.flatMap { c in goals.first { c > $0 } }
        VStack(alignment: .leading, spacing: 0) {
            TodayColorCaption("Kilo", symbol: "scalemass.fill", tint: .bPrimary)
            TodayValue(value: kg.map(fmt1) ?? "–", suffix: " kg").padding(.top, 4)
            if let c = kg, let s = profile.startKg, s != c {
                Text("\(c < s ? "↓" : "↑") \(fmt1(abs(s - c))) kg · başlangıç \(fmt1(s))").font(.bXs)
                    .foregroundStyle(c < s ? Color.bSuccess : Color.bMutedFg).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).padding(.top, 6)
            }
            Spacer(minLength: 12)
            if let c = kg, let n = next {
                let prev = goals.last { $0 > n } ?? profile.startKg ?? c
                BProgress(value: prev > n ? (prev - c) / (prev - n) : 0, label: "Sıradaki kilo hedefi")
                Text("\(fmt1(n)) kg hedefe \(fmt1(c - n)) kg").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().padding(.top, 6)
            } else if kg == nil {
                Text("Ölçümlerim'den kilo ekle").font(.bXs).foregroundStyle(Color.bMutedFg)
            } else if !goals.isEmpty {
                Text("Hedeflerin tamam").font(.bXs).foregroundStyle(Color.bSuccess)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .bCard()
    }
}


// MARK: - Energy balance

private struct TodayEnergyBalanceCard: View {
    @Environment(HealthService.self) private var health
    let profile: UserProfile
    let logs: [DayLog]
    let programs: [WorkoutProgram]
    let latestKg: Double?
    @AppStorage("energy.range") private var range = 0   // 0 day · 1 week · 2 month

    private struct DayE { var key: String; var burned: Double; var eaten: Double; var deficit: Double { burned - eaten } }

    var body: some View {
        let e = Energy.summary(profile: profile, health: health, day: logs.day(DayKey.today), latestMeasureKg: latestKg, isToday: true)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TodayIconBadge(symbol: "chart.bar.xaxis", tint: .bPrimary)
                Text("Enerji dengesi").font(.bXs).foregroundStyle(Color.bMutedFg)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(Array(["Gün", "Hafta", "Ay"].enumerated()), id: \.offset) { i, t in
                        Button { haptic(); withAnimation(.snappy) { range = i } } label: {
                            Text(tl(t)).font(.geist(12, range == i ? .semibold : .medium)).foregroundStyle(range == i ? Color.bFg : Color.bMutedFg)
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(range == i ? Color.bCard : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(range == i ? [.isSelected] : [])
                    }
                }
                .padding(2).background(Color.bFg.opacity(0.07), in: Capsule())
            }
            if let bmr = e.bmr {
                if range == 0 { today(e, bmr: bmr) } else { period(range == 1 ? 7 : 30, bmr: bmr, e: e) }
            } else {
                Text("Hesap için Profil'de \(e.missing.joined(separator: ", ")) eksik.").font(.bSm).foregroundStyle(Color.bMutedFg)
            }
        }
        .bCard()
    }

    private var kgBody: Double { latestKg ?? profile.startKg ?? 75 }

    /// Today's planned workout (its estimated calories if not done)
    private func plannedWorkout(_ day: DayLog?) -> (name: String, kcal: Double)? {
        let raw = day?.programIdRaw
        let id: String? = raw != nil ? (raw!.isEmpty ? nil : raw) : Schedule.programId(profile.schedule, date: DayKey.today)
        guard let id, let p = programs.first(where: { $0.pid == id }), !p.blocks.allExercises.isEmpty else { return nil }
        let mins = CalorieEngine.estimatedMinutes(sets: p.blocks.restProfile)
        return (p.name, CalorieEngine.workoutKcal(minutes: mins, weightKg: kgBody))
    }

    @ViewBuilder private func today(_ e: EnergySummary, bmr: Double) -> some View {
        let day = logs.day(DayKey.today)
        let done = (day?.workoutDone ?? false) || (day?.workoutSeconds ?? 0) > 0
        let plan = plannedWorkout(day)
        // active calories from Health already include a done workout; the estimate is added only for a workout not done yet
        let wk: Double = done ? (e.activeSource == .health ? 0 : 0) : (plan?.kcal ?? 0)
        let burned = bmr + e.activeKcal + wk
        let d = burned - e.eaten
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fmt0(abs(d))).font(.bNum(28, relativeTo: .title2)).foregroundStyle(d >= 0 ? Color.bSuccess : Color.bDestructive)
                Text(d >= 0 ? "kcal açık" : "kcal fazla").font(.geist(15, .medium)).foregroundStyle(Color.bMutedFg)
                Spacer(minLength: 0)
                Text("≈ \(fmt1(abs(d) / 7700 * 1000)) g yağ").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
            }
            Text("Gün sonu tahmini").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, -6)
            // burned and eaten bars side by side
            balanceBar(burned: burned, eaten: e.eaten)
            VStack(spacing: 0) {
                row("Bazal metabolizma", "gün boyu", bmr, sign: "+")
                row("Hareket", e.activeSource == .health ? "Apple Sağlık" : "adımdan tahmin", e.activeKcal, sign: "+")
                if let plan {
                    row("Antrenman", done ? String(localized: "\(plan.name) · yapıldı, harekete dahil") : String(localized: "\(plan.name) · tahmini"), done ? nil : wk, sign: "+")
                } else {
                    row("Antrenman", "bugün dinlenme", nil, sign: "+")
                }
                row("Yenen", String(localized: "\(day?.entries.count ?? 0) kayıt"), e.eaten, sign: "−", strong: true)
            }
        }
    }

    @ViewBuilder private func period(_ n: Int, bmr: Double, e: EnergySummary) -> some View {
        let today = DayKey.today
        let dict = Dictionary(logs.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let days: [DayE] = (0..<n).compactMap { i in
            let k = DayKey.shift(today, days: -i)
            guard let L = dict[k], !L.entries.isEmpty else { return nil }   // days without food logs don't count
            let steps = max(L.steps, k == today ? health.stepsToday : (health.weekSteps[k] ?? 0))
            let active = k == today ? e.activeKcal : CalorieEngine.stepsKcal(steps: steps, weightKg: kgBody) + L.workoutKcal
            let frac = k == today ? min(1, Date.now.timeIntervalSince(DayKey.calendar.startOfDay(for: .now)) / 86_400) : 1
            return DayE(key: k, burned: bmr * frac + active, eaten: L.eaten.kcal)
        }.reversed()
        let burned = days.reduce(0) { $0 + $1.burned }, eaten = days.reduce(0) { $0 + $1.eaten }
        let d = burned - eaten
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fmt0(abs(d))).font(.bNum(28, relativeTo: .title2)).foregroundStyle(d >= 0 ? Color.bSuccess : Color.bDestructive)
                Text(d >= 0 ? "kcal açık" : "kcal fazla").font(.geist(15, .medium)).foregroundStyle(Color.bMutedFg)
                Spacer(minLength: 0)
                Text("≈ \(fmt1(abs(d) / 7700)) kg yağ").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
            }
            Text(days.isEmpty ? "Bu dönemde yemek kaydı yok" : "Son \(n) gün · kayıtlı \(days.count) gün · günde ort. \(fmt0(d / Double(max(1, days.count)))) kcal")
                .font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, -6)
            // daily deficit bars: green deficit, red surplus
            if !days.isEmpty {
                let peak = max(1, days.map { abs($0.deficit) }.max() ?? 1)
                HStack(alignment: .center, spacing: n > 7 ? 2 : 6) {
                    ForEach(days, id: \.key) { x in
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.clear).frame(height: 24 * (1 - max(0, x.deficit) / peak))
                            RoundedRectangle(cornerRadius: 2).fill(Color.bSuccess).frame(height: 24 * max(0, x.deficit) / peak)
                            Rectangle().fill(Color.bBorder).frame(height: 1)
                            RoundedRectangle(cornerRadius: 2).fill(Color.bDestructive).frame(height: 24 * max(0, -x.deficit) / peak)
                            Rectangle().fill(Color.clear).frame(height: 24 * (1 - max(0, -x.deficit) / peak))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 49)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Günlük kalori açığı grafiği")
            }
            VStack(spacing: 0) {
                row("Yakılan", "bazal + hareket + antrenman", burned, sign: "+")
                row("Yenen", String(localized: "\(days.reduce(0) { $0 + (dict[$1.key]?.entries.count ?? 0) }) kayıt"), eaten, sign: "−", strong: true)
            }
        }
    }

    private func balanceBar(burned: Double, eaten: Double) -> some View {
        let m = max(1, max(burned, eaten))
        return VStack(spacing: 4) {
            GeometryReader { g in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color.fitKcal).frame(width: g.size.width * burned / m, height: 8)
                    Capsule().fill(Color.bFg.opacity(0.85)).frame(width: g.size.width * eaten / m, height: 8)
                }
            }
            .frame(height: 20)
            HStack {
                Label { Text("Yakılan \(fmt0(burned))") } icon: { Circle().fill(Color.fitKcal).frame(width: 7, height: 7) }
                Spacer()
                Label { Text("Yenen \(fmt0(eaten))") } icon: { Circle().fill(Color.bFg.opacity(0.85)).frame(width: 7, height: 7) }
            }
            .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
        }
    }

    private func row(_ t: String, _ sub: String, _ v: Double?, sign: String, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tl(t)).font(.bSm).foregroundStyle(Color.bMutedFg)
                Text(tl(sub)).font(.geist(11)).foregroundStyle(Color.bMutedFg.opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(v.map { String(localized: "\(sign)\(fmt0($0)) kcal") } ?? "–").font(.bNum(15)).foregroundStyle(strong ? Color.bFg : Color.bFg.opacity(0.9))
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Color.bBorder).frame(height: 1) }
    }
}
