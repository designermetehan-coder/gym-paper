import SwiftUI
import SwiftData
import GymPaperKit

/// Workout detail and program builder: muscle load from the plan + suggestion for a missing area
struct WkMuscleSection: View {
    @Environment(\.modelContext) private var ctx
    let prog: WorkoutProgram
    var canSuggest: Bool
    var title: String = tl("Çalışan kaslar")
    var footnote = true
    /// The week's plan (other days included); an area trained on another day isn't suggested
    var week: [MuscleLoad.Entry]? = nil
    /// Opens Add exercise filtered to the missing muscle group
    let onPick: (String) -> Void

    var body: some View {
        let blocks = prog.blocks
        let entries = MuscleLoad.load(MuscleData.plan(blocks), scope: .workout)
        let mins = Int(CalorieEngine.estimatedMinutes(sets: blocks.restProfile).rounded())
        let gap = canSuggest ? MuscleLoad.gap(entries, scope: .workout, week: week) : nil
        let ex = gap.flatMap { MuscleData.suggested($0, exclude: blocks.allExercises, ctx: ctx) }
        MuscleLoadCard(title: title, meta: String(localized: "\(blocks.setCount) set · ~\(mins) dk"), entries: entries, footnote: footnote,
                       suggestion: gap.flatMap { g in ex.map { e in MuscleData.workoutSuggestion(g, ex: e) { onPick(g.muscle) } } })
    }
}

/// Workout tab: the day's workout, or the whole week (done sets so far + the plan for the rest)
struct WkWeekMuscleSection: View {
    @Environment(\.modelContext) private var ctx
    let prog: WorkoutProgram
    let date: String
    let profile: UserProfile
    let logs: [DayLog]
    var canSuggest: Bool
    /// Opens Add exercise filtered to the missing muscle group
    let onPick: (String) -> Void
    @State private var mode = Mode.day

    enum Mode: Hashable { case day, week }

    var body: some View {
        // one card for both modes: only its data changes, so switching animates instead of rebuilding the card
        let blocks = prog.blocks
        let isDay = mode == .day
        let end = DayKey.shift(date, days: 6 - DayKey.weekday(date))
        let w = MuscleData.weekPlan(ctx, logs: logs, profile: profile, through: end)
        let weekEntries = MuscleLoad.load(w.items, scope: .week)
        let entries = isDay ? MuscleLoad.load(MuscleData.plan(blocks), scope: .workout) : weekEntries
        let mins = Int(CalorieEngine.estimatedMinutes(sets: blocks.restProfile).rounded())
        let meta = isDay ? String(localized: "\(blocks.setCount) set · ~\(mins) dk") : String(localized: "\(w.workouts) antrenman · \(w.sets) set")
        let gap = isDay && canSuggest ? MuscleLoad.gap(entries, scope: .workout, week: weekEntries) : nil
        let ex = gap.flatMap { MuscleData.suggested($0, exclude: blocks.allExercises, ctx: ctx) }
        MuscleLoadCard(meta: meta, entries: entries,
                       suggestion: gap.flatMap { g in ex.map { e in MuscleData.workoutSuggestion(g, ex: e) { onPick(g.muscle) } } },
                       scope: isDay ? .workout : .week,
                       control: AnyView(BSegmented(selection: Binding(get: { mode }, set: { m in withAnimation(.snappy(duration: 0.3)) { mode = m } }),
                                                   options: [(Mode.day, date == DayKey.today ? tl("Bugün") : tl("O gün")), (Mode.week, tl("Bu hafta"))])))
    }
}

/// Today › This week: muscle load from done sets; suggests an exercise for the next workout when a main area got no work
struct TodayMuscleWeekCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    let profile: UserProfile
    let logs: [DayLog]

    var body: some View {
        let w = MuscleData.week(ctx, logs: logs)
        if w.workouts > 0 {
            let entries = MuscleLoad.load(w.items, scope: .week)
            MuscleLoadCard(title: tl("Bu hafta çalışan kaslar"), meta: String(localized: "\(w.workouts) antrenman · \(w.sets) set"),
                           entries: entries, suggestion: suggestion(entries, workouts: w.workouts), scope: .week)
        }
    }

    private func suggestion(_ entries: [MuscleLoad.Entry], workouts: Int) -> MuscleSuggestion? {
        guard let gap = MuscleLoad.gap(entries, scope: .week, workouts: workouts) else { return nil }
        let today = DayKey.today
        for i in 0..<7 {
            let d = DayKey.shift(today, days: i)
            guard let p = Wk.programFor(d, profile: profile, ctx: ctx), !p.blocks.allExercises.isEmpty else { continue }
            if i == 0, workoutProgress(p, day: logs.first { $0.date == d }).complete { continue }
            guard let ex = MuscleData.suggested(gap, exclude: p.blocks.allExercises, ctx: ctx) else { return nil }
            let when = i == 0 ? tl("Bugünkü") : String(localized: "\(DayKey.dayLong[DayKey.weekday(d)]) günkü")
            let name = p.name.isEmpty ? tl("Antrenman") : p.name
            let detail = String(localized: "\(when) antrenmana (\(name)) \(ex.name) ekleyelim mi? \(MuscleData.dose(ex))")
            let prompt = "Bu hafta \(gap.muscle) hiç çalışmadı. Sıradaki antrenman: \(when) \(name). Önerilen hareket: \(ex.name) (\(MuscleData.dose(ex)))."
            return MuscleSuggestion(title: String(localized: "\(tl(gap.muscle)) bu hafta hiç çalışmadı"), detail: detail, prompt: prompt) {
                let before = p.blocks
                Wk.editBlocks(ctx, p) { $0.append(Block(single: ex)) }
                app.toast(String(localized: "\(ex.name) · \(name) antrenmanına eklendi")) { p.blocks = before }
            }
        }
        return nil
    }
}
