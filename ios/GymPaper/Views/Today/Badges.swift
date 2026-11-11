import SwiftUI
import SwiftData
import GymPaperKit

// Streak, badges and milestones (Figma "Streak card", "Milestones", "Badge celebration").

struct BadgeDef: Identifiable, Hashable {
    enum Group: String, CaseIterable { case streak, nutrition, workout }
    let id: String
    let group: Group
    let title: String
    let sub: String
    let symbol: String
    let mark: String?
}

struct BadgeState: Identifiable {
    let def: BadgeDef
    let earned: Bool
    var id: String { def.id }
}

/// Everything the streak card and milestones need, computed from the log in one pass
struct GameSummary {
    var streak: Gamify.Streak
    var longest: Int
    var week: [(key: String, active: Bool, frozen: Bool)]
    var badges: [BadgeState]
    var earnedCount: Int { badges.filter(\.earned).count }

    static let defs: [BadgeDef] = [
        BadgeDef(id: "streak3", group: .streak, title: tl("Isınma"), sub: tl("3 günlük seri"), symbol: "flame.fill", mark: "3"),
        BadgeDef(id: "streak10", group: .streak, title: tl("Ciddi"), sub: tl("10 günlük seri"), symbol: "flame.fill", mark: "10"),
        BadgeDef(id: "streak30", group: .streak, title: tl("Alışkanlık"), sub: tl("30 günlük seri"), symbol: "flame.fill", mark: "30"),
        BadgeDef(id: "meal1", group: .nutrition, title: tl("İlk tabak"), sub: tl("İlk öğün kaydı"), symbol: "fork.knife", mark: nil),
        BadgeDef(id: "protein7", group: .nutrition, title: tl("Protein haftası"), sub: tl("7 gün protein hedefi"), symbol: "flame.fill", mark: "7"),
        BadgeDef(id: "water3", group: .nutrition, title: tl("Kolay"), sub: tl("3 gün su hedefi"), symbol: "drop.fill", mark: nil),
        BadgeDef(id: "workout1", group: .workout, title: tl("İlk antrenman"), sub: tl("İlk antrenmanı bitir"), symbol: "dumbbell.fill", mark: nil),
        BadgeDef(id: "workout10", group: .workout, title: tl("On antrenman"), sub: tl("10 antrenman"), symbol: "dumbbell.fill", mark: "10"),
        BadgeDef(id: "workout50", group: .workout, title: tl("Elli antrenman"), sub: tl("50 antrenman"), symbol: "dumbbell.fill", mark: "50"),
    ]

    @MainActor static func build(ctx: ModelContext, profile: UserProfile, todaySteps: Int) -> GameSummary {
        let days = Wk.allDays(ctx)
        let logs = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let input = GamifyInput(logs: logs, stepGoal: profile.stepGoal, proteinGoal: profile.proteinG, waterGoal: profile.waterMl,
                                freezes: GameStore.freezes, plannedOn: { _ in false }, todaySteps: todaySteps)
        let today = DayKey.today
        let streak = Gamify.streak(input, today: today)
        if !streak.pending.isEmpty { GameStore.freezes.merge(streak.pending) { a, _ in a } }
        // Longest run of active days in the log (freezes ignored)
        var longest = 0, run = 0
        for k in logs.keys.sorted() {
            if input.isActive(k) {
                let prev = DayKey.shift(k, days: -1)
                run = (run > 0 && input.isActive(prev)) ? run + 1 : 1
                longest = max(longest, run)
            } else { run = 0 }
        }
        longest = max(longest, streak.count)
        let monday = DayKey.shift(today, days: -DayKey.weekday(today))
        let week = (0..<7).map { i -> (String, Bool, Bool) in
            let k = DayKey.shift(monday, days: i)
            return (k, k <= today && input.isActive(k), streak.frozen.contains(k))
        }
        func longestRun(_ ok: (DayLog) -> Bool) -> Int {
            var best = 0, cur = 0, last = ""
            for k in logs.keys.sorted() {
                guard let L = logs[k] else { continue }
                if ok(L) { cur = (cur > 0 && DayKey.shift(last, days: 1) == k) ? cur + 1 : 1; best = max(best, cur); last = k } else { cur = 0 }
            }
            return best
        }
        let workouts = days.filter(\.workoutDone).count
        let earned: [String: Bool] = [
            "streak3": longest >= 3, "streak10": longest >= 10, "streak30": longest >= 30,
            "meal1": days.contains { !$0.entries.isEmpty },
            "protein7": profile.proteinG > 0 && longestRun { $0.eaten.p >= profile.proteinG * 0.9 } >= 7,
            "water3": profile.waterMl > 0 && longestRun { $0.waterMl >= profile.waterMl } >= 3,
            "workout1": workouts >= 1, "workout10": workouts >= 10, "workout50": workouts >= 50,
        ]
        let badges = defs.map { BadgeState(def: $0, earned: earned[$0.id] ?? false) }
        return GameSummary(streak: streak, longest: longest, week: week.map { (key: $0.0, active: $0.1, frozen: $0.2) }, badges: badges)
    }
}

