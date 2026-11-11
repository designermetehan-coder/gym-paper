import SwiftUI


enum AppTab: String, CaseIterable, Hashable {
    // rawValue "profile" kept for widget/deep links (gympaper://tab/profile now opens Progress)
    case today, workout, food, social, profile
    /// Team (steps + workouts with friends) is its own tab; needs the Supabase social functions
    static let socialEnabled = true
    var label: String { switch self { case .today: tl("Bugün"); case .workout: tl("Antrenman"); case .food: tl("Beslenme"); case .social: tl("Ekip"); case .profile: tl("İlerleme") } }
    /// SF Symbol for the native tab bar
    var symbol: String { switch self { case .today: "square.grid.2x2"; case .workout: "dumbbell"; case .food: "fork.knife"; case .social: "person.2"; case .profile: "chart.bar" } }
}

struct ToastItem: Identifiable, Equatable {
    enum Kind { case ok, delete, error }
    let id = UUID()
    var msg: String
    var kind: Kind = .ok
    var undo: (() -> Void)?
    static func == (a: ToastItem, b: ToastItem) -> Bool { a.id == b.id }
}

/// Session runtime state: the player resumes where it was after the sheet closes and reopens
struct SessionCountdown: Equatable { var end: Date; var total: Double; var left: Double? }
@MainActor @Observable
final class SessionRuntime {
    var key = ""
    var idx = -1
    var rest: SessionCountdown?
    var timer: SessionCountdown?
    var finished = false
    var kg: Double = 0
    var reps: Double = 0
    /// Current step id ("exerciseId#set"): idx is found again after the program is edited
    var stepKey: String?
    /// Next set shown in the rest notification
    var restNext: String?
    func use(_ k: String) {
        guard key != k else { return }
        key = k; idx = -1; rest = nil; timer = nil; finished = false; kg = 0; reps = 0; stepKey = nil
    }
}

/// State shared across screens: tab, toasts, session
@MainActor
@Observable
final class AppState {
    var tab: AppTab = .today
    var toasts: [ToastItem] = []
    /// Open workout session (program id + day)
    var session: SessionRef?
    /// Sheet that can be opened from any screen
    var sheet: AppSheet? { didSet { sheetOpen = sheet != nil } }
    /// While a sheet is open, toasts show at the top
    var sheetOpen = false
    func open(_ s: AppSheet) { sheet = s }

    struct SessionRef: Identifiable, Equatable, Hashable { var pid: String; var date: String; var id: String { pid + date } }
    /// Navigation path of the Workout tab (My programs and program editing open full screen)
    var workoutPath: [WkRoute] = []
    /// Session minimized: mini player above the tab bar
    var sessionMin = false
    /// Persistent session runtime
    let rt = SessionRuntime()
    /// Live session info shown by the mini player (written by SessionView)
    var sessionNow: SessionNow?
    struct SessionNow: Equatable {
        var program: String
        var exercise: String
        var detail: String          // "Set 2/4" or "Rest"
        var restEnd: Date?
        var restTotal: Double = 0
        var paused = false
        var progress: Double = 0
        var setText = ""
        var load = ""
        var done = 0
        var total = 0
        var finished = false
    }
    /// Asks first when a new session is requested while another one is open
    var switchTo: SessionRef?
    func openSession(_ s: SessionRef, force: Bool = false) {
        if let cur = session, cur != s, !force { switchTo = s; return }
        if session != s { sessionNow = nil }   // don't keep the previous session's info
        #if !LITE
        RestAlarm.requestPermission()
        #endif
        rt.use(s.id)   // switch the runtime to the right session before the view appears
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { session = s; sessionMin = false }
    }
    /// Day completed or unmarked elsewhere: close that day's open session
    func endSessionIfOn(_ date: String) { if session?.date == date { closeSession() } }
    func closeSession() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { session = nil; sessionMin = false; sessionNow = nil }
        rt.use("")   // reopening must not bring back the old rest timer or beep
        RestAlarm.cancel()
    }
    func minimizeSession(_ m: Bool) {
        haptic()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { sessionMin = m }
    }

    func setTab(_ t: AppTab) { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = t } }

    func toast(_ msg: String, kind: ToastItem.Kind = .ok, undo: (() -> Void)? = nil) {
        let t = ToastItem(msg: msg, kind: kind, undo: undo)
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.38)) { toasts = [t] }
        if kind == .error { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        else if undo != nil { UINotificationFeedbackGenerator().notificationOccurred(.warning) }   // make undoable deletes and changes felt
        let life: Double = undo != nil ? 5 : (kind == .error ? 6 : 2.4)   // keep errors readable
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(life))
            withAnimation(.easeIn(duration: 0.28)) { toasts.removeAll { $0.id == t.id } }
        }
    }
    func dismissToast(_ t: ToastItem) { withAnimation(.easeIn(duration: 0.2)) { toasts.removeAll { $0.id == t.id } } }
}

struct ToastOverlay: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(spacing: 8) {
            ForEach(app.toasts) { t in
                HStack(spacing: 8) {
                    switch t.kind {
                    case .delete: Ti("trash").foregroundStyle(Color.bMutedFg)
                    case .error: Ti("alert-circle").foregroundStyle(Color.bDestructive)
                    case .ok: Ti("check").foregroundStyle(Color.bPrimary)
                    }
                    Text(tl(t.msg)).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(t.kind == .error ? 3 : 1).foregroundStyle(Color.bFg)
                    if let u = t.undo {
                        Button { u(); app.dismissToast(t); haptic() } label: {
                            Text("Geri al").font(.geist(14, .semibold, relativeTo: .subheadline)).padding(.horizontal, 14).frame(minHeight: 44)   // 44 pt touch target
                                .background(Color.bFg.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.press).foregroundStyle(Color.bFg)
                    }
                }
                .padding(.leading, 16).padding(.trailing, t.undo == nil ? 16 : 8).padding(.vertical, t.undo == nil ? 10 : 8)
                .bGlass(Capsule())
                .modifier(ToastDrag(top: app.sheetOpen) { app.dismissToast(t) })
                .transition(.move(edge: app.sheetOpen ? .top : .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: app.sheetOpen ? .top : .bottom)
        .padding(.bottom, app.sheetOpen ? 0 : 64)
        .padding(.top, app.sheetOpen ? 10 : 0)
        .allowsHitTesting(!app.toasts.isEmpty)
    }
}


/// Dismiss a toast by pushing it toward its edge (down at the bottom, up at the top)
private struct ToastDrag: ViewModifier {
    var top: Bool
    var dismiss: () -> Void
    @State private var dy: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .offset(y: dy)
            .opacity(1.0 - min(0.6, Double(abs(dy)) / 120.0))
            .gesture(DragGesture(minimumDistance: 6)
                .onChanged { v in
                    let d = v.translation.height
                    dy = top ? min(0, d) + max(0, d) * 0.15 : max(0, d) + min(0, d) * 0.15
                }
                .onEnded { v in
                    let d = v.predictedEndTranslation.height
                    if (top && d < -40) || (!top && d > 40) { haptic(); dismiss() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dy = 0 }
                })
    }
}
