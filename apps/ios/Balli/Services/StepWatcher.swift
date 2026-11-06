import UserNotifications
import WatchConnectivity
import SwiftData
import BalliKit
import Foundation
import HealthKit
import CoreMotion
import UIKit
import BackgroundTasks
import os

extension Notification.Name {
    /// Bugünün adım sayısı değişti (object: Int) — tek gözlemci StepWatcher'da (LA-12)
    static let balliStepsToday = Notification.Name("balli.stepsToday")
}

/// Uygulama kapalıyken de adım widget'ı güncel kalsın: HealthKit arka plan teslimi açılışta,
/// hiçbir await'ten önce kaydedilir (WG-01). Cihaz kilitliyken Sağlık verisi okunamaz; bu durumda atlanır.
/// Adımlar için tek HKObserverQuery; HealthService de buradan beslenir (LA-12)
final class StepWatcher: @unchecked Sendable {
    static let shared = StepWatcher()
    private let store = HKHealthStore()
    /// Yalnız ana aktörden değişir (SC-11)
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
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .balliStepsToday, object: Int(n)) }
                }
                done()
            }
            store.execute(stats)
        }
        store.execute(q)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        // Adım widget'ı uygulama açılmadan kendini yenilesin: widget CMPedometer'dan okur; izin yalnız uygulamada istenebilir (WG-11)
        if CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .notDetermined {
            let p = CMPedometer()
            p.queryPedometerData(from: Calendar.current.startOfDay(for: .now), to: .now) { _, _ in withExtendedLifetime(p) {} }
        }
        #endif
    }
}

/// Adım widget'ı uygulama açılmadan da tazelensin: iOS'un izin verdiği aralıklarla (en erken 15 dk) arka planda
/// bugünün adımını okur. Cihaz kilitliyken Sağlık verisi okunamaz; o zaman bir sonraki fırsata kalır (WG-10)
enum StepRefresh {
    static let id = "com.metehankaya.balli.steps"
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
            // Sosyal sıralama: arka planda da bugünün adımı gönderilsin (katıldıysa)
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
    /// Uygulama açıkken: dinlenme zaten bip + titreşimle bildirilir; diğer hatırlatmalar üstte görünür
    /// Protokol gereği ana aktöre bağlı değil (SC-10)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        n.request.identifier.hasPrefix("balli.rest") || n.request.identifier.hasPrefix("balli.ntf.goal") ? [] : [.banner, .list, .sound]
    }
    /// Uygulama kapatılınca kilit ekranındaki canlı etkinlik saatlerce kalmasın (CR-36)
    func applicationWillTerminate(_ application: UIApplication) {
        LiveSession.endAllNow()
    }
}

// MARK: - Apple Watch eşitlemesi (WatchConnectivity)

