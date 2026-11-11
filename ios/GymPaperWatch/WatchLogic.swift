import Foundation
import UIKit
import SwiftData
import Observation
import WatchConnectivity
import UserNotifications
import GymPaperKit

/// A single step in the player (one set of one exercise)
struct WStep: Hashable {
    let ex: Exercise
    let si: Int
    let of: Int
    let rest: Int
    let label: String
    var tag: String? = nil
    var ss = false
    var key: String { "\(ex.id)#\(si)" }
    var timed: Bool { ex.unit != "tekrar" }
}

@MainActor
enum WLogic {
    /// Today's workout progress + fasting plan → snapshot read by the complications
    @MainActor static func publish(_ ctx: ModelContext) {
        let today = DayKey.today
        let day = Store.day(ctx, today, create: false)
        var s = WatchSnap(date: today, program: nil, fast: PhoneSync.shared.fast)
        if let k = PhoneSync.shared.kcal, k.date == today { s.kcalTarget = k.target; s.kcalEaten = k.eaten }
        else if let k = PhoneSync.shared.kcal { s.kcalTarget = k.target; s.kcalEaten = 0 }   // midnight: new day
        // steps and active calories: the larger of the watch's own Health data and iPhone's
        let k = PhoneSync.shared.kcal
        let phoneToday = k?.date == today
        let h = WHealth.cached(today)
        let st = max(h?.steps ?? 0, phoneToday ? (k?.steps ?? 0) : 0)
        s.steps = st
        s.stepGoal = k?.stepGoal
        s.kcalActive = max(h?.active ?? 0, phoneToday ? (k?.active ?? 0) : 0)
        s.kcalBmr = k?.bmr
        if let prog = Store.program(for: today, profile: Store.profile(ctx), ctx: ctx), !prog.blocks.allExercises.isEmpty {
            let st = steps(prog)
            s.program = prog.name
            // short name that fits the corner arc: the program's short name, else the first two words
            let sh = prog.short?.trimmingCharacters(in: .whitespaces) ?? ""
            s.programShort = sh.isEmpty ? (prog.name.count > 13 ? prog.name.split(separator: " ").prefix(2).joined(separator: " ") : nil) : String(sh.prefix(13))
            s.total = st.count
            s.done = st.filter { isDone($0, day) }.count
            s.workoutDone = day?.workoutDone ?? false
        }
        WatchSnap.save(s)
    }

    /// Same order as the iPhone player: sets back to back for single exercises, round by round for supersets
    /// Steps aren't rebuilt unless the program changes; the player calls this on every render
    private static var stepsMemo: [String: (Data, [WStep])] = [:]
    static func steps(_ p: WorkoutProgram) -> [WStep] {
        let data = p.blocksData
        if let m = stepsMemo[p.pid], m.0 == data { return m.1 }
        let st = buildSteps(p)
        if stepsMemo.count > 12 { stepsMemo.removeAll() }
        stepsMemo[p.pid] = (data, st)
        return st
    }
    private static func buildSteps(_ p: WorkoutProgram) -> [WStep] {
        var steps: [WStep] = [], n = 0
        for b in p.blocks {
            if b.kind == .single, let e = b.ex {
                n += 1
                for i in 0..<max(0, e.sets) { steps.append(WStep(ex: e, si: i, of: e.sets, rest: e.rest, label: "#\(n)")) }
            } else if !b.exs.isEmpty {
                n += 1
                let R = max(1, b.rounds)
                for r in 0..<R {
                    for (j, e) in b.exs.enumerated() {
                        steps.append(WStep(ex: e, si: r, of: R, rest: j == b.exs.count - 1 ? b.rest : 0, label: "\(n)\(String(UnicodeScalar(97 + j)!))", tag: b.tag, ss: true))
                    }
                }
            }
        }
        return steps
    }

    static func isDone(_ s: WStep, _ d: DayLog?) -> Bool {
        guard let d else { return false }
        if let f = d.exDone[s.ex.id] { return f }
        let a = d.sets[s.ex.id] ?? []
        return s.si < a.count && a[s.si].done
    }

    /// Suggested weight for this exercise: today's log → earlier set today → last set in history → program weight
    static func suggestedKg(_ ctx: ModelContext, _ s: WStep, date: String, day: DayLog?) -> Double {
        let today = day?.sets[s.ex.id] ?? []
        if s.si < today.count, let k = today[s.si].kg, k > 0 { return k }
        if let k = today.prefix(s.si).last(where: { ($0.kg ?? 0) > 0 })?.kg { return k }
        if let k = PhoneSync.shared.lastKg[s.ex.id], k > 0 { return k }
        return s.ex.kg ?? 0
    }

