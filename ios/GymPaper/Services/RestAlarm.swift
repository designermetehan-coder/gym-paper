import Foundation
import UserNotifications
import AudioToolbox
import UIKit
import SwiftData
import GymPaperKit

/// Rest end: silent local notification in the background/locked; haptics only in the foreground
/// (last 3 seconds tick, then one strong buzz; no sound)
enum RestAlarm {
    private static let id = "gympaper.rest"

    static func requestPermission() {
        if ProcessInfo.processInfo.arguments.contains("-demo") { return }   // screenshots: no permission prompt
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func schedule(at end: Date, next: String?) {
        cancel()
        let left = end.timeIntervalSinceNow
        guard left > 1 else { return }
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Dinlenme bitti")
        c.body = next.map { String(localized: "Sıradaki: \($0)") } ?? String(localized: "Sıradaki sete geç")
        c.sound = nil   // no sound at the end of rest
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Last whole second announced by `countdown` (one tap per second, also with two tickers running)
    @MainActor private static var lastBeat = -1
    /// Last 3 seconds of a countdown: a light tap at 3, 2, 1
    @MainActor static func countdown(end: Date, now: Date = .now) {
        let left = Int(end.timeIntervalSince(now).rounded(.up))
        guard (1...3).contains(left), left != lastBeat else { return }
        lastBeat = left
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.7)
    }
    /// End of rest / timed set: one strong buzz, no sound
    @MainActor static func beep() {
        lastBeat = -1
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.impactOccurred(intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred(intensity: 1) }
    }
}

// MARK: - Reminders (local notifications; no server)

/// Workout, nutrition, water, weigh-in, weekly summary, unfinished workout and goal notifications.
/// The next 7 days are rescheduled on every launch/save; at most 2 scheduled reminders a day (water separate).
enum NtfKind: String, CaseIterable {
    case workout, openSession, food, water, weigh, weekly, goal, fast
}

@MainActor
enum Notifier {
    private static let d = UserDefaults.standard
    static let prefix = "gympaper.ntf."
    static let waterHours = [11, 14, 17]
    static let maxPerDay = 2
    /// Signature of the last scheduled plan: no system call if unchanged
    private static var lastSig = ""
    /// Force a reschedule when permission or settings change
    static func invalidate() { lastSig = "" }

    static func on(_ k: NtfKind) -> Bool { d.object(forKey: "ntf.\(k.rawValue)") as? Bool ?? (k != .water) }
    static var workoutMin: Int { d.object(forKey: "ntf.workoutMin") as? Int ?? 18 * 60 }
    static var foodMin: Int { d.object(forKey: "ntf.foodMin") as? Int ?? 21 * 60 }
    /// Calendar.weekday (1 = Pazar … 2 = Pazartesi)
    static var weighDay: Int { d.object(forKey: "ntf.weighDay") as? Int ?? 2 }

