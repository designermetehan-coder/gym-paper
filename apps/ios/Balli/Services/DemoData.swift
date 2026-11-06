#if DEBUG
import Foundation
import SwiftUI
import UIKit
import SwiftData
import BalliKit

/// Yalnız geliştirme: `-demo` başlatma argümanıyla örnek veri; `-tab workout|food|profile` ile sekme.
/// CI simülatör ekran görüntüleri bunu kullanır.
@MainActor
enum DemoData {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    /// `-onboarding`: ilk açılış akışı (`-onbStep N` ile adım); `-empty`: örnek veri yok (boş durumlar)
    static var onboarding: Bool { ProcessInfo.processInfo.arguments.contains("-onboarding") }
    /// `-shot <anahtar>`: Figma için belirli sheet ya da durumu açar (bkz. figma-shots.command)
    static var shot: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-shot"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static func seedIfRequested(ctx: ModelContext, app: AppState) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = AppTab(rawValue: args[i + 1]) { app.tab = t }
        guard args.contains("-demo"), !args.contains("-empty"), !onboarding else { return }
        defer { if args.contains("-session") { app.session = .init(pid: "demo-upper", date: DayKey.today) } }
        let p = Store.profile(ctx)
        if args.contains("-year") {   // 365 günlük tablo için geçmiş (YR-01)
            UserDefaults.standard.set(#"[{"kind":"year","size":"wide"},{"kind":"workout","size":"wide"}]"#, forKey: "today.widgets")
            if Store.day(ctx, DayKey.shift(DayKey.today, days: -300))?.steps == 0 {
                var seed: UInt64 = 42
                func rnd() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % 100) }
                for i in 1...364 {
                    guard let d = Store.day(ctx, DayKey.shift(DayKey.today, days: -i)) else { continue }
                    let wd = DayKey.weekday(d.date), ramp = i < 200 ? 15 : 0
                    d.workoutDone = [0, 1, 3, 4].contains(wd) ? rnd() < 55 + ramp : rnd() < 8
                    let r = rnd() + ramp
                    d.steps = r < 15 ? 1800 + rnd() * 10 : r < 40 ? 3500 + rnd() * 10 : r < 75 ? 6500 + rnd() * 20 : 10500 + rnd() * 30
                }
                Store.save(ctx)
            }
        }
        // Bugünün örnek kaydı her açılışta tamamlanır: simülatördeki veri önceki günden kaldıysa ekranlar boş görünmesin
        defer { seedToday(ctx) }
        guard Store.programs(ctx).isEmpty else { return }
        // İngilizce ekran görüntülerinde (-AppleLanguages (en)) örnek veriler de İngilizce
        let en = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
        func dl(_ tr: String, _ eng: String) -> String { en ? eng : tr }
        p.name = "Metehan"; p.startKg = 92; p.goals = [85, 80]; p.heightCm = 182
        p.birthDate = Calendar.current.date(from: DateComponents(year: 1990, month: 5, day: 1)); p.sex = .male
        p.proteinG = 150; p.carbsG = 180; p.fatG = 60; p.waterMl = 2500; p.waterStepMl = 500; p.stepGoal = 10000

        func ex(_ n: String, _ s: Int, _ r: Int, _ kg: Double?, rest: Int = 90, m: String = "") -> Exercise { Exercise(name: n, sets: s, reps: r, rest: rest, kg: kg, muscle: m) }
        let upper = WorkoutProgram(pid: "demo-upper", name: dl("Üst vücut", "Upper body"), blocks: [
            Block(single: ex(dl("Barfiks", "Pull up"), 4, 6, nil, m: dl("Sırt", "Back"))),
            Block(single: ex("Bench press", 4, 8, 60, m: dl("Göğüs", "Chest"))),
            Block(single: ex("Dumbbell fly", 3, 12, 10, rest: 60, m: dl("Göğüs", "Chest"))),
            Block(superset: [ex(dl("Omuz press", "Seated dumbbell shoulder press"), 3, 10, 16, m: dl("Omuz", "Shoulders")), ex(dl("Kablo row", "Seated cable row"), 3, 12, 40, m: dl("Sırt", "Back"))], rounds: 3, rest: 75),
            Block(single: ex(dl("Biceps curl", "Dumbbell curl"), 3, 12, 12, rest: 60, m: dl("Kol", "Arms"))),
        ])
        upper.short = dl("Üst", "Upper")
        let lower = WorkoutProgram(pid: "demo-lower", name: dl("Alt vücut", "Lower body"), blocks: [
            Block(single: ex("Squat", 4, 6, 80, rest: 120, m: dl("Bacak", "Legs"))),
            Block(single: ex("Romanian deadlift", 3, 10, 60, m: dl("Arka bacak", "Hamstrings"))),
            Block(single: ex("Leg press", 3, 12, 120, m: dl("Bacak", "Legs"))),
            Block(single: ex("Plank", 3, 45, nil, rest: 45, m: dl("Karın", "Core"))),
        ])
        lower.short = dl("Alt", "Lower")
        ctx.insert(upper); ctx.insert(lower)
        let monday = DayKey.shift(DayKey.today, days: -DayKey.weekday(DayKey.today))
        p.schedule = [ScheduleEntry(from: monday, days: ["0": "demo-upper", "1": "demo-lower", "3": "demo-upper", "4": "demo-lower"])]

        for i in 1...10 { ctx.insert(BodyMeasure(date: Calendar.current.date(byAdding: .day, value: -i * 3, to: .now)!, kg: 88 + Double(i) * 0.4)) }
        Store.save(ctx)
    }

    /// Bugün boşsa örnek su, adım ve öğünler (mağaza görselleri)
    private static func seedToday(_ ctx: ModelContext) {
        guard let d = Store.day(ctx, DayKey.today), d.entries.isEmpty else { return }
        d.waterMl = 1500; d.steps = 6420
        // İngilizce ekran görüntülerinde (-AppleLanguages (en)) örnek öğünler de İngilizce
        let en = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
        func dl(_ tr: String, _ eng: String) -> String { en ? eng : tr }
        d.entries = [
            FoodEntry(meal: .kahvalti, name: dl("Yumurta", "Eggs"), foodName: dl("Yumurta", "Eggs"), g: 120, per100: Macros(kcal: 155, p: 13, c: 1.1, f: 11)),
            FoodEntry(meal: .kahvalti, name: dl("Tam buğday ekmeği", "Whole wheat bread"), foodName: dl("Tam buğday ekmeği", "Whole wheat bread"), g: 60, per100: Macros(kcal: 250, p: 10, c: 43, f: 3.5)),
            FoodEntry(meal: .ogle, name: dl("Tavuk göğsü", "Chicken breast"), foodName: dl("Tavuk göğsü", "Chicken breast"), g: 200, per100: Macros(kcal: 165, p: 31, c: 0, f: 3.6)),
            FoodEntry(meal: .ogle, name: dl("Bulgur pilavı", "Bulgur pilaf"), foodName: dl("Bulgur pilavı", "Bulgur pilaf"), g: 150, per100: Macros(kcal: 150, p: 4, c: 28, f: 3)),
        ]
        Store.save(ctx)
    }
}

