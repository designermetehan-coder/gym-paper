import SwiftUI
import SwiftData
import GymPaperKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Muscle load card
// Workout detail, program builder, finished workout and Today › This week.
// Figma: Style Guide › Components / Muscle Map › Muscle Load Card; iPhone › v1.2 · Muscle map.

struct MuscleSuggestion {
    var title: String
    var detail: String
    /// Context for Apple Intelligence (personalizes the detail text on supported devices)
    var prompt: String?
    var action: String = tl("Ekle")
    var run: () -> Void
}

struct MuscleLoadCard: View {
    var title: String = tl("Çalışan kaslar")
    var meta: String? = nil
    let entries: [MuscleLoad.Entry]
    var footnote = true
    var suggestion: MuscleSuggestion? = nil
    var scope: MuscleLoad.Scope = .workout
    /// Control under the title, inside the card (Workout › This workout / So far / Week end)
    var control: AnyView? = nil
    @State private var all = false

    var body: some View {
        let levels = Dictionary(entries.map { ($0.muscle, $0.level) }, uniquingKeysWith: { a, _ in a })
        let shown = all ? entries : Array(entries.prefix(6))
        let top = max(entries.first?.sets ?? 1, 0.5)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.geist(16, .semibold, relativeTo: .headline)).foregroundStyle(Color.bFg)
                Spacer(minLength: 8)
                if let meta { Text(meta).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg) }
            }
            if let control { control }
            MuscleMapView(levels: levels).padding(.vertical, 4)
            HeatLegend(scope: scope)
            if entries.isEmpty {
                Text("Kas hedefi olan hareket yok.").font(.bSm).foregroundStyle(Color.bMutedFg)
            } else {
                VStack(spacing: 14) {
                    ForEach(shown) { e in MuscleLoadRow(entry: e, fraction: e.sets / top) }
                }
                if entries.count > 6 {
                    Button { withAnimation(.snappy) { all.toggle() } } label: {
                        Text(all ? "Daha az göster" : "Tümünü göster (\(entries.count))").font(.geist(14, .medium)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.b(.ghost, full: true))
                }
            }
            if footnote {
                Text("Ana kas 1 set, yardımcı kas ½ set sayılır.").font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            if let suggestion { MuscleSuggestionView(s: suggestion) }
        }
        .bCard()
    }
}

struct MuscleLoadRow: View {
    let entry: MuscleLoad.Entry
    let fraction: Double
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tl(entry.muscle)).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                Spacer(minLength: 8)
                Text(MuscleLoad.format(entry.sets)).font(.bNum(15, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                Text("set").font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bFg.opacity(0.10))
                    if entry.sets > 0 {
                        Capsule().fill(Color.bHeat(entry.level)).frame(width: max(6, g.size.width * min(1, fraction)))
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tl(entry.muscle)): \(MuscleLoad.format(entry.sets)) set, \(entry.level.title)")
    }
}

struct MuscleSuggestionView: View {
    let s: MuscleSuggestion
    @State private var ai: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(Color.bFg)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.geist(14, .medium, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                Text(ai ?? s.detail).font(.bXs).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { haptic(); s.run() } label: { BLabel(s.action) }
                .buttonStyle(.b(.primary, .small))
        }
        .padding(12)
        .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
        .task(id: s.prompt) {
            guard let p = s.prompt, let t = await MuscleAdvisor.refine(p, fallback: s.detail) else { return }
            withAnimation { ai = t }
        }
    }
}

// MARK: - Veri