    /// Asks once if permission hasn't been requested yet
    static func askOnce() async {
        let c = UNUserNotificationCenter.current()
        guard await c.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await c.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private struct Plan { var id: String; var title: String; var body: String; var at: DateComponents }

    static func reschedule(_ ctx: ModelContext) {
        let cal = DayKey.calendar
        let now = Date()
        let today = cal.startOfDay(for: now)
        let keys = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let profile = Store.profile(ctx)
        let from = DayKey.of(keys[0]), to = DayKey.of(keys[6])
        // from this week's Monday, for the weekly summary
        let monday = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let mondayKey = DayKey.of(monday)
        let lo = min(mondayKey, from)
        let days = (try? ctx.fetch(FetchDescriptor<DayLog>(predicate: #Predicate { $0.date >= lo && $0.date <= to }))) ?? []
        let measures = (try? ctx.fetch(FetchDescriptor<BodyMeasure>(predicate: #Predicate { $0.kg != nil }, sortBy: [SortDescriptor(\.date)]))) ?? []   // measurements with weight only
        let G = GoalState(startKg: profile.startKg, goals: profile.goals, measures: measures)

        var plans: [Plan] = []
        func comps(_ day: Date, _ min: Int) -> DateComponents? {
            guard let t = cal.date(bySettingHour: min / 60, minute: min % 60, second: 0, of: day), t > now.addingTimeInterval(30) else { return nil }
            return cal.dateComponents([.year, .month, .day, .hour, .minute], from: t)
        }
        for day in keys {
            let key = DayKey.of(day)
            let log = days.day(key)
            let isToday = key == DayKey.today
            var cands: [Plan] = []
            // 1) Workout day
            if on(.workout), !(log?.workoutDone ?? false), let prog = Store.program(for: key, profile: profile, ctx: ctx), let c = comps(day, workoutMin) {
                cands.append(Plan(id: "workout.\(key)", title: String(localized: "Bugün antrenman var"), body: String(localized: "\(prog.name) seni bekliyor. Hazır olduğunda başlat."), at: c))
            }
            // 2) Weigh-in day
            if on(.weigh), cal.component(.weekday, from: day) == weighDay,
               !measures.contains(where: { $0.kg != nil && cal.isDate($0.date, inSameDayAs: day) }), let c = comps(day, 8 * 60 + 30) {
                cands.append(Plan(id: "weigh.\(key)", title: String(localized: "Tartılma günü"), body: String(localized: "Sabah aç karnına tartıl ve kilonu ekle."), at: c))
            }
            // 3) Evening food log
            if on(.food), (log?.entries.isEmpty ?? true), let c = comps(day, foodMin) {
                cands.append(Plan(id: "food.\(key)", title: isToday ? String(localized: "Bugün henüz bir şey eklemedin") : String(localized: "Bugünü kaydettin mi?"),
                                  body: String(localized: "Yediklerini eklemek bir dakika sürer; kalori hedefin doğru kalsın."), at: c))
            }
            // 4) Sunday evening weekly summary
            if on(.weekly), cal.component(.weekday, from: day) == 1, let c = comps(day, 20 * 60) {
                let n = days.filter { $0.workoutDone && $0.date >= mondayKey && $0.date <= key }.reduce(into: Set<String>()) { $0.insert($1.date) }.count
                let goal = G.active != nil && !G.done ? String(localized: " · hedefe \(fmt1(G.left)) kg kaldı") : (G.done ? String(localized: " · tüm kilo hedeflerin tamam") : "")
                cands.append(Plan(id: "weekly.\(key)", title: String(localized: "Haftalık özet"), body: String(localized: "Bu hafta \(n) antrenman yaptın\(goal)."), at: c))
            }
            plans += cands.prefix(maxPerDay)
            // Intermittent fasting (counted separately): fast over · eating window closing
            if on(.fast), profile.fastOn {
                let f = profile.fast
                if let e = f.end(of: key), e > now.addingTimeInterval(30) {
                    plans.append(Plan(id: "fastend.\(key)", title: String(localized: "Oruç tamamlandı"), body: String(localized: "Orucun bitti (\(f.label)); yeme pencereni açabilirsin."),
                                      at: cal.dateComponents([.year, .month, .day, .hour, .minute], from: e)))
                }
                if !f.skipped.contains(key), let st = f.start(of: key)?.addingTimeInterval(-30 * 60), st > now.addingTimeInterval(30) {
                    plans.append(Plan(id: "fastclose.\(key)", title: String(localized: "Yeme pencerene 30 dk kaldı"), body: String(localized: "Oruç \(f.startText)'da başlıyor."),
                                      at: cal.dateComponents([.year, .month, .day, .hour, .minute], from: st)))
                }
            }
            // Water (separate; stops once the goal is reached)
            if on(.water) {
                let w = log?.waterMl ?? 0
                if !(isToday && w >= profile.waterMl) {
                    for h in waterHours { if let c = comps(day, h * 60) {
                        plans.append(Plan(id: "water.\(key).\(h)", title: String(localized: "Su içme zamanı"),
                                          body: isToday ? String(localized: "\(fmt1(Double(w) / 1000)) / \(fmt1(Double(profile.waterMl) / 1000)) L. Bir bardak daha?") : String(localized: "Günlük hedefin \(fmt1(Double(profile.waterMl) / 1000)) L."), at: c))
                    } }
                }
            }
        }

        // fast that started yesterday and ends today
        let yKey = DayKey.shift(DayKey.of(today), days: -1)
        if on(.fast), profile.fastOn, let e = profile.fast.end(of: yKey), e > now.addingTimeInterval(30) {
            plans.append(Plan(id: "fastend.\(yKey)", title: String(localized: "Oruç tamamlandı"), body: String(localized: "Orucun bitti (\(profile.fast.label)); yeme pencereni açabilirsin."),
                              at: cal.dateComponents([.year, .month, .day, .hour, .minute], from: e)))
        }

        let center = UNUserNotificationCenter.current()
        let sig = plans.map { "\($0.id)|\($0.title)|\($0.body)|\($0.at)" }.joined(separator: ";")
        if sig != lastSig {
        lastSig = sig
        var all: [String] = ["\(prefix)fastend.\(yKey)"]
        for day in keys { let k = DayKey.of(day); all += ["workout", "weigh", "food", "weekly", "fastend", "fastclose"].map { "\(prefix)\($0).\(k)" } + waterHours.map { "\(prefix)water.\(k).\($0)" } }
        center.removePendingNotificationRequests(withIdentifiers: all)
        for p in plans {
            let c = UNMutableNotificationContent()
            c.title = p.title; c.body = p.body; c.sound = .default
            center.add(UNNotificationRequest(identifier: prefix + p.id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: p.at, repeats: false)))
        }
        }

        // Goal reached: once per goal; the celebration is already on screen when the app is open
        if on(.goal), let cur = G.cur, let start = G.start {
            for g in G.goals where g < start && cur <= g && !d.bool(forKey: "ntf.goal.\(g)") {
                d.set(true, forKey: "ntf.goal.\(g)")
                if UIApplication.shared.applicationState != .active {
                    let c = UNMutableNotificationContent()
                    c.title = String(localized: "Tebrikler!"); c.body = String(localized: "\(fmt1(g)) kg hedefine ulaştın."); c.sound = .default
                    center.add(UNNotificationRequest(identifier: "\(prefix)goal.\(g)", content: c, trigger: nil))
                }
            }
        }
    }

    /// If a workout is open when the app goes to the background, remind after 2 hours; cancelled on return
    static func openSession(_ program: String?) {
        let id = prefix + "open"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let program, on(.openSession) else { return }
        let c = UNMutableNotificationContent()
        c.title = String(localized: "Antrenman hâlâ açık")
        c.body = String(localized: "\(program) 2 saattir açık. Bitirdiysen kaydet.")
        c.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2 * 3600, repeats: false)))
    }
}
