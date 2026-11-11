import Foundation
import SwiftData
import GymPaperKit

// Workout logic: plan history, day assignment, completion, records, volume and strength level.

@MainActor
enum Wk {
    // MARK: Date helpers
    static var months: [String] { DayKey.monthLong }
    private static func parts(_ k: String) -> (Int, Int, Int)? {
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        return (p[0], p[1], p[2])
    }
    /// "24 Ekim 2026"
    static func longDate(_ k: String) -> String { guard let (y, m, d) = parts(k) else { return "–" }; return "\(d) \(months[m - 1]) \(y)" }
    /// "24 Oct"
    static func shortDate(_ k: String) -> String { guard let (_, m, d) = parts(k) else { return "–" }; return "\(d) \(DayKey.monthShort[m - 1])" }
    static func mmss(_ s: Int) -> String { String(format: "%d:%02d", max(0, s) / 60, max(0, s) % 60) }
    private static let trLocale = Locale(identifier: "tr_TR")   // no new Locale per call
    static func lower(_ s: String) -> String { Locale.current.language.languageCode?.identifier == "tr" ? s.lowercased(with: trLocale) : s }
    /// Day `i` of this week (+ week offset)
    static func weekDate(_ i: Int, _ wk: Int = 0) -> String { DayKey.weekDate(DayKey.today, dow: i, weekOffset: wk) }
    /// `day` or the first `dow` after it
    static func nextOnOrAfter(_ day: String, _ dow: Int) -> String { DayKey.shift(day, days: ((dow - DayKey.weekday(day)) + 7) % 7) }