/// Small persistent game state (on device)
enum GameStore {
    static var freezes: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "gamify.freezes") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "gamify.freezes") }
    }
    static var celebrated: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "gamify.celebrated") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "gamify.celebrated") }
    }
    static let celebrateKey = "gamify.celebrate"
}

// MARK: - Hexagon badge

struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.25))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.75))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.75))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.25))
        p.closeSubpath()
        _ = w
        return p
    }
}

struct BadgeHex: View {
    let def: BadgeDef
    let earned: Bool
    var size: CGFloat = 76
    var body: some View {
        let tint = color
        ZStack {
            Hexagon().fill(earned ? tint : Color.bFg.opacity(0.10))
            Hexagon().inset(by: size * 0.08).fill(earned ? Color.white.opacity(0.18) : Color.clear)
            VStack(spacing: 0) {
                Image(systemName: def.symbol).font(.system(size: size * 0.3, weight: .semibold))
                if let m = def.mark { Text(m).font(.bNum(size * 0.18)) }
            }
            .foregroundStyle(earned ? Color.white : Color.bMutedFg)
        }
        .frame(width: size * 0.92, height: size)
        .accessibilityHidden(true)
    }
    private var color: Color {
        switch def.group {
        case .streak: Color(uiColor: .dyn(UIColor(hex: 0xD73F00), UIColor(hex: 0xFE7802)))
        case .nutrition: .fitKcal
        case .workout: .fitBlue
        }
    }
}

extension Hexagon: InsettableShape {
    func inset(by amount: CGFloat) -> InsetHexagon { InsetHexagon(amount: amount) }
}
struct InsetHexagon: InsettableShape {
    var amount: CGFloat
    func path(in r: CGRect) -> Path { Hexagon().path(in: r.insetBy(dx: amount, dy: amount)) }
    func inset(by a: CGFloat) -> InsetHexagon { InsetHexagon(amount: amount + a) }
}

// MARK: - Streak chip + card (Nutrition header)

struct StreakChip: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(red: 0.98, green: 0.47, blue: 0.01))
            Text("\(count)").font(.bNum(17)).foregroundStyle(Color.bFg).contentTransition(.numericText())
        }
        .padding(.horizontal, 12).frame(height: 44)
        .modifier(BGlassCapsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count) günlük seri"))
    }
}

struct BGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.glassEffect(.regular.interactive(), in: Capsule()) }
        else { content.background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Color.bFg.opacity(0.08), lineWidth: 1)) }
    }
}

