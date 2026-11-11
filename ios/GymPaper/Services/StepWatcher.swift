import UserNotifications
import WatchConnectivity
import SwiftData
import GymPaperKit
import Foundation
import HealthKit
import CoreMotion
import UIKit
import BackgroundTasks
import os

extension Notification.Name {
    /// Today's step count changed (object: Int) — single observer in StepWatcher
    static let gymPaperStepsToday = Notification.Name("gympaper.stepsToday")
}

/// Keeps the steps widget current with the app closed: HealthKit background delivery is registered at launch
/// before any await. Health data can't be read while the device is locked; then it's skipped.
/// Single HKObserverQuery for steps; HealthService is fed from here too
final class StepWatcher: @unchecked Sendable {
    static let shared = StepWatcher()
    private let store = HKHealthStore()
    /// Mutated only from the main actor
    @MainActor private var started = false

    @MainActor func start() {
        #if !LITE
        guard HKHealthStore.isHealthDataAvailable(), !started,
              UserDefaults.standard.bool(forKey: "healthAsked") else { return }
        started = true
        let type = HKQuantityType(.stepCount)
        let q = HKObserverQuery(sampleType: type, predicate: nil) { [store] _, done, error in
            guard error == nil else { done(); return }
            let pred = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: nil)
            let stats = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, r, _ in
                if let n = r?.sumQuantity()?.doubleValue(for: .count()) {
                    WidgetSync.pushSteps(Int(n))
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .gymPaperStepsToday, object: Int(n)) }
                }
                done()
            }
            store.execute(stats)
        }
        store.execute(q)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        // The steps widget refreshes without opening the app: it reads CMPedometer; permission can only be requested in the app
        if CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .notDetermined {
            let p = CMPedometer()
            p.queryPedometerData(from: Calendar.current.startOfDay(for: .now), to: .now) { _, _ in withExtendedLifetime(p) {} }
        }
        #endif
    }
}

/// Keeps the steps widget fresh without opening the app: reads today's steps in the background as often as iOS allows
/// (15 min at the earliest). Health data can't be read while locked; it waits for the next chance then.
enum StepRefresh {
    static let id = "\(AppConfig.bundleBase).steps"
    static func schedule() {
        #if !LITE
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(r)
        #endif
    }
    @MainActor static func socialPush(_ n: Int) async { await SocialService.shared.push([DayKey.today: n]) }
    static func run() async {
        #if !LITE
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let n: Double? = await withCheckedContinuation { c in
            let pred = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: nil)
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: pred, options: .cumulativeSum) { _, r, _ in
                c.resume(returning: r?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(q)
        }
        if let n {
            WidgetSync.pushSteps(Int(n))
            // Team ranking: today's steps are sent from the background too (if joined)
            if AppTab.socialEnabled { await socialPush(Int(n)) }
        }
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        StepWatcher.shared.start()
        StepRefresh.schedule()
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    /// While the app is open: rest is already signalled with a beep + haptic; other reminders show as banners
    /// Not bound to the main actor, as the protocol requires
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        n.request.identifier.hasPrefix("gympaper.rest") || n.request.identifier.hasPrefix("gympaper.ntf.goal") ? [] : [.banner, .list, .sound]
    }
    /// The Lock Screen live activity must not linger for hours after the app closes
    func applicationWillTerminate(_ application: UIApplication) {
        LiveSession.endAllNow()
    }
}

// MARK: - Apple Watch sync (WatchConnectivity)