    // MARK: Data access
    static func allPrograms(_ ctx: ModelContext) -> [WorkoutProgram] {
        (try? ctx.fetch(FetchDescriptor<WorkoutProgram>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
    static func live(_ ctx: ModelContext) -> [WorkoutProgram] { allPrograms(ctx).filter { !$0.archived } }
    static func program(_ pid: String?, _ ctx: ModelContext) -> WorkoutProgram? {
        guard let pid, !pid.isEmpty else { return nil }
        return allPrograms(ctx).first { $0.pid == pid }
    }
    static func allDays(_ ctx: ModelContext) -> [DayLog] {
        WkMemo.get("days") { (try? ctx.fetch(FetchDescriptor<DayLog>())) ?? [] }
    }

    // MARK: Plan
    static func scheduleAt(_ profile: UserProfile, _ date: String) -> [String: String?] { Schedule.at(profile.schedule, date: date) }

    /// The day's program id: the day's own pick, else the weekly plan on that date
    static func programIdFor(_ date: String, profile: UserProfile, day: DayLog?) -> String? {
        if let raw = day?.programIdRaw { return raw.isEmpty ? nil : raw }
        return Schedule.programId(profile.schedule, date: date)
    }
    /// Assigned program (even without exercises)
    static func assignedProgram(_ date: String, profile: UserProfile, ctx: ModelContext) -> WorkoutProgram? {
        program(programIdFor(date, profile: profile, day: Store.day(ctx, date, create: false)), ctx)
    }
    /// The day's workout: a program without exercises counts as rest
    static func programFor(_ date: String, profile: UserProfile, ctx: ModelContext) -> WorkoutProgram? {
        guard let p = assignedProgram(date, profile: profile, ctx: ctx), !p.blocks.allExercises.isEmpty else { return nil }
        return p
    }

    static func activeDay(_ d: DayLog?) -> Bool {
        guard let d else { return false }
        return d.workoutDone || d.exDone.values.contains(true) || d.sets.values.contains { $0.contains(where: \.done) }
    }

    /// Changes weekday `dow` in the weekly plan from `from` on; earlier dates are unaffected
    static func setScheduleFrom(_ ctx: ModelContext, _ profile: UserProfile, from: String, dow: Int, pid: String?) {
        pinActive(ctx, profile, from: from, dow: dow)
        var h = profile.schedule
        if h.isEmpty { h = [ScheduleEntry(from: "0000-01-01", days: [:])] }
        Schedule.set(&h, from: from, dow: dow, programId: pid)
        profile.schedule = h
        clearFutureOverrides(ctx, from: from, dow: dow)
    }

    /// Pins started (or open-session) days to their current program before the plan changes
    static func pinActive(_ ctx: ModelContext, _ profile: UserProfile, from: String, dow: Int? = nil) {
        for d in allDays(ctx) where d.date >= from && (dow == nil || DayKey.weekday(d.date) == dow)
            && d.programIdRaw == nil && (activeDay(d) || WkSessionClock.load(d.date) != nil) {
            if let p = Schedule.programId(profile.schedule, date: d.date) { d.programIdRaw = p }
        }
    }

    /// Removes future, not-yet-started "this day only" picks for that weekday
    static func clearFutureOverrides(_ ctx: ModelContext, from: String, dow: Int) {
        for d in allDays(ctx) where d.date >= from && DayKey.weekday(d.date) == dow && d.programIdRaw != nil && !activeDay(d) {
            let p = program(d.programIdRaw, ctx)
            if p == nil || p!.blocks.allExercises.isEmpty { d.programIdRaw = nil }
        }
    }

    /// Assign a program to a day. repeats: same weekday every week from this date (only that day for past dates)
    static func assignDay(_ ctx: ModelContext, _ profile: UserProfile, date: String, pid: String?, repeats: Bool) {
        let L = Store.day(ctx, date)!
        // When the program changes, the old program's done marks don't carry over; set logs stay for history
        if programIdFor(date, profile: profile, day: L) != pid { L.workoutDone = false; L.exDone = [:] }
        if repeats && date >= DayKey.today {
            let from = nextOnOrAfter(DayKey.today, DayKey.weekday(date))
            L.programIdRaw = nil
            setScheduleFrom(ctx, profile, from: from < date ? from : date, dow: DayKey.weekday(date), pid: pid)
        } else {
            L.programIdRaw = pid ?? ""
        }
    }

    /// Before a program's content changes, binds past days that used it to an unchanged archive copy
    static func freezePast(_ ctx: ModelContext, _ prog: WorkoutProgram, name: String? = nil) {
        guard !prog.archived else { return }
        let profile = Store.profile(ctx), today = DayKey.today
        let days = allDays(ctx).filter { $0.date < today && activeDay($0) && programIdFor($0.date, profile: profile, day: $0) == prog.pid }
        guard !days.isEmpty else { return }
        let snap = WorkoutProgram(pid: UUID().uuidString, name: name ?? prog.name, blocks: prog.blocks)
        snap.short = prog.short; snap.archived = true
        ctx.insert(snap)
        for d in days { d.programIdRaw = snap.pid }
    }

    /// When a program is deleted: removes it from future weekly plan entries and day picks
    static func clearFutureAssignments(_ ctx: ModelContext, _ profile: UserProfile, pid: String) {
        let today = DayKey.today
        pinActive(ctx, profile, from: today)
        var h = profile.schedule
        var changed = false
        // split today's entry from today on, then drop it from all future entries
        let cur = Schedule.at(h, date: today)
        if cur.values.contains(where: { $0 == pid }) {
            for (k, v) in cur where v == pid { if let dow = Int(k) { Schedule.set(&h, from: today, dow: dow, programId: nil); changed = true } }
        }
        for i in h.indices where h[i].from >= today {
            for (k, v) in h[i].days where v == pid { h[i].days[k] = .some(nil); changed = true }
        }
        if changed { profile.schedule = h }
        for d in allDays(ctx) where d.date >= today && d.programIdRaw == pid && !activeDay(d) { d.programIdRaw = nil }
    }

    // MARK: Tamamlama
    static func completeWorkout(_ ctx: ModelContext, date: String, prog: WorkoutProgram, only: Set<String>? = nil) {
        WkMemo.clear(); defer { WkMemo.clear() }
        let L = Store.day(ctx, date)!
        // a partial log counts as a finished workout only when every exercise is done
        L.workoutDone = only.map { o in prog.blocks.allExercises.allSatisfy { o.contains($0.id) || L.exDone[$0.id] == true } } ?? true
        // tapping Done while a session is open must not lose the duration
        if L.workoutSeconds == 0, let c = WkSessionClock.load(date) {
            let sec = c.elapsed(Date()); if sec > 0 { L.workoutSeconds = min(sec, 4 * 3600) }
        }
        WkSessionClock.clear(date)
        if L.programIdRaw == nil { L.programIdRaw = prog.pid }
        var X = L.exDone
        for e in prog.blocks.allExercises where only?.contains(e.id) ?? true { X[e.id] = true }
        L.exDone = X
    }
    static func uncompleteWorkout(_ ctx: ModelContext, date: String, prog: WorkoutProgram) {
        WkMemo.clear(); defer { WkMemo.clear() }
        let L = Store.day(ctx, date)!
        L.workoutDone = false
        L.workoutSeconds = 0; L.workoutKcal = 0      // lets a new session write a new duration
        WkSessionClock.clear(date)
        var X = L.exDone
        var S = L.sets
        for e in prog.blocks.allExercises {
            X[e.id] = false
            if var a = S[e.id] { for i in a.indices { a[i].done = false }; S[e.id] = a }   // WK-13
        }
        L.exDone = X
        L.sets = S
    }
    /// Row checkbox; the workout completes when all are done
    static func toggleExDone(_ ctx: ModelContext, date: String, prog: WorkoutProgram, e: Exercise) {
        WkMemo.clear(); defer { WkMemo.clear() }
        let L = Store.day(ctx, date)!
        let on = exDoneCount(e, day: L) < e.sets
        var X = L.exDone; X[e.id] = on; L.exDone = X
        // unmarking also clears that exercise's sets so the session can be done again
        if !on, var a = L.sets[e.id] { for i in a.indices { a[i].done = false }; var S = L.sets; S[e.id] = a; L.sets = S }
        if on && prog.blocks.allExercises.allSatisfy({ exDoneCount($0, day: L) >= $0.sets }) { completeWorkout(ctx, date: date, prog: prog) }
        else if !on && L.workoutDone { L.workoutDone = false }
    }

    /// Writes one set (extends the array if needed)
    static func setLog(_ ctx: ModelContext, date: String, eid: String, index i: Int, _ f: (inout SetLog) -> Void) {
        WkMemo.clear(); defer { WkMemo.clear() }
        let L = Store.day(ctx, date)!
        var S = L.sets
        var arr = S[eid] ?? []
        while arr.count <= i { arr.append(SetLog()) }
        f(&arr[i])
        S[eid] = arr; L.sets = S
        if arr[i].done, L.exDone[eid] == false { var X = L.exDone; X.removeValue(forKey: eid); L.exDone = X }
    }

    /// Weight entered in the session is written to the program; later days open with it
    /// History isn't frozen: past sets keep their weight in their own log
    static func rememberLoad(_ prog: WorkoutProgram?, eid: String, kg: Double?) {
        guard let prog, !prog.archived, let kg, kg > 0,
              let e = prog.blocks.allExercises.first(where: { $0.id == eid }), e.unit == "tekrar", e.kg != kg else { return }
        WkMemo.clear(); defer { WkMemo.clear() }
        var b = prog.blocks
        updateExercise(&b, eid: eid) { $0.kg = kg }
        prog.blocks = b
    }

    struct Lifted { var date: String; var kg: Double; var reps: Int? }
    /// The last set with weight for this exercise before a date
    static func lastLifted(_ ctx: ModelContext, eid: String, before: String) -> Lifted? {
        // only earlier days, newest first and capped, instead of the whole table
        var fd = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date < before }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 365
        for d in (try? ctx.fetch(fd)) ?? [] {
            if let hit = (d.sets[eid] ?? []).last(where: { $0.done && ($0.kg ?? 0) > 0 }) { return Lifted(date: d.date, kg: hit.kg ?? 0, reps: hit.reps) }
        }
        return nil
    }

    // MARK: Program editing
    /// Changes program blocks (freezes history first)
    static func editBlocks(_ ctx: ModelContext, _ prog: WorkoutProgram, _ f: (inout [Block]) -> Void) {
        WkMemo.clear(); defer { WkMemo.clear() }
        freezePast(ctx, prog)
        var b = prog.blocks; f(&b); prog.blocks = b
    }
    /// Updates an exercise by id (single or in a superset)
    static func updateExercise(_ blocks: inout [Block], eid: String, _ f: (inout Exercise) -> Void) {
        for i in blocks.indices {
            if blocks[i].kind == .single, var e = blocks[i].ex, e.id == eid { f(&e); blocks[i].ex = e; blocks[i].rounds = e.sets; blocks[i].rest = e.rest }
            if blocks[i].kind == .superset, let k = blocks[i].exs.firstIndex(where: { $0.id == eid }) { f(&blocks[i].exs[k]) }
        }
    }
    static func findExercise(_ prog: WorkoutProgram?, _ eid: String) -> Exercise? { prog?.blocks.allExercises.first { $0.id == eid } }
    static func supersetOf(_ prog: WorkoutProgram?, eid: String) -> Block? { prog?.blocks.first { $0.kind == .superset && $0.exs.contains { $0.id == eid } } }

    /// Copy with new ids (adding from a template)
    static func clone(_ p: WkTemplateProgram) -> WorkoutProgram {
        let blocks = p.blocks.map { b -> Block in
            if b.kind == .single, var e = b.ex { e.id = UUID().uuidString; return Block(single: e) }
            return Block(superset: b.exs.map { var e = $0; e.id = UUID().uuidString; return e }, rounds: b.rounds, rest: b.rest, tag: b.tag)
        }
        return WorkoutProgram(pid: UUID().uuidString, name: p.name, blocks: blocks)
    }

    /// Adds a ready-made program (reuses one with the same name) and writes it into the weekly plan from today.
    /// Returns the added programs and the previous plan for undo (My programs, onboarding)
    @discardableResult
    /// `assignDays: false`: programs are only added, not placed in the weekly plan (the user picks the days)
    static func applyTemplate(_ t: WkTemplate, ctx: ModelContext, profile: UserProfile, assignDays: Bool = true) -> (added: [WorkoutProgram], oldSchedule: [ScheduleEntry]) {
        let today = DayKey.today, oldSched = profile.schedule
        let live = Store.programs(ctx)
        var map: [String: String] = [:], added: [WorkoutProgram] = []
        for p in t.programs {
            if let ex = live.first(where: { $0.name == p.name }) { map[p.id] = ex.pid }
            else { let c = clone(p); ctx.insert(c); map[p.id] = c.pid; added.append(c) }
        }
        if assignDays { for (k, v) in t.schedule { if let d = Int(k) { setScheduleFrom(ctx, profile, from: today, dow: d, pid: v.flatMap { map[$0] }) } } }
        return (added, oldSched)
    }

    // MARK: Short name ("Upper Body A" → "Upper A")
    private static let shortMap: [(String, String)] = [
        ("alt v[uü]cut|bacak|legs?\\b|squat", "Bacak"), ("[uü]st v[uü]cut|upper", "Üst"), ("alt|lower", "Alt"),
        ("iti[sş]|push", "İtiş"), ("[cç]eki[sş]|pull", "Çekiş"), ("full ?body|t[uü]m v[uü]cut", "Tüm"),
        ("kal[cç]a|glute", "Kalça"), ("g[oö]ğ[uü]s|gogus|chest", "Göğüs"), ("s[ıi]rt|back", "Sırt"), ("omuz|shoulder", "Omuz"),
        ("kol|arm|biceps|triceps", "Kol"), ("kar[ıi]n|core|abs", "Karın"), ("kardiyo|cardio|ko[sş]u", "Kardiyo"),
    ]
    static func shortOf(_ p: WorkoutProgram?) -> String {
        guard let p else { return "–" }
        if let s = p.short?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return String(s.prefix(10)) }
        return shortOf(name: p.name)
    }
    static func shortOf(name raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "–" }
        var letter: String?
        if let r = name.range(of: "\\s([A-D]|\\d)$", options: .regularExpression) { letter = String(name[r]).trimmingCharacters(in: .whitespaces) }
        let base = shortMap.first { name.range(of: $0.0, options: [.regularExpression, .caseInsensitive]) != nil }.map { tl($0.1) }
            ?? String((name.split(separator: " ").first.map(String.init) ?? "Antr.").prefix(7))
        return letter.map { "\(base) \($0)" } ?? base
    }

