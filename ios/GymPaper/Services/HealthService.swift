import Foundation
import HealthKit
import GymPaperKit

/// Apple Health: reads steps, active energy, weight, height, age, sex; writes workouts.
@MainActor
@Observable
final class HealthService {
    private let store = HKHealthStore()
    #if LITE
    var available: Bool { false } // Lite: no Health entitlement
    #else
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    #endif
    var authorized = false
    var stepsToday: Int = 0
    /// Steps of the last 7 days (day key → steps), for the weekly average
    var weekSteps: [String: Int] = [:]
    var activeKcalToday: Double = 0
    var latestWeightKg: Double?
    var latestWeightAt: Date?
    var heightCm: Double?
    var birthDate: Date?
    var sex: Sex?
    var lastError: String?

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.bodyMass), HKQuantityType(.height),
        ]
        s.insert(HKCharacteristicType(.dateOfBirth))
        s.insert(HKCharacteristicType(.biologicalSex))
        return s
    }
    private var writeTypes: Set<HKSampleType> { [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass)] }

    func requestAccess() async {
        guard available else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            await refresh()
            await updateAuthorized()
        } catch { lastError = error.localizedDescription }
    }

    /// A successful request doesn't mean access was granted: HealthKit hides read denials,
    /// so we count as connected once the prompt was answered and (some write access exists or data was read).
    private func updateAuthorized() async {
        let status = try? await store.statusForAuthorizationRequest(toShare: writeTypes, read: readTypes)
        guard status == .unnecessary else { authorized = false; return }
        let canWrite = writeTypes.contains { store.authorizationStatus(for: $0) == .sharingAuthorized }
        let hasData = stepsToday > 0 || activeKcalToday > 0 || latestWeightKg != nil || heightCm != nil
        authorized = canWrite || hasData
    }

    @ObservationIgnored private var stepToken: NSObjectProtocol?
    /// Single step observer: StepWatcher updates the widget and notifies here
    func startStepUpdates() {
        #if !LITE
        guard available, stepToken == nil else { return }
        stepToken = NotificationCenter.default.addObserver(forName: .gymPaperStepsToday, object: nil, queue: .main) { [weak self] n in
            guard let v = n.object as? Int else { return }
            MainActor.assumeIsolated { self?.stepsToday = v }
        }
        StepWatcher.shared.start()   // widget observer after the first grant
        #endif
    }

    func refresh(for day: Date = .now) async {
        guard available else { return }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        // if the query fails (e.g. device locked) keep the old value instead of dropping to 0
        if let v = await trySum(.stepCount, unit: .count(), start: start, end: end) { stepsToday = Int(v) }
        if let v = await trySum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end) { activeKcalToday = v }
        var w: [String: Int] = [:]
        for i in 1...6 {
            let d = Calendar.current.date(byAdding: .day, value: -i, to: start)!
            if let v = await trySum(.stepCount, unit: .count(), start: d, end: Calendar.current.date(byAdding: .day, value: 1, to: d)!) { w[DayKey.of(d)] = Int(v) }
        }
        w[DayKey.of(start)] = stepsToday
        weekSteps = w
        let wq = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass))], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        if let w = (try? await wq.result(for: store))?.first {
            latestWeightKg = w.quantity.doubleValue(for: .gramUnit(with: .kilo)); latestWeightAt = w.endDate
        } else { latestWeightKg = nil; latestWeightAt = nil }
        if let h = await latest(.height, unit: .meterUnit(with: .centi)) { heightCm = h }
        if let dob = try? store.dateOfBirthComponents(), let d = Calendar.current.date(from: dob) { birthDate = d }
        if let s = try? store.biologicalSex().biologicalSex {
            sex = s == .male ? .male : s == .female ? .female : nil
        }
    }

    /// Daily steps from a date to today (day key → steps); one collection query
    func dailySteps(from key: String) async -> [String: Int] {
        guard available, let start = DayKey.date(key) else { return [:] }
        let s = Calendar.current.startOfDay(for: start)
        let pred = HKQuery.predicateForSamples(withStart: s, end: .now)
        let q = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: pred),
            options: .cumulativeSum, anchorDate: s, intervalComponents: DateComponents(day: 1))
        guard let coll = try? await q.result(for: store) else { return [:] }
        var out: [String: Int] = [:]
        coll.enumerateStatistics(from: s, to: .now) { st, _ in
            if let v = st.sumQuantity()?.doubleValue(for: .count()), v > 0 { out[DayKey.of(st.startDate)] = Int(v) }
        }
        return out
    }

    private func trySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        let type = HKQuantityType(id)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let q = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: pred), options: .cumulativeSum)
        do { return try await q.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0 }
        catch { return nil }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        let type = HKQuantityType(id)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        let q = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: pred), options: .cumulativeSum)
        return (try? await q.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType(id)
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type)], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return (try? await q.result(for: store))?.first?.quantity.doubleValue(for: unit)
    }

    /// Writes a finished strength workout to Health
    /// True when written; only then is the flag set, so a failed write can be retried
    @discardableResult
    func saveStrengthWorkout(start: Date, end: Date, kcal: Double) async -> Bool {
        guard available, store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end)
            try await builder.addSamples([energy])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    func saveWeight(_ kg: Double, at date: Date = .now) async {
        guard available, store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized else { return }
        let s = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date)
        try? await store.save(s)
    }
}