/// The watch only tracks workouts; it gets its data from iPhone and sends completed sets back right away.
/// iPhone writes them to its database, and iCloud carries them to other devices.
@MainActor
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private var container: ModelContainer?
    private var lastSent: Data?
    private let log = Logger(subsystem: AppConfig.bundleBase, category: "watch")
    /// Ids of the latest events from the watch: duplicate deliveries aren't processed twice
    private var seen: [String] = UserDefaults.standard.stringArray(forKey: "wsync.seen") ?? []
    /// Open workout on iPhone ("day|program"); the watch shows a notice
    private var live: String?
    func setLive(_ s: String?) {
        guard s != live else { return }
        live = s; push()
    }

    func activate(_ c: ModelContainer) {
        container = c
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // live session state to the watch: immediately if it's reachable, queued otherwise
        LiveBridge.shared.transport = { d in
            let s = WCSession.default
            guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
            let msg: [String: Any] = ["L": d]
            if s.isReachable { s.sendMessage(msg, replyHandler: nil) { _ in s.transferUserInfo(msg) } }
            else {
                // while disconnected only the latest state waits; older ones are dropped from the queue
                for t in s.outstandingUserInfoTransfers where t.userInfo["L"] != nil { t.cancel() }
                s.transferUserInfo(msg)
            }
        }
    }

    /// Sends current workout data to the watch (skipped when unchanged).
    /// direct: if the watch is reachable, the context also goes as a message so plan changes show up immediately
    func push(direct: Bool = false) {
        guard let ctx = container?.mainContext, WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let today = DayKey.today
        let p = Store.profile(ctx)
        // this week's days (Monday → Sunday)
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let week = (0..<7).map { DayKey.shift(monday, days: $0) }
        var progs = Store.programs(ctx)
        for k in week {
            if let tp = Store.program(for: k, profile: p, ctx: ctx), !progs.contains(where: { $0.pid == tp.pid }) { progs.append(tp) }
        }
        let lo = week[0], hi = week[6]
        let days = (try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= lo && $0.date <= hi }))) ?? []
        var last: [String: Double] = [:], lastReps: [String: Int] = [:], sug: [String: Double] = [:]
        let exs = progs.flatMap { $0.blocks.allExercises }
        let ids = Set(exs.map(\.id))
        var d = FetchDescriptor<DayLog>(predicate: #Predicate { $0.date < today }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 120
        // last sets and suggestions come from the same 120-day pass; the whole history isn't scanned on every save
        var lastSets: [String: [SetLog]] = [:]
        for L in (try? ctx.fetch(d)) ?? [] {
            for (eid, arr) in L.sets where ids.contains(eid) && lastSets[eid] == nil {
                let done = arr.filter { $0.done && ($0.kg ?? 0) > 0 }
                guard let hit = done.last else { continue }
                lastSets[eid] = done; last[eid] = hit.kg; lastReps[eid] = hit.reps
            }
        }
        // suggestion from the same source as iPhone (GymPaperKit Progression)
        for e in exs where e.unit == "tekrar" && sug[e.id] == nil && lastSets[e.id] != nil {
            if let r = WkProgress.suggestKg(ctx, e, date: today) { sug[e.id] = r.kg }
        }
        let payload = WatchPayload(
            today: today, schedule: p.scheduleData,
            programs: progs.map { .init(pid: $0.pid, name: $0.name, blocks: $0.blocksData, archived: $0.archived, short: $0.short) },
            days: week.compactMap { k in days.day(k).map { .init(date: k, programIdRaw: $0.programIdRaw, sets: $0.setsData, exDone: $0.exDoneData, workoutDone: $0.workoutDone) } },
            lastKg: last, lastReps: lastReps, sugKg: sug, fast: p.fastOn ? p.fast : nil)
        // nutrition complication: today's calories from the widget snapshot (eaten is 0 if it belongs to another day)
        var payload2 = payload
        if let snap = SharedStore.shared.read() {
            payload2.kcalTarget = snap.kcalTarget.rounded()
            payload2.kcalEaten = snap.date == today ? snap.kcalEaten.rounded() : 0
            // watch corner complications: steps (the watch takes the larger of its own Health data), active, basal
            payload2.steps = snap.date == today ? snap.steps : 0
            payload2.stepGoal = snap.stepGoal
            payload2.kcalActive = snap.date == today ? snap.kcalActive.rounded() : 0
        }
        payload2.kcalBmr = WidgetSync.lastBmr.map { $0.rounded() }
        payload2.live = live
        guard let data = try? JSONEncoder().encode(payload2), data != lastSent else { return }
        let prev = lastSent.flatMap { try? JSONDecoder().decode(WatchPayload.self, from: $0) }
        // marked only after a successful send; on error the next push retries
        do {
            try s.updateApplicationContext(["p": data])
            lastSent = data
            if direct || prev?.today != payload2.today || prev?.days.map(\.programIdRaw) != payload2.days.map(\.programIdRaw) || prev?.schedule != payload2.schedule,
               s.isReachable {
                s.sendMessage(["p": data], replyHandler: nil, errorHandler: nil)
            }
            // priority delivery when a complication is on the watch face; only when calories or the day change (daily budget is limited)
            let changed = prev?.today != payload2.today || prev?.kcalEaten != payload2.kcalEaten || prev?.kcalTarget != payload2.kcalTarget
                || prev?.kcalBmr != payload2.kcalBmr || prev?.stepGoal != payload2.stepGoal
            if changed, s.isComplicationEnabled, s.remainingComplicationUserInfoTransfers > 0 {
                s.transferCurrentComplicationUserInfo(["p": data])
            }
        } catch {
            log.error("Saate bağlam gönderilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Event from the watch: write the set or save the workout
    private func apply(_ msg: [String: Any]) {
        guard let data = msg["d"] as? Data, let ctx = container?.mainContext,
              let e = try? JSONDecoder().decode(WatchEvent.self, from: data) else { return }
        // if sendMessage fails and the event arrives again via transferUserInfo, don't process it twice
        if let id = msg["id"] as? String {
            guard !seen.contains(id) else { return }
            seen.append(id)
            if seen.count > 200 { seen.removeFirst(seen.count - 200) }
            UserDefaults.standard.set(seen, forKey: "wsync.seen")
        }
        switch e.kind {
        case "set":
            // only exercises of programs that exist on iPhone are written (the watch's sample program stays out)
            guard let eid = e.eid, let si = e.si, let prog = Wk.program(e.pid, ctx), prog.blocks.allExercises.contains(where: { $0.id == eid }) else { return }
            Wk.setLog(ctx, date: e.date, eid: eid, index: si) { s in s.kg = e.kg; s.reps = e.reps; s.done = true }
            Wk.rememberLoad(prog, eid: eid, kg: e.kg)   // weight entered on the watch is written to the program too
        case "complete":
            guard let prog = Wk.program(e.pid, ctx) else { return }
            let L = Store.day(ctx, e.date)!
            let doneIds = Set(e.doneIds ?? [])
            var X = L.exDone
            for id in doneIds { X[id] = true }
            L.exDone = X
            L.workoutDone = prog.blocks.allExercises.allSatisfy { doneIds.contains($0.id) || L.exDone[$0.id] == true }
            if L.programIdRaw == nil { L.programIdRaw = prog.pid }
            // the watch already wrote the workout to Health; iPhone doesn't write it again
            if let sec = e.seconds, sec > 0, L.workoutSeconds == 0 {
                L.workoutSeconds = min(sec, 4 * 3600)
                // calories measured by Health aren't written to iCloud; the app's own MET estimate is used
                L.workoutKcal = CalorieEngine.workoutKcal(minutes: Double(L.workoutSeconds) / 60,
                                                          weightKg: Store.latestWeight(ctx) ?? Store.profile(ctx).startKg ?? 75)
            }
            if (e.seconds ?? 0) > 0 {   // only if the watch really wrote to Health
                UserDefaults.standard.set(true, forKey: "wk.hk.\(e.date)")
                L.hkSaved = true   // the watch wrote it; let the other devices know
            }
            WkSessionClock.clear(e.date)
        case "fastEnd":
            // "End fast" from the watch: the fast that started that day ends now
            let p = Store.profile(ctx); var f = p.fast
            if let k = e.pid { f.endEarly(k, at: e.at ?? Date()) }; p.fast = f   // use the watch's time on delayed delivery; the next fast shifts
        case "fastSkip":
            let p = Store.profile(ctx); var f = p.fast
            // newer watches send an explicit value; toggle for older ones (no value)
            if let k = e.pid {
                let on = msg["on"] as? Bool ?? !f.skipped.contains(k)
                if on { f.skipped.insert(k) } else { f.skipped.remove(k) }
            }
            p.fast = f
        case "pick":
            // another program was picked and started on the watch: it becomes today's workout (this day only)
            guard let pid = e.pid, Wk.program(pid, ctx) != nil else { return }
            let prof = Store.profile(ctx)
            if Store.day(ctx, e.date, create: false)?.workoutDone != true, Store.program(for: e.date, profile: prof, ctx: ctx)?.pid != pid {
                Wk.assignDay(ctx, prof, date: e.date, pid: pid, repeats: false)
            }
        case "swap":
            // "machine taken → alternative" on the watch: same swap here (same ids)
            guard let eid = e.eid, let pid = e.pid, let name = e.name else { return }
            Store.swapForDay(ctx, date: e.date, pid: pid, eid: eid, doneSets: e.si ?? 0, to: name, muscle: e.muscle ?? "")
        case "sync":
            // watch opened or entered the plan screen: resend the latest state (even if unchanged)
            lastSent = nil
        default: return
        }
        Store.save(ctx)
        push(direct: true)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.lastSent = nil; self.push() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSent = nil; self.push() }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let L = userInfo["L"] as? Data { Task { @MainActor in LiveBridge.shared.receive(L) }; return }
        guard let m = Self.event(userInfo) else { return }
        Task { @MainActor in self.apply(m.dict) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let L = message["L"] as? Data { Task { @MainActor in LiveBridge.shared.receive(L) }; return }
        guard let m = Self.event(message) else { return }
        Task { @MainActor in self.apply(m.dict) }
    }
    /// Only known fields are taken so the dictionary can cross actors
    private struct Event: @unchecked Sendable { let dict: [String: Any] }
    nonisolated private static func event(_ m: [String: Any]) -> Event? {
        guard let d = m["d"] as? Data else { return nil }
        var x: [String: Any] = ["d": d]
        if let id = m["id"] as? String { x["id"] = id }
        if let on = m["on"] as? Bool { x["on"] = on }
        return Event(dict: x)
    }
}