struct StreakCard: View {
    let g: GameSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(g.streak.count)").font(.bNum(40, relativeTo: .largeTitle)).foregroundStyle(Color.bHeroAccent)
                        Text("günlük seri").font(.bDisplay(20, relativeTo: .title3))
                    }
                    Text(String(localized: "En uzun \(g.longest) gün · \(g.streak.freezeReady ? 1 : 0) joker")).font(.bXs).foregroundStyle(Color.bHeroMuted)
                }
                Spacer()
                Image(systemName: "flame").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.bHeroAccent)
                    .frame(width: 52, height: 52).background(Color.bHeroFill, in: Circle())
            }
            HStack(spacing: 0) {
                ForEach(Array(g.week.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 6) {
                        Text(String(DayKey.dayShort[i].prefix(1))).font(.geist(11, .medium, relativeTo: .caption2)).foregroundStyle(Color.bHeroMuted)
                        ZStack {
                            Circle().fill(d.active || d.frozen ? Color.bHeroHi : Color.bHeroFill)
                            if d.key == DayKey.today && d.active { Image(systemName: "flame").foregroundStyle(Color.bHeroOnHi) }
                            else if d.frozen { Image(systemName: "moon.fill").foregroundStyle(Color.bHeroOnHi) }
                            else if d.active { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.bHeroOnHi) }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            Text("Her gün bir öğün ya da antrenman kaydet. Dinlenme günleri seriyi bozmaz; her hafta 1 jokerin var.")
                .font(.bSm).foregroundStyle(Color.bHeroMuted)
        }
        .bHeroCard()
    }
}

// MARK: - Milestones

struct MilestonesScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var g: GameSummary?

    var body: some View {
        BScreen(pinHeader: false) {
            WkPushedHeader(title: "Rozetler")
            if let g {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "flame").foregroundStyle(Color.bHeroAccent).frame(width: 32, height: 32).background(Color.bHeroFill, in: Circle())
                        HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(g.streak.count)").font(.bNum(30)); Text("gün").font(.bXs).foregroundStyle(Color.bHeroMuted) }
                        Text(String(localized: "En uzun seri \(g.longest) gün")).font(.bXs).foregroundStyle(Color.bHeroMuted)
                    }
                    .bHeroCard(padding: 16)
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "trophy.fill").foregroundStyle(Color.fitPurple).frame(width: 32, height: 32).background(Color.fitPurple.opacity(0.14), in: Circle())
                        HStack(alignment: .firstTextBaseline, spacing: 2) { Text("\(g.earnedCount)").font(.bNum(30)); Text("/\(g.badges.count)").font(.bXs).foregroundStyle(Color.bMutedFg) }
                        Text("kazanılan rozet").font(.bXs).foregroundStyle(Color.bMutedFg)
                        BProgress(value: Double(g.earnedCount) / Double(max(1, g.badges.count)), height: 5, label: "Rozetler")
                    }
                    .foregroundStyle(Color.bFg)
                    .bCard(padding: 16)
                }
                BadgeGrid(g: g)
            }
        }
        .onAppear { g = GameSummary.build(ctx: ctx, profile: profiles.first ?? UserProfile(), todaySteps: health.stepsToday) }
    }
}

/// Badges by group (Milestones screen and the streak sheet)
struct BadgeGrid: View {
    let g: GameSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
        ForEach(BadgeDef.Group.allCases, id: \.self) { grp in
            VStack(alignment: .leading, spacing: 12) {
                Text(title(grp)).font(.bDisplay(20, relativeTo: .title3)).foregroundStyle(Color.bFg)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(g.badges.filter { $0.def.group == grp }) { b in
                        VStack(spacing: 6) {
                            BadgeHex(def: b.def, earned: b.earned)
                            Text(b.earned ? b.def.title : tl("Kilitli")).font(.bDisplay(14, relativeTo: .subheadline))
                                .foregroundStyle(b.earned ? Color.bFg : Color.bMutedFg)
                            Text(b.def.sub).font(.bXs).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(b.def.title), \(b.def.sub)"))
                        .accessibilityValue(b.earned ? tl("Kazanıldı") : tl("Kilitli"))
                    }
                }
            }
        }
        }
    }
    private func title(_ g: BadgeDef.Group) -> String {
        switch g { case .streak: tl("Seri"); case .nutrition: tl("Beslenme"); case .workout: tl("Antrenman") }
    }
}

