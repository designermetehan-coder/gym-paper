import SwiftUI

// Uygulama kabuğu: yüzen cam tab bar + cam toast (PWA App.jsx / Toasts ile aynı)

enum AppTab: String, CaseIterable, Hashable {
    case today, workout, food, social, profile
    /// Sosyal (arkadaşlarla adım sıralaması) 1.1'de kapalı; sunucu (Supabase) gerektirdiği için 1.2'ye kaldı
    static let socialEnabled = false
    var label: String { switch self { case .today: tl("Özet"); case .workout: tl("Antrenman"); case .food: tl("Beslenme"); case .social: tl("Sosyal"); case .profile: tl("Profil") } }
    /// Yerel tab bar SF Symbol'ü (seçilince sistem animasyonu)
    var symbol: String { switch self { case .today: "circle.circle"; case .workout: "dumbbell"; case .food: "fork.knife.circle"; case .social: "person.2"; case .profile: "person.crop.circle" } }
}

struct ToastItem: Identifiable, Equatable {
    enum Kind { case ok, delete, error }
    let id = UUID()
    var msg: String
    var kind: Kind = .ok
    var undo: (() -> Void)?
    static func == (a: ToastItem, b: ToastItem) -> Bool { a.id == b.id }
}

/// Seans çalışma durumu: oynatıcı sheet'i kapanıp açılınca kaldığı yerden devam etsin
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
    /// Geçerli adımın kimliği ("hareketId#set"): program düzenlenince idx yeniden bulunur (QA-07)
    var stepKey: String?
    /// Dinlenme bildiriminde yazacak sıradaki set (QA-11)
    var restNext: String?
    func use(_ k: String) {
        guard key != k else { return }
        key = k; idx = -1; rest = nil; timer = nil; finished = false; kg = 0; reps = 0; stepKey = nil
    }
}

/// Ekranlar arası ortak durum: sekme, toast, seans
@MainActor
@Observable
final class AppState {
    var tab: AppTab = .today
    var toasts: [ToastItem] = []
    /// Açık antrenman seansı (program id + gün)
    var session: SessionRef?
    /// Her ekrandan açılan sheet (PWA open())
    var sheet: AppSheet? { didSet { sheetOpen = sheet != nil } }
    /// Sheet açıkken toast üstte görünür
    var sheetOpen = false
    func open(_ s: AppSheet) { sheet = s }

    struct SessionRef: Identifiable, Equatable, Hashable { var pid: String; var date: String; var id: String { pid + date } }
    /// Antrenman sekmesinin gezinme yolu (Antrenmanlarım, program düzenleme tam ekran açılır)
    var workoutPath: [WkRoute] = []
    /// Seans küçültüldü: tab bar'ın üstünde mini oynatıcı
    var sessionMin = false
    /// Seansın kalıcı çalışma durumu
    let rt = SessionRuntime()
    /// Mini oynatıcının gösterdiği anlık seans bilgisi (SessionView yazar)
    var sessionNow: SessionNow?
    struct SessionNow: Equatable {
        var program: String
        var exercise: String
        var detail: String          // "Set 2/4" ya da "Dinlenme"
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
    /// Başka bir seans açıkken yenisi istenirse önce sorulur (QA-06)
    var switchTo: SessionRef?
    func openSession(_ s: SessionRef, force: Bool = false) {
        if let cur = session, cur != s, !force { switchTo = s; return }
        if session != s { sessionNow = nil }   // önceki seansın bilgisi kalmasın (WK-06/11)
        #if !LITE
        RestAlarm.requestPermission()
        #endif
        rt.use(s.id)   // çalışma durumu görünüm açılmadan doğru seansa geçsin (QA-06)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { session = s; sessionMin = false }
    }
    /// Gün dışarıdan tamamlandı/işaret kaldırıldı: o günün açık seansı kapansın (QA-08)
    func endSessionIfOn(_ date: String) { if session?.date == date { closeSession() } }
    func closeSession() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { session = nil; sessionMin = false; sessionNow = nil }
        rt.use("")   // yeniden açınca eski dinlenme/bip geri gelmesin (WK-10)
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
        else if undo != nil { UINotificationFeedbackGenerator().notificationOccurred(.warning) }   // geri alınabilir silme/değişiklik hissedilsin (IY-04)
        let life: Double = undo != nil ? 5 : (kind == .error ? 6 : 2.4)   // hata okunabilsin (CR-35)
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
                            Text("Geri al").font(.geist(14, .semibold, relativeTo: .subheadline)).padding(.horizontal, 14).frame(minHeight: 44)   // 44 pt dokunma (CR-35)
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


/// Toast'ı kenarına doğru (alttaysa aşağı, üstteyse yukarı) iterek kapat
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
