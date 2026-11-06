import Foundation
import HealthKit
import Observation
import BalliKit

/// Saatte antrenman oturumu: nabız ve aktif kaloriyi toplar, bitince antrenmanı Sağlık'a yazar.
/// Oturum açıkken uygulama bilekte önde kalır (spor salonunda ekran kararınca kapanmaz).
@MainActor @Observable
final class WatchWorkout: NSObject {
    /// Uygulama temsilcisi çökme sonrası oturumu buna bağlar (WT-14)
    static let shared = WatchWorkout()
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var heartRate: Double = 0
    private(set) var kcal: Double = 0
    private(set) var startedAt: Date?
    /// Oturum hangi gün/program için açık
    private(set) var owner: String?

    var running: Bool { session != nil }

    /// İzin bir oturumda bir kez istenir; her ön plana gelişte ve her başlatmada beklenmesin (WQ-11)
    @ObservationIgnored private var authAsked = false
    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable(), !authAsked else { return }
        authAsked = true
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(owner: String) async {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        await requestAuth()
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .traditionalStrengthTraining
        cfg.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            s.delegate = self
            b.delegate = self
            session = s; builder = b; self.owner = owner
            heartRate = 0; kcal = 0
            let now = Date()
            startedAt = now
            UserDefaults.standard.set(owner, forKey: "wwk.owner")
            s.startActivity(with: now)
            do { try await b.beginCollection(at: now) }
            catch {
                // Etkinlik başladı ama toplama açılamadı: oturum açık kalmasın (WT-13)
                s.end(); b.discardWorkout()
                throw error
            }
        } catch {
            reset()
        }
    }

    /// Uygulama çöküp yeniden açılınca süren antrenman oturumunu geri bağlar (WT-14)
    func recover() async {
        guard session == nil else { return }
        guard let s = try? await store.recoverActiveWorkoutSession() else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: s.workoutConfiguration)
        s.delegate = self
        b.delegate = self
        session = s; builder = b
        owner = UserDefaults.standard.string(forKey: "wwk.owner")
        startedAt = b.startDate ?? s.startDate ?? Date()
        paused = s.state == .paused
    }

    /// Oturumu bitirip Sağlık'a kaydeder; (süre sn, kcal) döner
    func finish() async -> (seconds: Int, kcal: Double)? {
        guard let s = session, let b = builder else { return nil }
        finishing = true
        defer { finishing = false }
        let end = Date()
        s.end()
        let k = kcal
        // Sağlık takılırsa "Kaydet" sonsuza dek beklemesin: en çok 8 sn (WQ-02)
        let w: HKWorkout? = await withTaskGroup(of: HKWorkout?.self) { g in
            g.addTask { @MainActor in
                try? await b.endCollection(at: end)
                return try? await b.finishWorkout()
            }
            g.addTask { try? await Task.sleep(for: .seconds(8)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        // Sağlık'a yazılamadıysa iPhone "saat yazdı" sanmasın (CR-37)
        guard let w else { reset(); return nil }
        let sec = Int(w.duration)
        reset()
        return (sec, k)
    }

    var paused = false
    /// Duraklamalar düşülmüş antrenman süresi
    var elapsed: TimeInterval { builder?.elapsedTime ?? startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    func pause() { session?.pause(); paused = true }
    func resume() { session?.resume(); paused = false }

    /// Kaydetmeden kapat
    func discard() {
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    /// finish() sürerken gelen .ended olayı oturumu sıfırlamasın
    @ObservationIgnored private var finishing = false

    private func reset() {
        session = nil; builder = nil; owner = nil; startedAt = nil; paused = false
        UserDefaults.standard.removeObject(forKey: "wwk.owner")
    }

    /// Oturum sistem tarafından bitti ya da hata verdi: açık kalmış görünmesin (WT-14)
    fileprivate func sessionDropped(_ s: HKWorkoutSession, failed: Bool) {
        guard session === s, !finishing else { return }
        if failed { s.end() }
        builder?.discardWorkout()
        reset()
    }
}

extension WatchWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.sessionDropped(workoutSession, failed: false) }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.sessionDropped(workoutSession, failed: true) }
    }
}

extension WatchWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        let kc = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let hr { self.heartRate = hr }
            if let kc { self.kcal = kc }
        }
    }
}


/// Köşe göstergeleri için bugünkü adım ve aktif kalori, saatin kendi Sağlık verisinden (WC-01, WC-03).
/// Komplikasyon uzantısı Sağlık'a erişemez; uygulama açılınca ve arka plan yenilemesinde okunup App Group'a yazılır.
enum WHealth {
    struct Today: Codable { var date: String; var steps: Int; var active: Double }
    private static let key = "whealth.today"
    private static let store = HKHealthStore()

    static func cached(_ day: String) -> Today? {
        guard let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode(Today.self, from: d), t.date == day else { return nil }
        return t
    }

    /// Bugünün toplamlarını okur ve saklar; izin yoksa ya da okunamazsa eski değer kalır
    static func refresh() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let day = DayKey.today
        let start = Calendar.current.startOfDay(for: .now)
        async let steps = sum(.stepCount, unit: .count(), from: start)
        async let active = sum(.activeEnergyBurned, unit: .kilocalorie(), from: start)
        let (s, a) = await (steps, active)
        guard s != nil || a != nil else { return }
        let old = cached(day)
        let t = Today(date: day, steps: Int(s ?? Double(old?.steps ?? 0)), active: a ?? old?.active ?? 0)
        if let d = try? JSONEncoder().encode(t) { UserDefaults.standard.set(d, forKey: key) }
    }

    private static func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> Double? {
        await withCheckedContinuation { c in
            let pred = HKQuery.predicateForSamples(withStart: start, end: nil)
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: pred, options: .cumulativeSum) { _, r, _ in
                c.resume(returning: r?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
}
