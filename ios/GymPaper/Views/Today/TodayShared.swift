import SwiftUI
import SwiftData
import GymPaperKit

// Parts shared by Today and Profile

private var trMonths: [String] { DayKey.monthLong }
private func keyParts(_ k: String) -> [Int]? { let p = k.split(separator: "-").compactMap { Int($0) }; return p.count == 3 ? p : nil }
/// "24 Ekim 2026"
func trLongDate(_ k: String) -> String { guard let p = keyParts(k), (1...12).contains(p[1]) else { return "–" }; return "\(p[2]) \(trMonths[p[1] - 1]) \(p[0])" }
/// "Ekim 2026"
func trMonthYear(_ k: String) -> String { guard let p = keyParts(k), (1...12).contains(p[1]) else { return "–" }; return "\(trMonths[p[1] - 1]) \(p[0])" }
/// "24 Oct"
func trShortDate(_ k: String) -> String { guard let p = keyParts(k), (1...12).contains(p[1]) else { return "–" }; return "\(p[2]) \(DayKey.monthShort[p[1] - 1])" }
/// "72,5" → 72.5
func trNum(_ s: String) -> Double {
    var t = s.trimmingCharacters(in: .whitespaces)
    // with both comma and dot, the last one is the decimal separator, the other thousands ("1.234,5" / "1,234.5")
    if let c = t.lastIndex(of: ","), let p = t.lastIndex(of: ".") {
        t = t.replacingOccurrences(of: c > p ? "." : ",", with: "")
    }
    guard let d = Double(t.replacingOccurrences(of: ",", with: ".")), d.isFinite else { return 0 }
    return d
}

/// Appearance preference (Profile › Appearance): system / light / dark
struct GymPaperThemeModifier: ViewModifier {
    @AppStorage("gympaper-theme") private var theme = "system"
    func body(content: Content) -> some View {
        content.preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}

extension View { func gymPaperTheme() -> some View { modifier(GymPaperThemeModifier()) } }

/// Section title
struct ProfileSectionTitle<A: View>: View {
    let title: String
    @ViewBuilder var action: A
    var body: some View {
        HStack(spacing: 8) {
            Text(tl(title)).font(.bDisplay(20, relativeTo: .title3)).foregroundStyle(Color.bFg)
            Spacer()
            action
        }
        .frame(minHeight: 28)
        // sit close to the card below (BScreen spacing 16 → ~8)
        .padding(.top, 12).padding(.bottom, -6)
    }
}
extension ProfileSectionTitle where A == EmptyView { init(_ title: String) { self.title = title; self.action = EmptyView() } }
extension ProfileSectionTitle { init(_ title: String, @ViewBuilder action: () -> A) { self.title = title; self.action = action() } }

/// Value like "1.5 / 2.5 L": big number + small unit
struct TodayValue: View {
    let value: String; let suffix: String
    var size: CGFloat = 20
    var body: some View {
        (Text(value).font(.bNum(size)).foregroundStyle(Color.bFg)
         + Text(tl(suffix)).font(.bXs).foregroundStyle(Color.bMutedFg))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: value)
    }
}

// MARK: - Weight goal celebration

/// Full-screen celebration for a reached but not yet celebrated weight goal
struct GoalCelebrationOverlay: ViewModifier {
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \BodyMeasure.date) private var measures: [BodyMeasure]
    @AppStorage("gympaper-celebrated") private var celebratedJSON = "[]"
    /// The share image is rendered once (not on every draw)
    @State private var shareImg: Image?

    private var celebrated: Set<Double> { Set((try? JSONDecoder().decode([Double].self, from: Data(celebratedJSON.utf8))) ?? []) }

    func body(content: Content) -> some View {
        let p = profiles.first
        let G = GoalState(startKg: p?.startKg, goals: p?.goals ?? [], measures: measures)
        // a goal above the start weight isn't celebrated as "reached"
        let pend = Gamify.pendingGoals(goals: G.goals.filter { $0 < (G.start ?? .infinity) }, celebrated: celebrated, cur: G.cur, hasMeasure: !G.pts.isEmpty)
        let busy = app.sheet != nil || app.session != nil
        content.overlay {
            if let goal = pend.first, !busy, let cur = G.cur {
                celebration(goal: goal, G: G, cur: cur, name: p?.name ?? "") {
                    var s = celebrated; pend.forEach { s.insert($0) }
                    celebratedJSON = String(data: (try? JSONEncoder().encode(Array(s))) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func celebration(goal: Double, G: GoalState, cur: Double, name: String, done: @escaping () -> Void) -> some View {
        let next = G.goals.filter { $0 < goal && cur > $0 }.max()
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.bBg.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 16) {
                Circle().fill(Color.bPrimary.opacity(0.15)).frame(width: 96, height: 96)
                    .overlay(Ti("trophy", size: 48).foregroundStyle(Color.bPrimary))
                Text("\(fmt1(goal)) kg hedefine ulaştın!").font(.geist(30, .semibold, relativeTo: .largeTitle)).multilineTextAlignment(.center)
                    .foregroundStyle(Color.bFg)
                Text(G.start.map { String(localized: "\(fmt1($0)) → \(fmt1(cur)) kg · toplam \(fmt1($0 - cur)) kg") } ?? String(localized: "Şu an \(fmt1(cur)) kg"))
                    .font(.geist(16)).foregroundStyle(Color.bMutedFg).monospacedDigit()
                if let next {
                    (Text("Sıradaki durak: ") + Text("\(fmt1(next)) kg").font(.geist(14, .semibold))).font(.bSm).foregroundStyle(Color.bFg)
                }
                VStack(spacing: 8) {
                    if let img = shareImg {
                        ShareLink(item: img, preview: SharePreview("\(fmt1(goal)) kg hedefine ulaştım", image: img)) {
                            BLabel("Paylaş", icon: "share").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.b(.primary, .large, full: true))
                    }
                    Button("Devam et") { withAnimation { done() } }.buttonStyle(.b(.ghost, .large, full: true))
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 384)
            .padding(24)
        }
        // realistic confetti + haptic
        .overlay { ConfettiBurst().id(goal).ignoresSafeArea() }
        .task(id: goal) { shareImg = shareImage(goal: goal, start: G.start, cur: cur, name: name) }
    }

    @MainActor private func shareImage(goal: Double, start: Double?, cur: Double, name: String) -> Image? {
        let card = VStack(alignment: .leading, spacing: 0) {
            Text("GYM PAPER").font(.geist(44, .semibold)).foregroundStyle(Color(red: 0.98, green: 0.57, blue: 0.24))
            Spacer()
            Text("\(fmt1(goal)) kg").font(.geist(150, .bold)).foregroundStyle(.white).minimumScaleFactor(0.5)
            Text("hedefine ulaştım").font(.geist(64, .medium)).foregroundStyle(.white.opacity(0.85))
            if let start {
                Text("\(fmt1(start)) → \(fmt1(cur)) kg").font(.geist(56, .semibold)).foregroundStyle(Color(red: 0.99, green: 0.73, blue: 0.45)).padding(.top, 140)
                Text("toplam \(fmt1(start - cur)) kg").font(.geist(44, .medium)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("\(name.isEmpty ? "" : name + " · ")\(trLongDate(DayKey.today))").font(.geist(40, .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(96)
        .frame(width: 1080, height: 1350, alignment: .leading)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.10, blue: 0.09), Color(red: 0.49, green: 0.18, blue: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
        let r = ImageRenderer(content: card)
        r.scale = 1
        guard let ui = r.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}
extension View { func goalCelebration() -> some View { modifier(GoalCelebrationOverlay()) } }