    static func meta(_ e: Exercise) -> String {
        var s = String(localized: "\(e.sets) set · \(e.reps) \(tl(e.unit))")
        if let kg = e.kg, kg > 0 { s += String(localized: " · \(fmt1(kg)) kg") }
        if e.rest > 0 { s += String(localized: " · \(e.rest) sn") }
        return s
    }
}

// MARK: - Ready-made programs and exercise library (generated JSON)

struct WkTemplateProgram: Decodable { var id: String; var name: String; var blocks: [Block] }
struct WkTemplate: Decodable, Identifiable {
    var key: String; var name: String; var days: Int?; var who: String; var split: String
    var programs: [WkTemplateProgram]
    var schedule: [String: String?]
    var id: String { key }
    static let all: [WkTemplate] = {
        guard let u = Bundle.main.url(forResource: "workout-templates", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([WkTemplate].self, from: d)) ?? []
    }()
}

struct WkLibItem: Decodable, Identifiable, Hashable {
    var name: String; var muscle: String; var unit: String; var reps: Int; var sets: Int; var rest: Int
    var tr: [String] = []
    var mine: Bool? = nil
    var progs: [String]? = nil
    var id: String { name }
    enum CodingKeys: String, CodingKey { case name, muscle, unit, reps, sets, rest, tr }
    init(name: String, muscle: String, unit: String, reps: Int, sets: Int, rest: Int, tr: [String] = [], mine: Bool? = nil, progs: [String]? = nil) {
        self.name = name; self.muscle = muscle; self.unit = unit; self.reps = reps; self.sets = sets; self.rest = rest; self.tr = tr; self.mine = mine; self.progs = progs
    }
}
struct WkLibrary: Decodable {
    var muscles: [String]; var exercises: [WkLibItem]
    static let shared: WkLibrary = {
        guard let u = Bundle.main.url(forResource: "exercise-library", withExtension: "json"), let d = try? Data(contentsOf: u),
              let l = try? JSONDecoder().decode(WkLibrary.self, from: d) else { return WkLibrary(muscles: [], exercises: []) }
        return l
    }()