    static func suggestedReps(_ s: WStep, day: DayLog?) -> Int {
        let a = day?.sets[s.ex.id] ?? []
        if s.si < a.count, let r = a[s.si].reps, r > 0 { return r }
        return max(1, s.ex.reps)
    }

    /// Writes the set as done (same format as Wk.setLog on iPhone)
    static func mark(_ ctx: ModelContext, date: String, pid: String, step s: WStep, kg: Double, reps: Int) {
        let L = Store.day(ctx, date)!
        var S = L.sets
        var arr = S[s.ex.id] ?? []
        while arr.count <= s.si { arr.append(SetLog()) }
        arr[s.si].kg = s.timed ? nil : (kg > 0 ? kg : nil)
        arr[s.si].reps = reps
        arr[s.si].done = true
        S[s.ex.id] = arr; L.sets = S
        if L.exDone[s.ex.id] == false { var X = L.exDone; X.removeValue(forKey: s.ex.id); L.exDone = X }
        try? ctx.save()
        WLogic.publish(ctx)   // complications
        PhoneSync.shared.send(WatchEvent(kind: "set", date: date, eid: s.ex.id, si: s.si, kg: arr[s.si].kg, reps: reps, pid: pid))
    }

    /// Saves the workout; if left unfinished, only exercises with every set done are completed
    static func complete(_ ctx: ModelContext, date: String, prog: WorkoutProgram, seconds: Int?, kcal: Double?) {
        let L = Store.day(ctx, date)!
        let steps = steps(prog)
        let doneIds = Set(prog.blocks.allExercises.map(\.id).filter { id in steps.filter { $0.ex.id == id }.allSatisfy { isDone($0, L) } })
        var X = L.exDone
        for id in doneIds { X[id] = true }
        L.exDone = X
        L.workoutDone = prog.blocks.allExercises.allSatisfy { doneIds.contains($0.id) || L.exDone[$0.id] == true }
        if L.programIdRaw == nil { L.programIdRaw = prog.pid }
        // the watch workout was already written to Health; the duration is set so iPhone doesn't write it again
        if let seconds, seconds > 0, L.workoutSeconds == 0 {
            L.workoutSeconds = min(seconds, 4 * 3600)
            L.workoutKcal = kcal ?? 0
        }
        try? ctx.save()
        WLogic.publish(ctx)   // complications
        PhoneSync.shared.completed(date: date, pid: prog.pid, doneIds: Array(doneIds), workoutDone: L.workoutDone, seconds: seconds, kcal: kcal)
    }

    #if targetEnvironment(simulator)
    /// Sample program to try in the simulator without iCloud data
    static func seedSample(_ ctx: ModelContext) {
        let p = WorkoutProgram(name: tl("Örnek: Üst vücut"), blocks: [
            Block(single: Exercise(name: "Bench press", sets: 3, reps: 10, rest: 90, kg: 60)),
            Block(single: Exercise(name: "Lat pulldown", sets: 3, reps: 12, rest: 60, kg: 45)),
            Block(superset: [Exercise(name: "Omuz press", sets: 2, reps: 12, kg: 14), Exercise(name: "Plank", sets: 2, reps: 45, unit: "sn")], rounds: 2, rest: 60),
        ])
        ctx.insert(p)
        let L = Store.day(ctx, DayKey.today)!
        L.programIdRaw = p.pid
        try? ctx.save()
        WLogic.publish(ctx)   // complications
    }
    #endif
}

extension Double {
    var kgText: String { formatted(.number.precision(.fractionLength(0...2)).locale(.current)) }
}

/// Sync with iPhone: gets data from iPhone, sends completed sets and workouts back
@MainActor @Observable
final class PhoneSync: NSObject, WCSessionDelegate {
    static let shared = PhoneSync()
    @ObservationIgnored private var container: ModelContainer?
    /// Last sync time (shown on screen)
    var syncedAt: Date? = UserDefaults.standard.object(forKey: "wsync.at") as? Date
    var lastKg: [String: Double] = PhoneSync.load("wsync.kg") ?? [:]
    var lastReps: [String: Int] = PhoneSync.load("wsync.reps") ?? [:]
    var sugKg: [String: Double] = PhoneSync.load("wsync.sug") ?? [:]
    /// Intermittent fasting schedule (nil when off on iPhone)
    var fast: FastPlan? = PhoneSync.load("wsync.fast")
    /// Today's calories (for the nutrition complication)
    struct Kcal: Codable, Equatable {
        var date: String; var target: Double; var eaten: Double
        // corner complications; missing in old records
        var bmr: Double? = nil; var active: Double? = nil; var steps: Int? = nil; var stepGoal: Int? = nil
    }
    var kcal: Kcal? = PhoneSync.load("wsync.kcal")
    /// Open workout on iPhone: "day|program"
    var live: String? = UserDefaults.standard.string(forKey: "wsync.live")
    @ObservationIgnored private var lastSyncAsk = Date.distantPast