// MARK: - Kapak videosu gezintisi
extension Notification.Name { static let tourCompleteSet = Notification.Name("tourCompleteSet") }

/// Portfolyo kapak videosu için otomatik gezinti: `-demo -tour` ile açılır (ios/tour.command).
/// Özet'te kaydırır, Antrenman ve Beslenme sekmelerine geçer; dokunuşlar ekranda yarı saydam halka olarak görünür.
@Observable @MainActor
final class TourTouch {
    static let shared = TourTouch()
    var point: CGPoint?
    var pressed = false
    var visible = false
}

@MainActor
enum DemoTour {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("-tour") }

    private static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static func run(app: AppState, ctx: ModelContext) async {
        let b = UIScreen.main.bounds
        let W = b.width, H = b.height
        func x(_ v: CGFloat) -> CGFloat { v / 402 * W }
        func y(_ v: CGFloat) -> CGFloat { v / 874 * H }
        if ProcessInfo.processInfo.arguments.contains("-tourLong") { await runLong(app: app, ctx: ctx, x: x, y: y); return }
        await wait(2.2)
        // Yediğini ekle → besin ekleme ekranı
        await tap(CGPoint(x: x(175), y: y(532))) { app.open(.addFood(date: DayKey.today, meal: nil)) }
        await wait(2.2)
        await drag(from: CGPoint(x: x(200), y: y(140)), dy: y(420), dur: 0.7, scroll: false)
        app.sheet = nil
        await wait(1.0)
        // Başlat → oynatıcı (bildirim izni sorulmadan)
        await tap(CGPoint(x: x(175), y: y(280))) {
            if let prog = Store.program(for: DayKey.today, profile: Store.profile(ctx), ctx: ctx) {
                let s = AppState.SessionRef(pid: prog.pid, date: DayKey.today)
                app.rt.use(s.id)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { app.session = s; app.sessionMin = false }
            }
        }
        await wait(1.8)
        // Seti tamamla → dinlenme geri sayımı
        await tap(CGPoint(x: x(316), y: y(685))) { NotificationCenter.default.post(name: .tourCompleteSet, object: nil) }
    }

    /// Duyuru videosu için uzun gezinti (yazısız): Özet → kaydır → Antrenman → Beslenme → Profil → oynatıcı → dinlenme
    static func runLong(app: AppState, ctx: ModelContext, x: (CGFloat) -> CGFloat, y: (CGFloat) -> CGFloat) async {
        let tabY = y(824)
        func tab(_ t: AppTab, _ px: CGFloat) async { await tap(CGPoint(x: x(px), y: tabY)) { withAnimation(.snappy) { app.tab = t } } }
        await wait(1.6)
        await drag(from: CGPoint(x: x(220), y: y(640)), dy: -y(380), dur: 0.8)
        await wait(0.6)
        await drag(from: CGPoint(x: x(220), y: y(300)), dy: y(380), dur: 0.7)
        await tab(.workout, 132); await wait(1.4)
        await tab(.food, 200); await wait(1.0)
        await drag(from: CGPoint(x: x(220), y: y(640)), dy: -y(300), dur: 0.7)
        await wait(0.5)
        await tab(.profile, 338); await wait(1.4)
        await tab(.today, 63); await wait(0.6)
        // Oynatıcı
        await tap(CGPoint(x: x(200), y: y(260))) {
            let s = AppState.SessionRef(pid: "demo-upper", date: DayKey.today)
            app.rt.use(s.id)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { app.session = s; app.sessionMin = false }
        }
        await wait(1.8)
        await tap(CGPoint(x: x(316), y: y(685))) { NotificationCenter.default.post(name: .tourCompleteSet, object: nil) }
        await wait(2.5)
    }

    static func tap(_ p: CGPoint, _ action: () -> Void) async {
        let t = TourTouch.shared
        t.point = p; t.pressed = false
        withAnimation(.easeOut(duration: 0.18)) { t.visible = true }
        await wait(0.22)
        withAnimation(.easeOut(duration: 0.12)) { t.pressed = true }
        await wait(0.12)
        action()
        withAnimation(.easeOut(duration: 0.15)) { t.pressed = false }
        await wait(0.12)
        withAnimation(.easeIn(duration: 0.25)) { t.visible = false }
        await wait(0.25)
    }

    static func drag(from p: CGPoint, dy: CGFloat, dur: Double, scroll: Bool = true) async {
        let t = TourTouch.shared
        t.point = p; t.pressed = true
        withAnimation(.easeOut(duration: 0.15)) { t.visible = true }
        await wait(0.18)
        if scroll, let sv = activeScrollView() {
            let maxY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
            let y = min(maxY, sv.contentOffset.y - dy)
            UIView.animate(withDuration: dur, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                sv.contentOffset.y = y
            }
        }
        withAnimation(.easeInOut(duration: dur)) { t.point = CGPoint(x: p.x, y: p.y + dy) }
        await wait(dur)
        withAnimation(.easeIn(duration: 0.25)) { t.visible = false; t.pressed = false }
        await wait(0.25)
    }

    /// Ekranda görünen en büyük dikey kaydırma görünümü (seçili sekmenin listesi)
    private static func activeScrollView() -> UIScrollView? {
        guard let win = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        var best: (UIScrollView, CGFloat)?
        func visible(_ v: UIView) -> Bool {
            var c: UIView? = v
            while let x = c { if x.isHidden || x.alpha < 0.01 { return false }; c = x.superview }
            return true
        }
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, visible(s), s.contentSize.height > s.bounds.height + 40, s.bounds.height > 300 {
                let r = s.convert(s.bounds, to: win).intersection(win.bounds)
                if !r.isNull, r.contains(CGPoint(x: win.bounds.midX, y: win.bounds.midY)) {
                    let area = r.width * r.height
                    if area > (best?.1 ?? 0) { best = (s, area) }
                }
            }
            v.subviews.forEach(walk)
        }
        walk(win)
        return best?.0
    }
}

/// Dokunma halkası (iOS simülatöründeki parmak izine benzer)
struct TourTouchOverlay: View {
    @State private var t = TourTouch.shared
    var body: some View {
        GeometryReader { _ in
            if let p = t.point {
                Circle()
                    .fill(Color.black.opacity(0.28))
                    .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .frame(width: 50, height: 50)
                    .scaleEffect(t.pressed ? 0.82 : 1)
                    .opacity(t.visible ? 1 : 0)
                    .position(p)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
#endif