    /// Library + your own exercises from programs
    @MainActor static func list(_ ctx: ModelContext) -> [WkLibItem] {
        var map: [String: WkLibItem] = [:]; var order: [String] = []
        func put(_ e: WkLibItem, mine: Bool) {
            let k = TextNorm.norm(e.name)
            if map[k] == nil { order.append(k) }
            if map[k] == nil || mine {
                var x = e; x.muscle = e.muscle.isEmpty ? (map[k]?.muscle ?? "Diğer") : e.muscle
                x.tr = map[k]?.tr ?? e.tr; x.mine = mine || (map[k]?.mine ?? false); x.progs = map[k]?.progs
                map[k] = x
            }
        }
        shared.exercises.forEach { put($0, mine: false) }
        for p in Wk.live(ctx) {
            for e in p.blocks.allExercises {
                put(WkLibItem(name: e.name, muscle: e.muscle, unit: e.unit, reps: e.reps, sets: e.sets, rest: e.rest), mine: true)
                let k = TextNorm.norm(e.name)
                var progs = map[k]?.progs ?? []
                if !progs.contains(p.name) { progs.append(p.name) }
                map[k]?.progs = progs
            }
        }
        return order.compactMap { map[$0] }
    }
}

// MARK: - Progress

struct WkSession { var date: String; var name: String; var sets: [(kg: Double, reps: Int)]; var best: (kg: Double, reps: Int, e1rm: Double); var vol: Double }
struct WkPR: Identifiable { var date: String; var name: String; var kg: Double; var reps: Int; var e1rm: Double; var id: String { date + name } }
struct WkWeek: Identifiable { var start: String; var vol: Double; var workouts: Int; var id: String { start } }