/// Saat yalnız antrenman takibi yapar; verisini iPhone'dan alır, tamamlanan setleri anında iPhone'a yollar.
/// iPhone kaydı kendi veritabanına yazar, iCloud ile diğer cihazlara oradan gider.
@MainActor
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private var container: ModelContainer?
    private var lastSent: Data?
    private let log = Logger(subsystem: "com.metehankaya.balli", category: "watch")
    /// Saatten gelen son olay kimlikleri: çift teslim ikinci kez işlenmez (WT-11)
    private var seen: [String] = UserDefaults.standard.stringArray(forKey: "wsync.seen") ?? []
    /// iPhone'da açık antrenman ("gün|program"); saat bildirim gösterir (4 Kas)
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
    }

    /// Saate güncel antrenman verisini yollar (değişmediyse yollamaz).
    /// direct: saat açıksa bağlam ayrıca mesajla da gider, plan değişikliği hemen görünür (WT-15)
    func push(direct: Bool = false) {
        guard let ctx = container?.mainContext, WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let today = DayKey.today
        let p = Store.profile(ctx)
        // Bu haftanın günleri (pazartesi → pazar)
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
        // Son setler ve öneri aynı 120 günlük döngüden; her kayıtta tüm geçmiş taranmaz (PF-01)
        var lastSets: [String: [SetLog]] = [:]
        for L in (try? ctx.fetch(d)) ?? [] {
            for (eid, arr) in L.sets where ids.contains(eid) && lastSets[eid] == nil {
                let done = arr.filter { $0.done && ($0.kg ?? 0) > 0 }
                guard let hit = done.last else { continue }
                lastSets[eid] = done; last[eid] = hit.kg; lastReps[eid] = hit.reps
            }
        }
        for e in exs where e.unit == "tekrar" && sug[e.id] == nil {
            guard let sets = lastSets[e.id] else { continue }
            let top = sets.compactMap(\.kg).max() ?? 0
            let hit = sets.count >= max(1, e.sets) && sets.allSatisfy { ($0.reps ?? e.reps) >= e.reps }
            let inc = ["bacak", "kalca", "baldir"].contains(TextNorm.norm(e.muscle)) ? 5.0 : 2.5
            sug[e.id] = hit ? top + inc : top
        }
        let payload = WatchPayload(
            today: today, schedule: p.scheduleData,
            programs: progs.map { .init(pid: $0.pid, name: $0.name, blocks: $0.blocksData, archived: $0.archived, short: $0.short) },
            days: week.compactMap { k in days.day(k).map { .init(date: k, programIdRaw: $0.programIdRaw, sets: $0.setsData, exDone: $0.exDoneData, workoutDone: $0.workoutDone) } },
            lastKg: last, lastReps: lastReps, sugKg: sug, fast: p.fastOn ? p.fast : nil)
        // Beslenme komplikasyonu: widget anlık durumundaki bugünkü kalori (başka güne aitse yenen 0)
        var payload2 = payload
        if let snap = SharedStore.shared.read() {
            payload2.kcalTarget = snap.kcalTarget.rounded()
            payload2.kcalEaten = snap.date == today ? snap.kcalEaten.rounded() : 0
            // Saat köşe göstergeleri: adım (saat kendi Sağlık verisiyle büyüğünü alır), aktif kalori, bazal (WC-01…03)
            payload2.steps = snap.date == today ? snap.steps : 0
            payload2.stepGoal = snap.stepGoal
            payload2.kcalActive = snap.date == today ? snap.kcalActive.rounded() : 0
        }
        payload2.kcalBmr = WidgetSync.lastBmr.map { $0.rounded() }
        payload2.live = live
        guard let data = try? JSONEncoder().encode(payload2), data != lastSent else { return }
        let prev = lastSent.flatMap { try? JSONDecoder().decode(WatchPayload.self, from: $0) }
        // Yalnız başarılı gönderimden sonra işaretlenir; hata olursa sonraki push yeniden dener (WT-12)
        do {
            try s.updateApplicationContext(["p": data])
            lastSent = data
            if direct || prev?.today != payload2.today || prev?.days.map(\.programIdRaw) != payload2.days.map(\.programIdRaw) || prev?.schedule != payload2.schedule,
               s.isReachable {
                s.sendMessage(["p": data], replyHandler: nil, errorHandler: nil)
            }
            // Saat yüzünde komplikasyon varsa öncelikli teslim; yalnız kalori ya da gün değişince (günlük bütçe sınırlı)
            let changed = prev?.today != payload2.today || prev?.kcalEaten != payload2.kcalEaten || prev?.kcalTarget != payload2.kcalTarget
                || prev?.kcalBmr != payload2.kcalBmr || prev?.stepGoal != payload2.stepGoal
            if changed, s.isComplicationEnabled, s.remainingComplicationUserInfoTransfers > 0 {
                s.transferCurrentComplicationUserInfo(["p": data])
            }
        } catch {
            log.error("Saate bağlam gönderilemedi: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saatten gelen olay: seti yaz ya da antrenmanı kaydet
    private func apply(_ msg: [String: Any]) {
        guard let data = msg["d"] as? Data, let ctx = container?.mainContext,
              let e = try? JSONDecoder().decode(WatchEvent.self, from: data) else { return }
        // sendMessage hata verip transferUserInfo ile tekrar gelirse aynı olay iki kez işlenmesin (WT-11)
        if let id = msg["id"] as? String {
            guard !seen.contains(id) else { return }
            seen.append(id)
            if seen.count > 200 { seen.removeFirst(seen.count - 200) }
            UserDefaults.standard.set(seen, forKey: "wsync.seen")
        }
        switch e.kind {
        case "set":
            // Yalnız iPhone'da bulunan programın hareketleri yazılır (saatteki örnek program iPhone'a karışmasın)
            guard let eid = e.eid, let si = e.si, let prog = Wk.program(e.pid, ctx), prog.blocks.allExercises.contains(where: { $0.id == eid }) else { return }
            Wk.setLog(ctx, date: e.date, eid: eid, index: si) { s in s.kg = e.kg; s.reps = e.reps; s.done = true }
            Wk.rememberLoad(prog, eid: eid, kg: e.kg)   // saatte girilen kilo da programa yazılır (4 Kas)
        case "complete":
            guard let prog = Wk.program(e.pid, ctx) else { return }
            let L = Store.day(ctx, e.date)!
            let doneIds = Set(e.doneIds ?? [])
            var X = L.exDone
            for id in doneIds { X[id] = true }
            L.exDone = X
            L.workoutDone = prog.blocks.allExercises.allSatisfy { doneIds.contains($0.id) || L.exDone[$0.id] == true }
            if L.programIdRaw == nil { L.programIdRaw = prog.pid }
            // Saat antrenmanı Sağlık'a zaten yazdı; iPhone ikinci kez yazmasın
            if let sec = e.seconds, sec > 0, L.workoutSeconds == 0 {
                L.workoutSeconds = min(sec, 4 * 3600)
                // Sağlık'ın ölçtüğü kalori iCloud'a yazılmaz (5.1.3, AR-03); uygulamanın kendi MET tahmini kullanılır
                L.workoutKcal = CalorieEngine.workoutKcal(minutes: Double(L.workoutSeconds) / 60,
                                                          weightKg: Store.latestWeight(ctx) ?? Store.profile(ctx).startKg ?? 75)
            }
            if (e.seconds ?? 0) > 0 {   // yalnız saat gerçekten Sağlık'a yazdıysa (CR-37)
                UserDefaults.standard.set(true, forKey: "wk.hk.\(e.date)")
                L.hkSaved = true   // saat yazdı; diğer cihazlar da bilsin (CR-22)
            }
            WkSessionClock.clear(e.date)
        case "fastEnd":
            // Saatten "orucu bitir": o gün başlayan oruç şimdi biter
            let p = Store.profile(ctx); var f = p.fast
            if let k = e.pid { f.endEarly(k, at: e.at ?? Date()) }; p.fast = f   // gecikmeli teslimde saatin anı (CR-33); sıradaki oruç kayar (FS-01)
        case "fastSkip":
            let p = Store.profile(ctx); var f = p.fast
            // Yeni saat açık değer yollar; eski sürüm (değer yok) için aç/kapat (WT-11)
            if let k = e.pid {
                let on = msg["on"] as? Bool ?? !f.skipped.contains(k)
                if on { f.skipped.insert(k) } else { f.skipped.remove(k) }
            }
            p.fast = f
        case "pick":
            // Saatte başka program seçilip başlatıldı: bugünün antrenmanı o olur (yalnız bu gün, WT-16)
            guard let pid = e.pid, Wk.program(pid, ctx) != nil else { return }
            let prof = Store.profile(ctx)
            if Store.day(ctx, e.date, create: false)?.workoutDone != true, Store.program(for: e.date, profile: prof, ctx: ctx)?.pid != pid {
                Wk.assignDay(ctx, prof, date: e.date, pid: pid, repeats: false)
            }
        case "sync":
            // Saat açıldı ya da plan ekranına girdi: son hali yeniden yolla (değişmemiş olsa bile)
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
        guard let m = Self.event(userInfo) else { return }
        Task { @MainActor in self.apply(m.dict) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let m = Self.event(message) else { return }
        Task { @MainActor in self.apply(m.dict) }
    }
    /// Sözlüğü aktörler arası geçirmek için yalnız bilinen alanlar alınır
    private struct Event: @unchecked Sendable { let dict: [String: Any] }
    nonisolated private static func event(_ m: [String: Any]) -> Event? {
        guard let d = m["d"] as? Data else { return nil }
        var x: [String: Any] = ["d": d]
        if let id = m["id"] as? String { x["id"] = id }
        if let on = m["on"] as? Bool { x["on"] = on }
        return Event(dict: x)
    }
}