/// Opened from the streak chip (Today): streak card, next badge, all badges
struct StreakSheet: View {
    let g: GameSummary
    var body: some View {
        BSheet(title: "Seri") {
            StreakCard(g: g)
            if let next = g.badges.first(where: { !$0.earned }) {
                HStack(spacing: 14) {
                    BadgeHex(def: next.def, earned: false).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sıradaki rozet").font(.bXs).foregroundStyle(Color.bMutedFg)
                        Text(next.def.title).font(.geist(16, .semibold, relativeTo: .headline)).foregroundStyle(Color.bFg)
                        Text(next.def.sub).font(.bXs).foregroundStyle(Color.bMutedFg)
                    }
                    Spacer(minLength: 0)
                }
                .bCard(padding: 16)
                .accessibilityElement(children: .combine)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Rozetler").font(.bDisplay(20, relativeTo: .title3)).foregroundStyle(Color.bFg)
                Spacer()
                Text("\(g.earnedCount)/\(g.badges.count)").font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg)
            }
            .padding(.top, 4)
            BadgeGrid(g: g)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - New badge celebration

/// Shows the first newly earned badge once (Today); can be turned off
struct BadgeCelebrationHost: ViewModifier {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query private var logs: [DayLog]
    @AppStorage(GameStore.celebrateKey) private var on = true
    @State private var badge: BadgeDef?
    @State private var all = false

    func body(content: Content) -> some View {
        content
            .onAppear { check() }
            .onChange(of: logs.count) { check() }
            .fullScreenCover(item: $badge) { b in
                BadgeCelebration(def: b, onAll: { badge = nil; Task { try? await Task.sleep(for: .milliseconds(450)); all = true } }, onOff: { on = false; badge = nil })
            }
            .navigationDestination(isPresented: $all) { MilestonesScreen() }
    }
    private func check() {
        guard badge == nil else { return }
        #if DEBUG
        if DemoData.active { return }
        #endif
        let g = GameSummary.build(ctx: ctx, profile: profiles.first ?? UserProfile(), todaySteps: health.stepsToday)
        let earned = Set(g.badges.filter(\.earned).map(\.id))
        var seen = GameStore.celebrated
        // first run of this feature: mark what's already earned as seen, no flood of celebrations
        if UserDefaults.standard.object(forKey: "gamify.celebrated") == nil { GameStore.celebrated = earned; return }
        guard on, let new = g.badges.first(where: { $0.earned && !seen.contains($0.id) }) else { return }
        seen.insert(new.id); GameStore.celebrated = seen
        badge = new.def
    }
}

extension View { func badgeCelebrations() -> some View { modifier(BadgeCelebrationHost()) } }

struct BadgeCelebration: View {
    let def: BadgeDef
    var onAll: () -> Void
    var onOff: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pop = false
    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack { Button { dismiss() } label: { Ti("x", size: 20) }.buttonStyle(BGlassIconStyle()).accessibilityLabel(tl("Kapat")); Spacer() }
                Spacer()
                ZStack {
                    Hexagon().fill(Color.bAction).frame(width: 200, height: 220)
                    Hexagon().inset(by: 18).fill(Color.white.opacity(0.25)).frame(width: 200, height: 220)
                    VStack(spacing: 2) {
                        Image(systemName: def.symbol).font(.system(size: 64, weight: .semibold))
                        if let m = def.mark { Text(m).font(.bNum(30)) }
                    }
                    .foregroundStyle(Color.bActionFg)
                }
                .scaleEffect(pop ? 1 : 0.6).opacity(pop ? 1 : 0)
                Text("Yeni rozet").font(.bXs).foregroundStyle(Color.white.opacity(0.64))
                Text(def.title).font(.bDisplay(32, relativeTo: .largeTitle)).foregroundStyle(.white)
                Text(def.sub).font(.bSm).foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                ShareLink(item: String(localized: "GYM Paper'da yeni rozet: \(def.title) · \(def.sub)")) {
                    HStack(spacing: 8) { Text("Paylaş"); Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.b(.primary, .large, full: true))
                Button(action: onAll) {
                    HStack(spacing: 8) { Text("Tüm rozetler"); Image(systemName: "trophy").font(.system(size: 15, weight: .bold)) }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.b(.secondary, .large, full: true))
                Button("Kutlamaları kapat", action: onOff).font(.bSm).foregroundStyle(Color.white.opacity(0.64)).frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .environment(\.colorScheme, .dark)
        }
        .overlay { ConfettiBurst().ignoresSafeArea().allowsHitTesting(false) }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { pop = true } }
    }
}