@MainActor
enum WkProgress {
    static func e1rm(_ kg: Double, _ reps: Int) -> Double { kg * (1 + Double(reps) / 30) }
    /// Bodyweight for assisted exercises (load = bodyweight − assistance); 75 kg until a weigh-in exists
    static func bodyweightForLoad(_ ctx: ModelContext) -> Double { Store.latestWeight(ctx) ?? 75 }
    /// Weight that counts as lifted (assisted: bodyweight − assistance)
    static func load(_ name: String, _ kg: Double, bw: Double) -> Double { Progression.load(name: name, kg: kg, bodyweight: bw) }

    static func exIndex(_ ctx: ModelContext) -> [String: Exercise] {
        var m: [String: Exercise] = [:]
        // archive copies (freezePast) carry the same exercise ids; the current (non-archived) definition wins
        for p in Wk.allPrograms(ctx) where p.archived { for e in p.blocks.allExercises { m[e.id] = e } }
        for p in Wk.allPrograms(ctx) where !p.archived { for e in p.blocks.allExercises { m[e.id] = e } }
        return m
    }
    private static func doneSets(_ L: DayLog, _ idx: [String: Exercise]) -> [(key: String, name: String, kg: Double, reps: Int)] {
        var out: [(key: String, name: String, kg: Double, reps: Int)] = []
        for (eid, arr) in L.sets {
            guard let ex = idx[eid], ex.unit == "tekrar" else { continue }
            for s in arr where s.done {
                let kg = s.kg ?? 0, reps = (s.reps ?? 0) > 0 ? s.reps! : ex.reps
                if kg > 0 && reps > 0 { out.append((key: TextNorm.norm(ex.name), name: ex.name, kg: kg, reps: reps)) }
            }
        }
        return out
    }
    static func histories(_ ctx: ModelContext) -> [String: [WkSession]] {
        WkMemo.get("histories") { computeHistories(ctx) }
    }
    private static func computeHistories(_ ctx: ModelContext) -> [String: [WkSession]] {
        let idx = exIndex(ctx), bw = bodyweightForLoad(ctx)
        var H: [String: [WkSession]] = [:]
        for L in Wk.allDays(ctx).sorted(by: { $0.date < $1.date }) {
            var by: [String: [(key: String, name: String, kg: Double, reps: Int)]] = [:]
            for s in doneSets(L, idx) { by[s.key, default: []].append(s) }
            for (k, sets) in by {
                var best = (kg: 0.0, reps: 0, e1rm: -1.0)
                // best set by lifted load: for assisted exercises less help wins
                for s in sets { let v = e1rm(load(s.name, s.kg, bw: bw), s.reps); if v > best.e1rm { best = (s.kg, s.reps, v) } }
                H[k, default: []].append(WkSession(date: L.date, name: sets[0].name, sets: sets.map { ($0.kg, $0.reps) }, best: best, vol: sets.reduce(0) { $0 + load($1.name, $1.kg, bw: bw) * Double($1.reps) }))
            }
        }
        return H
    }
    static func historyOf(_ ctx: ModelContext, _ name: String) -> [WkSession] { histories(ctx)[TextNorm.norm(name)] ?? [] }