@MainActor
enum MuscleData {
    /// Primary muscle of an exercise: the muscle in the program, else looked up by name in the library
    static func muscle(of e: Exercise) -> String {
        let c = MuscleLoad.canonical(e.muscle)
        if !c.isEmpty { return c }
        let k = TextNorm.norm(e.name)
        let hit = WkLibrary.shared.exercises.first { TextNorm.norm($0.name) == k || $0.tr.contains { TextNorm.norm($0) == k } }
        return hit.map { MuscleLoad.canonical($0.muscle) } ?? ""
    }
    /// From the plan (as many sets as rounds in a superset)
    static func plan(_ blocks: [Block]) -> [MuscleLoad.Item] {
        blocks.flatMap { b in b.exercises.map { e in MuscleLoad.Item(name: e.name, muscle: muscle(of: e), sets: Double(b.kind == .single ? e.sets : b.rounds)) } }
    }
    /// From done sets; an exercise marked done without set logs counts its planned sets
    static func done(_ exercises: [Exercise], day: DayLog?) -> [MuscleLoad.Item] {
        guard let day else { return [] }
        return exercises.compactMap { e in
            let n = (day.sets[e.id] ?? []).filter(\.done).count
            let c = n > 0 ? n : (day.exDone[e.id] == true ? e.sets : 0)
            return c > 0 ? MuscleLoad.Item(name: e.name, muscle: muscle(of: e), sets: Double(c)) : nil
        }
    }
    /// This week's work (Monday → today) and number of workout days
    static func week(_ ctx: ModelContext, logs: [DayLog]) -> (items: [MuscleLoad.Item], workouts: Int, sets: Int) {
        let today = DayKey.today
        return range(ctx, logs: logs, from: DayKey.shift(today, days: -DayKey.weekday(today)), to: today)
    }
    /// The selected day's week, Monday → `through`: done sets for past days and finished workouts,
    /// planned sets for today and later (what the week looks like if the plan is followed)
    static func weekPlan(_ ctx: ModelContext, logs: [DayLog], profile: UserProfile, through: String) -> (items: [MuscleLoad.Item], workouts: Int, sets: Int) {
        let idx = WkProgress.exIndex(ctx), today = DayKey.today
        let monday = DayKey.shift(through, days: -DayKey.weekday(through))
        var items: [MuscleLoad.Item] = [], workouts = 0, sets = 0
        for i in 0..<7 {
            let d = DayKey.shift(monday, days: i)
            guard d <= through else { break }
            let L = logs.first { $0.date == d }
            let exs = L.map { l in Set(l.sets.keys).union(l.exDone.filter(\.value).keys).compactMap { idx[$0] } } ?? []
            var dayItems = done(exs, day: L)
            if d >= today, let p = Wk.programFor(d, profile: profile, ctx: ctx), !workoutProgress(p, day: L).complete {
                dayItems = plan(p.blocks)
            }
            if !dayItems.isEmpty { workouts += 1; items += dayItems; sets += Int(dayItems.reduce(0) { $0 + $1.sets }) }
        }
        return (items, workouts, sets)
    }
    /// Done sets per muscle between two day keys (inclusive)
    static func range(_ ctx: ModelContext, logs: [DayLog], from: String, to: String) -> (items: [MuscleLoad.Item], workouts: Int, sets: Int) {
        let idx = WkProgress.exIndex(ctx)
        var items: [MuscleLoad.Item] = [], workouts = 0, sets = 0
        for L in logs where L.date >= from && L.date <= to {
            let exs = Set(L.sets.keys).union(L.exDone.filter(\.value).keys).compactMap { idx[$0] }
            let d = done(exs, day: L)
            if !d.isEmpty { workouts += 1; items += d; sets += Int(d.reduce(0) { $0 + $1.sets }) }
        }
        return (items, workouts, sets)
    }
    static func libraryCandidates() -> [ExerciseAlternatives.Candidate] {
        WkLibrary.shared.exercises.map { .init(name: $0.name, alias: $0.tr.first, muscle: $0.muscle, unit: $0.unit) }
    }
    /// Exercise for a missing area (library item → program exercise)
    static func suggested(_ gap: MuscleLoad.Gap, exclude: [Exercise], ctx: ModelContext) -> Exercise? {
        let done = Set(WkProgress.histories(ctx).keys)
        guard let c = MuscleLoad.pick(for: gap.muscle, library: libraryCandidates(), done: done, exclude: Set(exclude.map { TextNorm.norm($0.name) })),
              let it = WkLibrary.shared.exercises.first(where: { $0.name == c.name }) else { return nil }
        return Exercise(name: it.name, sets: it.sets, reps: it.reps, unit: it.unit, rest: it.rest, muscle: it.muscle)
    }
    static func dose(_ e: Exercise) -> String {
        e.unit == "tekrar" ? String(localized: "\(e.sets) set · \(e.reps) tekrar") : e.unit == "sn" ? String(localized: "\(e.sets) set · \(e.reps) sn") : String(localized: "\(e.sets) set · \(e.reps) dk")
    }

    /// Suggestion text for a workout / program
    static func workoutSuggestion(_ gap: MuscleLoad.Gap, ex: Exercise, run: @escaping () -> Void) -> MuscleSuggestion {
        let m = tl(gap.muscle)
        let detail = gap.because.map { String(localized: "\(tl($0)) yüklü ve bu hafta \(m) için başka gün yok. Dengelemek için bir hareket seç, örneğin \(ex.name).") }
            ?? String(localized: "Bu hafta \(m) için başka gün yok. Sona bir hareket seç, örneğin \(ex.name).")
        let prompt = "Antrenmanda \(gap.muscle) hiç çalışmıyor ve haftanın başka gününde de yok\(gap.because.map { ", \($0) ise yoğun" } ?? ""). Örnek hareket: \(ex.name) (\(dose(ex)))."
        return MuscleSuggestion(title: String(localized: "\(m) hiç çalışmıyor"), detail: detail, prompt: prompt, action: tl("Hareket seç"), run: run)
    }
}

