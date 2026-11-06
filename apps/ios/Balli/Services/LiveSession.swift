import Foundation
import ActivityKit
import BalliKit
import UIKit

/// Antrenman sürerken kilit ekranı + Dynamic Island canlı etkinliği
@MainActor
enum LiveSession {
    private static var activity: Activity<SessionActivityAttributes>?
    private static var last: SessionActivityAttributes.ContentState?
    private static var program = ""
    /// Dinlenme dışındaki güncellemelerde eskime süresi (LA-10)
    static let staleAfter: TimeInterval = 15 * 60

    static func sync(_ now: AppState.SessionNow?, active: Bool) {
        #if !LITE
        guard active, let now else { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = SessionActivityAttributes.ContentState(
            exercise: now.exercise, setText: now.setText, load: now.load,
            restEnd: now.restEnd.flatMap { $0 > .now ? $0 : nil }, restTotal: now.restTotal,
            paused: now.paused, finished: now.finished, done: now.done, total: now.total)
        guard state != last else { return }
        last = state
        // Dinlenme bitince "eskidi" sayılsın → görünüm "Sıradaki set" der
        // Dinlenme yoksa kısa, her güncellemede ileri kayan süre: uygulama öldürülürse en geç 15 dk'da eskir (WK-18, LA-10)
        let content = ActivityContent(state: state, staleDate: state.restEnd ?? Date().addingTimeInterval(Self.staleAfter))
        // Farklı seansa geçildiyse eskisini kapat, yenisini başlat (WK-06)
        if let a = activity, program != now.program {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
            activity = nil
        }
        program = now.program
        if let a = activity {
            Task { await a.update(content) }
        } else {
            activity = try? Activity.request(attributes: .init(program: now.program), content: content)
        }
        #endif
    }

    /// Yalnız bu çalıştırmanın etkinliğini bitirir (yeni açılanı yanlışlıkla kapatmaz)
    static func end() {
        #if !LITE
        last = nil
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Uygulama kapanırken: etkinlikleri bitirmeyi dener. Ana iş parçacığı bekletilmez (LA-10);
    /// yetişmezse kısa eskime süresi ve açılıştaki endOrphans temizler.
    nonisolated static func endAllNow() {
        #if !LITE
        Task.detached(priority: .userInitiated) {
            for a in Activity<SessionActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// Açılışta: önceki çalıştırmadan kalan (uygulama öldürülmüş) etkinlikleri temizle
    static func endOrphans() {
        #if !LITE
        let all = Activity<SessionActivityAttributes>.activities
        Task { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
        #endif
    }
}

/// Aralıklı oruç canlı etkinliği: oruçtayken kilit ekranında ve Dynamic Island'da geri sayım.
/// Program sabit olduğundan uygulama her açıldığında/kapandığında güncel duruma eşitlenir.
@MainActor
enum LiveFast {
    static func sync(_ p: UserProfile) {
        #if !LITE
        let existing = Activity<FastActivityAttributes>.activities
        guard p.fastOn else {
            for a in existing { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            requestedWindow = nil; dismissedWindow = nil   // yeniden açılınca etkinlik gelsin
            return
        }
        // Oruçta: bitişe geri sayım; yeme penceresinde: oruç başlangıcına geri sayım
        let f = p.fast
        let now = Date()
        let (start, end, fasting): (Date, Date, Bool) = {
            switch f.phase(at: now) {
            case let .fasting(s, e, _): return (s, e, true)
            case let .eating(s, n, _): return (s, n, false)
            }
        }()
        let next: Date = {
            switch f.phase(at: end.addingTimeInterval(1)) {
            case let .fasting(_, e, _): return e
            case let .eating(_, n, _): return n
            }
        }()
        let state = FastActivityAttributes.ContentState(start: start, end: end, next: next, fasting: fasting)
        // Eskime anında görünüm sıradaki döneme geçer; bir sonraki dönemin sonunda da kapanır
        let content = ActivityContent(state: state, staleDate: end)
        // Kullanıcı kilit ekranından kaldırdıysa aynı dönem içinde yeniden açılmaz (LA-11)
        let window = start.timeIntervalSince1970
        let live = existing.filter { $0.activityState == .active || $0.activityState == .stale }
        // (eski .dismissed kayıtları sistemin kapattıklarını da içerebilir; karar watch() içinde verilir)
        if let a = live.first {
            if a.content.state != state { Task { await a.update(content) } }
            for b in live.dropFirst() { Task { await b.end(nil, dismissalPolicy: .immediate) } }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled,
                  UIApplication.shared.applicationState == .active,   // arka planda istek atılmaz (LA-11)
                  dismissedWindow != window {   // sistem 8 saatte kapattıysa aynı dönemde yeniden açılır; yalnız kullanıcı kaldırdıysa açılmaz
            if let a = try? Activity<FastActivityAttributes>.request(attributes: FastActivityAttributes(label: f.label), content: content) {
                requestedWindow = window
                watch(a, window: window)
            }
        }
        #endif
    }

    #if !LITE
    /// Bu dönem için açılan etkinlik: yoksa ve aynı dönemse kullanıcı kaldırmış demektir
    private static var requestedWindow: Double? {
        get { UserDefaults.standard.object(forKey: "livefast.req") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "livefast.req") }
    }
    private static var dismissedWindow: Double? {
        get { UserDefaults.standard.object(forKey: "livefast.dismissed") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "livefast.dismissed") }
    }
    /// Uygulama açıkken kaldırılırsa hemen kaydedilir
    private static func watch(_ a: Activity<FastActivityAttributes>, window: Double) {
        Task {
            // Sistem süreyi doldurup kapattıysa önce .ended gelir; yalnız doğrudan kaldırma "kullanıcı kaldırdı" sayılır
            var ended = false
            for await st in a.activityStateUpdates {
                if st == .ended { ended = true }
                if st == .dismissed {
                    if !ended { await MainActor.run { dismissedWindow = window } }
                    break
                }
            }
        }
    }
    #endif
}