    static func prList(_ H: [String: [WkSession]]) -> [WkPR] {
        var out: [WkPR] = []
        for list in H.values {
            var best = 0.0
            for (i, s) in list.enumerated() {
                if i > 0 && s.best.e1rm > best + 0.01 { out.append(WkPR(date: s.date, name: s.name, kg: s.best.kg, reps: s.best.reps, e1rm: s.best.e1rm)) }
                best = max(best, s.best.e1rm)
            }
        }
        return out.sorted { $0.date != $1.date ? $0.date > $1.date : $0.e1rm > $1.e1rm }
    }
    static func prsOn(_ ctx: ModelContext, _ date: String) -> [WkPR] { prList(histories(ctx)).filter { $0.date == date } }

    static func weekStart(_ key: String = DayKey.today, _ offset: Int = 0) -> String { DayKey.shift(key, days: -DayKey.weekday(key) + offset * 7) }
    private static func dayDone(_ L: DayLog, _ idx: [String: Exercise]) -> Bool { L.workoutDone || !doneSets(L, idx).isEmpty || L.exDone.values.contains(true) }

    static func weeks(_ ctx: ModelContext, _ n: Int = 8) -> [WkWeek] {
        let idx = exIndex(ctx), cur = weekStart(), bw = bodyweightForLoad(ctx)
        var W = (0..<n).map { WkWeek(start: weekStart(cur, $0 - n + 1), vol: 0, workouts: 0) }
        for L in Wk.allDays(ctx) {
            guard let i = W.firstIndex(where: { L.date >= $0.start && L.date < DayKey.shift($0.start, days: 7) }) else { continue }
            W[i].vol += doneSets(L, idx).reduce(0) { $0 + load($1.name, $1.kg, bw: bw) * Double($1.reps) }
            if dayDone(L, idx) { W[i].workouts += 1 }
        }
        return W
    }
    static func streakWeeks(_ ctx: ModelContext) -> Int {
        let idx = exIndex(ctx)
        let done = Set(Wk.allDays(ctx).filter { dayDone($0, idx) }.map { weekStart($0.date) })
        var off = done.contains(weekStart()) ? 0 : -1, n = 0
        while done.contains(weekStart(DayKey.today, off)) { n += 1; off -= 1 }
        return n
    }

    struct Suggestion { var kg: Double; var up: Bool; var reps: Int? = nil; var streak: Int = 0; var needed: Int = Progression.needed; var assisted = false }
    /// Weight suggestion: GymPaperKit `Progression` — all sets at 15+ reps for 3 workouts in a row at the same weight
    /// → step up by equipment (dumbbell +2, bar +2.5, machine/cable +5), target 8 reps. Never below the current weight.
    static func suggestKg(_ ctx: ModelContext, _ ex: Exercise, date: String, currentKg: Double? = nil) -> Suggestion? {
        guard ex.unit == "tekrar" else { return nil }
        let hist = historyOf(ctx, ex.name).filter { $0.date < date }
            .map { Progression.Session(date: $0.date, sets: $0.sets.map { Progression.Lift(kg: $0.kg, reps: $0.reps) }) }
        guard !hist.isEmpty, let r = Progression.suggest(name: ex.name, history: hist, currentKg: currentKg ?? ex.kg) else { return nil }
        return Suggestion(kg: r.kg, up: r.up, reps: r.reps, streak: r.streak, needed: r.needed, assisted: r.assisted)
    }
    static func beatsPrevBest(_ ctx: ModelContext, name: String, date: String, kg: Double, reps: Int) -> Bool {
        let prev = historyOf(ctx, name).filter { $0.date < date }
        guard !prev.isEmpty, kg > 0, reps > 0 else { return false }
        return e1rm(load(name, kg, bw: bodyweightForLoad(ctx)), reps) > (prev.map(\.best.e1rm).max() ?? 0) + 0.01
    }

