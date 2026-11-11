import Foundation
import ActivityKit
import GymPaperKit
import UIKit

/// Lock Screen + Dynamic Island live activity during a workout
@MainActor
enum LiveSession {
    private static var activity: Activity<SessionActivityAttributes>?
    private static var last: SessionActivityAttributes.ContentState?
    private static var program = ""
    /// Stale date for updates other than rest
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
        // once rest ends it counts as stale → the view says "Next set"
        // without rest, a short stale date pushed forward on every update: if the app is killed it goes stale within 15 min
        let content = ActivityContent(state: state, staleDate: state.restEnd ?? Date().addingTimeInterval(Self.staleAfter))
        // switching to another session ends the old one and starts the new one
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

    /// Ends only this run's activity (never the newly opened one)
    static func end() {
        #if !LITE
        last = nil
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// On app termination: tries to end activities without blocking the main thread;
    /// if it doesn't make it, the short stale date and endOrphans on next launch clean up.
    nonisolated static func endAllNow() {
        #if !LITE
        Task.detached(priority: .userInitiated) {
            for a in Activity<SessionActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// On launch: clean up activities left by a previous run (app killed)
    static func endOrphans() {
        #if !LITE
        let all = Activity<SessionActivityAttributes>.activities
        Task { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
        #endif
    }
}

/// Intermittent fasting live activity: countdown on the Lock Screen and Dynamic Island while fasting.
/// The schedule is fixed, so it syncs to the current state whenever the app opens or closes.
@MainActor
enum LiveFast {
    static func sync(_ p: UserProfile) {
        #if !LITE
        let existing = Activity<FastActivityAttributes>.activities
        guard p.fastOn else {
            for a in existing { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            requestedWindow = nil; dismissedWindow = nil   // bring the activity back on reopen
            return
        }
        // fasting: count down to the end; eating window: count down to the next fast
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
        // at the stale date the view moves to the next phase; it also ends at the end of the next phase
        let content = ActivityContent(state: state, staleDate: end)
        // if the user removed it from the Lock Screen, it isn't reopened within the same phase
        let window = start.timeIntervalSince1970
        let live = existing.filter { $0.activityState == .active || $0.activityState == .stale }
        // (old .dismissed records may include ones the system closed; watch() decides)
        if let a = live.first {
            if a.content.state != state { Task { await a.update(content) } }
            for b in live.dropFirst() { Task { await b.end(nil, dismissalPolicy: .immediate) } }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled,
                  UIApplication.shared.applicationState == .active,   // no request in the background
                  dismissedWindow != window {   // if the system closed it after 8 hours, reopen in the same phase; only a user removal keeps it closed
            if let a = try? Activity<FastActivityAttributes>.request(attributes: FastActivityAttributes(label: f.label), content: content) {
                requestedWindow = window
                watch(a, window: window)
            }
        }
        #endif
    }

    #if !LITE
    /// Activity opened for this phase: if missing within the same phase, the user removed it
    private static var requestedWindow: Double? {
        get { UserDefaults.standard.object(forKey: "livefast.req") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "livefast.req") }
    }
    private static var dismissedWindow: Double? {
        get { UserDefaults.standard.object(forKey: "livefast.dismissed") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "livefast.dismissed") }
    }
    /// Saved right away if removed while the app is open
    private static func watch(_ a: Activity<FastActivityAttributes>, window: Double) {
        Task {
            // When the system ends it on timeout, .ended comes first; only a direct removal counts as "user removed"
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