    /// Change made on the watch that iPhone's context doesn't reflect yet
    struct Pending: Codable {
        var kind: String          // "complete" | "fastEnd" | "fastSkip"
        var date: String
        var ids: [String] = []
        var on = true             // complete: workoutDone · fastSkip: skipped or not
        var at = Date()
    }
    /// Event id → pending change; deleted once iPhone's context reflects it
    @ObservationIgnored private var pending: [String: Pending] = PhoneSync.load("wsync.pending") ?? [:]
    /// Events produced before the session activates wait here
    @ObservationIgnored private var outbox: [[String: Any]] = (UserDefaults.standard.array(forKey: "wsync.outbox") as? [[String: Any]]) ?? []

    nonisolated private static func load<T: Decodable>(_ k: String) -> T? { UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    nonisolated private static func store<T: Encodable>(_ v: T, _ k: String) { if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: k) } }

    func activate(_ c: ModelContainer) {
        container = c
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // live session state to iPhone: queued without the phone, sent once connected
        LiveBridge.shared.transport = { d in
            let s = WCSession.default
            guard s.activationState == .activated else { return }
            let msg: [String: Any] = ["L": d]
            if s.isReachable { s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) } }
            else {
                // while disconnected only the latest state waits; older ones are dropped from the queue
                for t in s.outstandingUserInfoTransfers where t.userInfo["L"] != nil { t.cancel() }
                s.transferUserInfo(msg)
            }
        }
    }

    /// Sends the event with an id and an explicit value; iPhone doesn't process the same id twice
    @discardableResult
    func send(_ e: WatchEvent, on: Bool? = nil) -> String {
        let id = UUID().uuidString
        guard WCSession.isSupported(), let d = try? JSONEncoder().encode(e) else { return id }
        var msg: [String: Any] = ["d": d, "id": id]
        if let on { msg["on"] = on }
        deliver(msg)
        return id
    }

    private func deliver(_ msg: [String: Any]) {
        let s = WCSession.default
        // don't lose events before the session opens: queue them and send once active
        guard s.activationState == .activated else {
            outbox.append(msg); UserDefaults.standard.set(outbox, forKey: "wsync.outbox")
            return
        }
        // immediately if iPhone is reachable; otherwise queued and handled when the iPhone app opens
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) }
        } else {
            s.transferUserInfo(msg)
        }
    }

    private func flushOutbox() {
        guard WCSession.default.activationState == .activated, !outbox.isEmpty else { return }
        let q = outbox
        outbox = []; UserDefaults.standard.removeObject(forKey: "wsync.outbox")
        for m in q { deliver(m) }
    }

    private func remember(_ id: String, _ p: Pending) {
        pending[id] = p
        Self.store(pending, "wsync.pending")
    }

    /// Workout done: kept on the watch until iPhone's context reflects it
    func completed(date: String, pid: String, doneIds: [String], workoutDone: Bool, seconds: Int?, kcal: Double?) {
        let id = send(WatchEvent(kind: "complete", date: date, pid: pid, doneIds: doneIds, seconds: seconds, kcal: kcal))
        remember(id, Pending(kind: "complete", date: date, ids: doneIds, on: workoutDone))
    }

    /// A program picked on the watch is written to today and sent to iPhone; both devices show the same program even if unfinished
    func pick(_ ctx: ModelContext, date: String, pid: String) {
        let profile = Store.profile(ctx)
        guard Store.program(for: date, profile: profile, ctx: ctx)?.pid != pid, let L = Store.day(ctx, date) else { return }
        L.programIdRaw = pid
        try? ctx.save()
        WLogic.publish(ctx)
        send(WatchEvent(kind: "pick", date: date, pid: pid))
    }

    /// Fasting: end now / skip the next fast — shows on the watch immediately and goes to iPhone
    func fastEnd(_ key: String) {
        let now = Date()
        fast?.endEarly(key, at: now); store()   // the eating window starts now and the next fast shifts
        let id = send(WatchEvent(kind: "fastEnd", date: key, pid: key, at: now))
        remember(id, Pending(kind: "fastEnd", date: key, at: now))
    }
    /// Sent as an explicit value (not a toggle); not undone by a duplicate delivery
    func fastSkip(_ key: String) {
        let on = !(fast?.skipped.contains(key) ?? false)
        if on { fast?.skipped.insert(key) } else { fast?.skipped.remove(key) }
        store()
        let id = send(WatchEvent(kind: "fastSkip", date: key, pid: key), on: on)
        // an older pending skip/undo for the same fast is void
        for (k, p) in pending where p.kind == "fastSkip" && p.date == key { pending.removeValue(forKey: k) }
        remember(id, Pending(kind: "fastSkip", date: key, on: on))
    }
    private func store() {
        if let f = fast { Self.store(f, "wsync.fast") }
        if let ctx = container?.mainContext { WLogic.publish(ctx) }   // fasting complication
    }

    /// Last processed context: the database isn't touched if the same one arrives again
    @ObservationIgnored private var lastApplied: Data?
    private func apply(_ data: Data) {
        guard data != lastApplied else { return }
        guard let ctx = container?.mainContext, let p = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        lastApplied = data
        // the open workout's program and day aren't deleted; the player must not crash on a deleted record
        let owner = WatchWorkout.shared.owner ?? ""
        // very old (2 days) pending items are dropped: iPhone didn't process or rejected them
        let cutoff = Date().addingTimeInterval(-2 * 86400)
        pending = pending.filter { $0.value.at > cutoff }
        let prof = Store.profile(ctx)
        if prof.scheduleData != p.schedule { prof.scheduleData = p.schedule }
        let existing = Dictionary(Store.programs(ctx, includeArchived: true).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let incoming = Set(p.programs.map(\.pid))
        for x in p.programs {
            let w = existing[x.pid] ?? { let n = WorkoutProgram(pid: x.pid, name: x.name); ctx.insert(n); return n }()
            // only changed fields are written so screens aren't redrawn from scratch on every sync
            if w.name != x.name { w.name = x.name }
            if w.archived != x.archived { w.archived = x.archived }
            if w.short != x.short { w.short = x.short }
            if w.blocksData != x.blocks { w.blocksData = x.blocks }
        }
        // a day copy created on the watch (machine taken) isn't deleted until iPhone processes it
        let todayCopy = "@\(DayKey.today)"
        for (pid, w) in existing where !incoming.contains(pid) && !owner.hasSuffix(pid) && !pid.hasSuffix(todayCopy) { ctx.delete(w) }
        for d in p.days {
            let L = Store.day(ctx, d.date)!
            if L.programIdRaw != d.programIdRaw { L.programIdRaw = d.programIdRaw }
            // don't lose sets marked on the watch that haven't reached iPhone yet
            let remote = (try? JSONDecoder().decode([String: [SetLog]].self, from: d.sets)) ?? [:]
            var flags = (try? JSONDecoder().decode([String: Bool].self, from: d.exDone)) ?? [:]
            let merged = DayMerge.sets(remote, L.sets)
            if merged != L.sets { L.sets = merged }
            var done = d.workoutDone
            // a "done" that hasn't reached iPhone isn't undone; the pending item is deleted once reflected
            for (k, x) in pending where x.kind == "complete" && x.date == d.date {
                if x.ids.allSatisfy({ flags[$0] == true }) && (!x.on || d.workoutDone) { pending.removeValue(forKey: k); continue }
                for id in x.ids { flags[id] = true }
                done = done || x.on
            }
            if L.exDone != flags { L.exDone = flags }
            if L.workoutDone != done { L.workoutDone = done }
        }
        // old days don't pile up on the watch
        let keep = Set(p.days.map(\.date))
        let lo = p.days.map(\.date).min() ?? p.today
        for L in (try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date < lo }))) ?? [] where !keep.contains(L.date) && !owner.hasPrefix(L.date) { ctx.delete(L) }
        try? ctx.save()
        WLogic.publish(ctx)   // complications
        // fasting: pending end/skip changes are kept until iPhone reflects them
        var f = p.fast
        if f != nil {
            for (k, x) in pending where x.kind == "fastEnd" || x.kind == "fastSkip" {
                if x.kind == "fastEnd" {
                    if f?.endedAt[x.date] != nil { pending.removeValue(forKey: k) } else { f?.endEarly(x.date, at: x.at) }
                } else {
                    if (f?.skipped.contains(x.date) ?? false) == x.on { pending.removeValue(forKey: k) }
                    else if x.on { f?.skipped.insert(x.date) } else { f?.skipped.remove(x.date) }
                }
            }
        } else {
            pending = pending.filter { $0.value.kind == "complete" }   // fasting was turned off on iPhone
        }
        Self.store(pending, "wsync.pending")
        lastKg = p.lastKg; lastReps = p.lastReps; sugKg = p.sugKg; fast = f
        if let f { Self.store(f, "wsync.fast") } else { UserDefaults.standard.removeObject(forKey: "wsync.fast") }
        Self.store(p.lastKg, "wsync.kg"); Self.store(p.lastReps, "wsync.reps"); Self.store(p.sugKg, "wsync.sug")
        if let t = p.kcalTarget {
            kcal = Kcal(date: p.today, target: t, eaten: p.kcalEaten ?? 0, bmr: p.kcalBmr, active: p.kcalActive, steps: p.steps, stepGoal: p.stepGoal)
            Self.store(kcal, "wsync.kcal")
            WLogic.publish(ctx)   // beslenme komplikasyonu
        }
        // a new workout started on iPhone: notice on the watch
        if p.live != live {
            let old = live
            live = p.live
            if let l = p.live { UserDefaults.standard.set(l, forKey: "wsync.live") } else { UserDefaults.standard.removeObject(forKey: "wsync.live") }
            if let l = p.live, l != old { WLiveNotice.post(l, ctx: ctx) }
        }
        syncedAt = Date()
        UserDefaults.standard.set(syncedAt, forKey: "wsync.at")
    }

    /// Ask iPhone for the latest state when the watch opens (don't miss plan changes); at most every 20 s
    func requestSync() {
        guard Date().timeIntervalSince(lastSyncAsk) > 20, WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        lastSyncAsk = Date()
        send(WatchEvent(kind: "sync", date: DayKey.today))
    }

    /// The open iPhone workout if it's for today (day, program)
    var liveToday: (date: String, pid: String)? {
        guard let l = live else { return nil }
        let a = l.split(separator: "|", maxSplits: 1).map(String.init)
        guard a.count == 2, a[0] == DayKey.today else { return nil }
        return (a[0], a[1])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let d = session.receivedApplicationContext["p"] as? Data
        Task { @MainActor in
            self.flushOutbox()
            if let d { self.apply(d) }
            self.requestSync()
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestSync() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let d = applicationContext["p"] as? Data else { return }
        Task { @MainActor in self.apply(d) }
    }
    /// While iPhone is reachable the context also arrives immediately (sendMessage) so plan changes aren't delayed
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let L = message["L"] as? Data { Task { @MainActor in LiveBridge.shared.receive(L) }; return }
        guard let d = message["p"] as? Data else { return }
        Task { @MainActor in self.apply(d) }
    }
    /// Priority delivery for complications (transferCurrentComplicationUserInfo)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let L = userInfo["L"] as? Data { Task { @MainActor in LiveBridge.shared.receive(L) }; return }
        guard let d = userInfo["p"] as? Data else { return }
        Task { @MainActor in self.apply(d) }
    }
}