    // MARK: Strength level
    static let levels = ["Başlangıç", "Acemi", "Orta", "İleri", "Elit"]
    struct Lift { var id: String; var name: String; var names: [String]; var reps = false; var m: [Double]; var f: [Double] }
    static let lifts: [Lift] = [
        Lift(id: "bench", name: "Bench press", names: ["barbell bench press", "bench press", "flat bench press"], m: [0.5, 0.75, 1.0, 1.5, 2.0], f: [0.25, 0.5, 0.75, 1.0, 1.5]),
        Lift(id: "squat", name: "Squat", names: ["back squat", "squat", "barbell squat", "barbell back squat", "high bar squat", "low bar squat"], m: [0.75, 1.25, 1.5, 2.25, 2.75], f: [0.5, 0.75, 1.25, 1.5, 2.0]),
        Lift(id: "deadlift", name: "Deadlift", names: ["deadlift", "conventional deadlift", "barbell deadlift", "sumo deadlift"], m: [1.0, 1.5, 2.0, 2.5, 3.0], f: [0.5, 1.0, 1.25, 1.75, 2.5]),
        Lift(id: "ohp", name: "Overhead press", names: ["overhead press", "military press", "barbell overhead press", "standing overhead press", "barbell shoulder press", "ohp"], m: [0.35, 0.55, 0.75, 1.05, 1.35], f: [0.2, 0.35, 0.5, 0.75, 1.0]),
        Lift(id: "row", name: "Barbell row", names: ["barbell row", "bent over row", "barbell bent over row", "pendlay row"], m: [0.5, 0.75, 1.0, 1.5, 1.75], f: [0.25, 0.4, 0.65, 0.9, 1.2]),
        Lift(id: "pullup", name: "Barfiks", names: ["pull up", "pullup", "chin up", "chinup", "barfiks", "wide grip pull up", "neutral grip pull up"], reps: true, m: [1, 5, 11, 18, 25], f: [1, 2, 5, 10, 16]),
    ]
    struct LevelRow: Identifiable {
        var lift: Lift; var value: Double; var ratio: Double; var isReps: Bool
        var idx: Int; var nextLabel: String?; var pct: Double; var toNext: Double
        var id: String { lift.id }
    }
    struct Levels { var need: String?; var bw: Double; var rows: [LevelRow] }

    static func levelFor(_ v: Double, _ th: [Double]) -> (idx: Int, next: Double?, nextLabel: String?, pct: Double) {
        var idx = -1
        for (i, t) in th.enumerated() where v >= t - 1e-9 { idx = i }
        let next: Double? = idx + 1 < th.count ? th[idx + 1] : nil
        let from = idx >= 0 ? th[idx] : 0
        let pct = next == nil ? 1 : max(0, min(1, (v - from) / ((next! - from) == 0 ? 1 : (next! - from))))
        // idx -1: below the first threshold ("below beginner"); badge and next goal stay consistent
        return (idx, next, next != nil ? levels[idx + 1] : nil, pct)
    }
    static func bodyweight(_ ctx: ModelContext, _ profile: UserProfile) -> Double { Store.latestWeight(ctx) ?? profile.startKg ?? 0 }