// MARK: - Apple Intelligence (on-device model; the rule-based text stays otherwise)

@MainActor
enum MuscleAdvisor {
    private static var cache: [String: String] = [:]

    static func refine(_ context: String, fallback: String) async -> String? {
        if let c = cache[context] { return c }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability, model.supportsLocale(Locale.current) else { return nil }
            let lang = Locale.current.language.languageCode?.identifier == "tr" ? "Türkçe" : "English"
            let session = LanguageModelSession(instructions: """
                Bir fitness uygulamasında kısa, samimi bir öneri cümlesi yazıyorsun. Yalnızca tek cümle, en fazla 90 karakter, \
                "sen" diye hitap et, emoji ve tırnak kullanma, hareket adını ve set bilgisini aynen koru. Dil: \(lang).
                """)
            guard let r = try? await session.respond(to: "\(context)\nÖrnek cümle: \(fallback)", options: GenerationOptions(temperature: 0.4)) else { return nil }
            let t = r.content.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
            guard !t.isEmpty, t.count <= 120 else { return nil }
            cache[context] = t
            return t
        }
        #endif
        return nil
    }
}

// MARK: - Exercise detail: worked muscles + how-to (1.2)

/// Primary and secondary muscles of one exercise on the body map
struct ExerciseMusclesCard: View {
    let e: Exercise
    var body: some View {
        let primary = MuscleData.muscle(of: e)
        let secondary = MuscleLoad.secondary(name: e.name, muscle: primary)
        var levels: [String: MuscleLoad.Level] = [:]
        if !primary.isEmpty { levels[MuscleLoad.canonical(primary)] = .max }
        for s in secondary where levels[MuscleLoad.canonical(s)] == nil { levels[MuscleLoad.canonical(s)] = .moderate }
        return HStack(alignment: .center, spacing: 16) {
            MuscleMapView(levels: levels, figureHeight: 120).frame(width: 140)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ana kas").font(.bXs).foregroundStyle(Color.bMutedFg)
                Text(primary.isEmpty ? "–" : tl(primary)).font(.bDisplay(22, relativeTo: .title2))
                if !secondary.isEmpty {
                    Text("Yardımcı").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.top, 6)
                    Text(secondary.map { tl($0) }.joined(separator: " · ")).font(.bSm).foregroundStyle(Color.bMutedFg)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.bFg)
        .bCard()
        .accessibilityElement(children: .combine)
    }
}

/// Three short form cues written on device with Apple Intelligence; hidden when the model is unavailable
struct ExerciseHowTo: View {
    let name: String
    @State private var steps: [String] = []
    private static var cache: [String: [String]] = [:]
    var body: some View {
        Group {
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nasıl yapılır").font(.bXs).foregroundStyle(Color.bMutedFg)
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.bDisplay(15, relativeTo: .body)).monospacedDigit()
                            Text(s).font(.bSm)
                        }
                    }
                    Text("Apple Intelligence ile cihazda yazıldı; emin değilsen form videosuna bak.").font(.bXs).foregroundStyle(Color.bMutedFg)
                }
                .foregroundStyle(Color.bFg)
                .bCard()
                .transition(.opacity)
            }
        }
        .task(id: name) { steps = await Self.load(name) }
    }

    @MainActor static func load(_ name: String) async -> [String] {
        if let c = cache[name] { return c }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability, model.supportsLocale(Locale.current) else { return [] }
            let lang = Locale.current.language.languageCode?.identifier == "tr" ? "Türkçe" : "English"
            let session = LanguageModelSession(instructions: """
                You are a strength coach. Give exactly three short form cues for the exercise, one per line, no numbering, \
                no emoji, at most 80 characters each, second person. Language: \(lang).
                """)
            guard let r = try? await session.respond(to: name, options: GenerationOptions(temperature: 0.2)) else { return [] }
            let lines = r.content.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-•*0123456789.)"))) }
                .filter { !$0.isEmpty && $0.count <= 120 }
            let out = Array(lines.prefix(3))
            if out.count == 3 { cache[name] = out; return out }
        }
        #endif
        return []
    }
}