/// Exercise visuals: two frames (start/end) and a "how to" — same source as iPhone
/// Called from the UI only; the cache lives on the main actor
@MainActor
enum WMotion {
    private struct Media: Decodable { let s: String; let tr: String }
    private static let media: [String: Media] = {
        guard let u = Bundle.main.url(forResource: "ex-media", withExtension: "json"), let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: Media].self, from: d)) ?? [:]
    }()
    private static let aliases: [String: String] = {
        struct Lib: Decodable { struct E: Decodable { let name: String; let tr: [String]? }; let exercises: [E] }
        guard let u = Bundle.main.url(forResource: "exercise-library", withExtension: "json"), let d = try? Data(contentsOf: u),
              let lib = try? JSONDecoder().decode(Lib.self, from: d) else { return [:] }
        var m: [String: String] = [:]
        for e in lib.exercises { for a in e.tr ?? [] { m[TextNorm.norm(a)] = TextNorm.norm(e.name) } }
        return m
    }()
    private static let mk: [String: String] = [
        "barfiks": "pull-ups", "pull up": "pull-ups", "pull ups": "pull-ups", "pullup": "pull-ups", "barfix": "pull-ups",
        "dumbbell fly": "dumbbell-chest-fly", "dumbbell chest fly": "dumbbell-chest-fly", "dambil acis": "dumbbell-chest-fly",
        "dambil fly": "dumbbell-chest-fly", "dumbell fly": "dumbbell-chest-fly",
    ]
    private static func entry(_ name: String) -> Media? {
        let n = TextNorm.norm(name)
        return media[n] ?? aliases[n].flatMap { media[$0] }
    }
    /// MoveKit Complete Pack: English library name → slug (mk-map.json, same as iPhone)
    private static let mkMap: [String: String] = {
        guard let u = Bundle.main.url(forResource: "mk-map", withExtension: "json"), let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in m { out[TextNorm.norm(k)] = v }
        return out
    }()
    private static var cache: [String: UIImage] = [:]
    private static var seqCache: [String: [UIImage]] = [:]
    private static func image(_ file: String) -> UIImage? {
        if let i = cache[file] { return i }
        guard let u = Bundle.main.url(forResource: file, withExtension: "jpg"), let i = UIImage(contentsOfFile: u.path) else { return nil }
        cache[file] = i
        return i
    }
    /// Same priority as iPhone: the 3D MoveKit movement if present (6 fps frames from the video), otherwise the photo pair
    static func frames(_ name: String) -> [UIImage] {
        let n = TextNorm.norm(name)
        if !noMoveKit, let s = mk[n] ?? mkMap[n] ?? aliases[n].flatMap({ mkMap[$0] }) ?? mk.first(where: { n.hasPrefix($0.key + " ") })?.value {
            if let c = seqCache[s] { return c }
            var arr: [UIImage] = []
            for k in 1...99 {
                guard let u = Bundle.main.url(forResource: String(format: "mkw-%@-%02d", s, k), withExtension: "jpg"), let i = UIImage(contentsOfFile: u.path) else { break }
                arr.append(i)
            }
            // watch memory: frames of at most two exercises are kept
            if !arr.isEmpty { if seqCache.count >= 2 { seqCache.removeAll() }; seqCache[s] = arr; return arr }
            if let i = image("mk-\(s)") { return [i] }
        }
        if let m = entry(name) { return [0, 1].compactMap { image("\(m.s)-\($0)") } }
        return []
    }
    /// Whether it's a MoveKit visual (inverted onto black on the watch)
    /// Screenshots / open source: MoveKit frames aren't used
    static let noMoveKit = ProcessInfo.processInfo.arguments.contains("-noMoveKit")
    static func isMK(_ name: String) -> Bool {
        let n = TextNorm.norm(name)
        if noMoveKit { return false }
        return (mk[n] ?? mkMap[n] ?? aliases[n].flatMap({ mkMap[$0] }) ?? mk.first(where: { n.hasPrefix($0.key + " ") })?.value) != nil
    }
    /// List thumbnail: first frame only (doesn't load every video frame)
    static func thumb(_ name: String) -> UIImage? {
        let n = TextNorm.norm(name)
        if let s = mk[n] ?? mkMap[n] ?? aliases[n].flatMap({ mkMap[$0] }) ?? mk.first(where: { n.hasPrefix($0.key + " ") })?.value {
            if let c = seqCache[s]?.first { return c }
            if let i = image(String(format: "mkw-%@-%02d", s, 8)) ?? image(String(format: "mkw-%@-%02d", s, 1)) { return i }
        }
        if let m = entry(name) { return image("\(m.s)-0") }
        return nil
    }
    static func howTo(_ name: String) -> String? { entry(name)?.tr }
}


/// Local notification on the watch for a workout started on iPhone
@MainActor
enum WLiveNotice {
    static func requestAuth() {
        // no permission prompt interrupting screenshots
        guard !ProcessInfo.processInfo.arguments.contains("-shot") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func post(_ live: String, ctx: ModelContext) {
        let a = live.split(separator: "|", maxSplits: 1).map(String.init)
        guard a.count == 2, a[0] == DayKey.today, !WatchWorkout.shared.running else { return }
        let pid = a[1]
        let name = (try? ctx.fetch(FetchDescriptor<WorkoutProgram>(predicate: #Predicate { $0.pid == pid })))?.first?.name ?? ""
        let c = UNMutableNotificationContent()
        c.title = String(localized: "iPhone'da antrenman başladı")
        c.body = name.isEmpty ? String(localized: "Saatte açmak için dokun.") : String(localized: "\(name) · saatte açmak için dokun.")
        c.sound = .default
        c.userInfo = ["live": live]
        let r = UNNotificationRequest(identifier: "live-" + live, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(r)
    }
}