    static func strengthLevels(_ ctx: ModelContext, _ profile: UserProfile) -> Levels {
        let bw = bodyweight(ctx, profile)
        guard let sex = profile.sex else { return Levels(need: "sex", bw: bw, rows: []) }
        let H = histories(ctx), idx = exIndex(ctx)
        var rows: [LevelRow] = []
        for lift in lifts {
            let th = sex == .male ? lift.m : lift.f
            if lift.reps {
                var best = 0
                for L in Wk.allDays(ctx) { for (eid, arr) in L.sets { guard let ex = idx[eid], lift.names.contains(TextNorm.norm(ex.name)) else { continue }
                    for s in arr where s.done { best = max(best, (s.reps ?? 0) > 0 ? s.reps! : ex.reps) } } }
                guard best > 0 else { continue }
                let lv = levelFor(Double(best), th)
                rows.append(LevelRow(lift: lift, value: Double(best), ratio: 0, isReps: true, idx: lv.idx, nextLabel: lv.nextLabel, pct: lv.pct, toNext: lv.next.map { max(0, $0 - Double(best)) } ?? 0))
                continue
            }
            guard bw > 0 else { continue }
            var best: Double?
            for n in lift.names { for s in H[TextNorm.norm(n)] ?? [] where best == nil || s.best.e1rm > best! { best = s.best.e1rm } }
            guard let b = best else { continue }
            let lv = levelFor(b / bw, th)
            rows.append(LevelRow(lift: lift, value: b, ratio: b / bw, isReps: false, idx: lv.idx, nextLabel: lv.nextLabel, pct: lv.pct, toNext: lv.next.map { max(0, $0 * bw - b) } ?? 0))
        }
        return Levels(need: bw > 0 ? nil : "bw", bw: bw, rows: rows)
    }
    static func levelOfExercise(_ ctx: ModelContext, _ profile: UserProfile, name: String) -> LevelRow? {
        let n = TextNorm.norm(name)
        guard let lift = lifts.first(where: { $0.names.contains(n) }) else { return nil }
        return strengthLevels(ctx, profile).rows.first { $0.lift.id == lift.id }
    }
}

// MARK: - Session state (start, pause) — duration survives closing and reopening

struct WkSessionClock: Codable {
    var startedAt: Date
    var pausedAt: Date?
    var pausedSec: Double = 0          // legacy field (unused)
    /// Active workout time: starts with the first set; gaps between sets count at most `gapCap`.
    /// So the duration doesn't balloon if the player is left open or the app sits in the background for hours.
    var activeSec: Double?
    var lastAt: Date?
    static let gapCap: Double = 15 * 60
    static let firstSetSec: Double = 60

    init(startedAt: Date = Date()) { self.startedAt = startedAt }

    static func key(_ date: String) -> String { "wk.session.\(date)" }
    static func load(_ date: String) -> WkSessionClock? {
        guard let d = UserDefaults.standard.data(forKey: key(date)) else { return nil }
        return try? JSONDecoder().decode(WkSessionClock.self, from: d)
    }
    func save(_ date: String) { if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key(date)) } }
    static func clear(_ date: String) { UserDefaults.standard.removeObject(forKey: key(date)) }

    var started: Bool { activeSec != nil }

    /// Displayed duration (time since the last set adds at most 15 min)
    func elapsed(_ now: Date) -> Int {
        guard let a = activeSec else { return 0 }
        var t = a
        if pausedAt == nil, let l = lastAt { t += min(max(0, now.timeIntervalSince(l)), Self.gapCap) }
        return Int(t)
    }
    /// Saved duration: up to the last completed set
    var total: Int { Int(activeSec ?? 0) }

    /// Player opened: the clock starts now
    mutating func begin(_ now: Date = Date()) {
        guard activeSec == nil else { return }
        activeSec = 0; lastAt = now; startedAt = now
    }
    /// Set completed
    mutating func mark(_ now: Date = Date()) {
        if activeSec == nil {
            activeSec = Self.firstSetSec
            startedAt = now.addingTimeInterval(-Self.firstSetSec)
        } else if pausedAt == nil, let l = lastAt {
            activeSec! += min(max(0, now.timeIntervalSince(l)), Self.gapCap)
        }
        lastAt = now
    }
    mutating func pause(_ now: Date = Date()) {
        guard pausedAt == nil else { return }
        if activeSec != nil, let l = lastAt { activeSec! += min(max(0, now.timeIntervalSince(l)), Self.gapCap) }
        lastAt = nil; pausedAt = now
    }
    mutating func resume(_ now: Date = Date()) {
        pausedAt = nil
        lastAt = activeSec == nil ? nil : now
    }
}


/// Short-lived cache for heavy history work so one render doesn't repeat the same scan.
/// Invalidated on save (didSave) or after 1 s.
enum WkMemo {
    nonisolated(unsafe) private static var store: [String: (Date, Any)] = [:]
    nonisolated(unsafe) private static var observer: NSObjectProtocol?
    static func get<T>(_ key: String, _ make: () -> T) -> T {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in WkMemo.clear() }
        }
        if let (t, v) = store[key], Date().timeIntervalSince(t) < 1, let x = v as? T { return x }
        let v = make()
        store[key] = (Date(), v)
        return v
    }
    static func clear() { store.removeAll() }
}
