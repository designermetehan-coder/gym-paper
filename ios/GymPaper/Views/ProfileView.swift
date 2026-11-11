import UserNotifications
import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import GymPaperKit

// Profile: data lives in iCloud; version info instead of in-app updates.

/// Formatter used by older screens (e.g. "72.5")
func fmt(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1)).locale(.current)) }

/// Measurement fields: [key, label, unit]
let profileMeasureFields: [(key: ReferenceWritableKeyPath<BodyMeasure, Double?>, label: String, unit: String)] = [
    (\BodyMeasure.kg, "Kilo", "kg"), (\BodyMeasure.waistCm, "Bel", "cm"), (\BodyMeasure.hipCm, "Kalça", "cm"), (\BodyMeasure.chestCm, "Göğüs", "cm"),
    (\BodyMeasure.rightArmCm, "Sağ kol", "cm"), (\BodyMeasure.leftArmCm, "Sol kol", "cm"), (\BodyMeasure.thighCm, "Bacak", "cm"), (\BodyMeasure.shoulderCm, "Omuz", "cm"),
]

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    @Query(filter: #Predicate<WorkoutProgram> { !$0.archived }, sort: \WorkoutProgram.createdAt) private var myPrograms: [WorkoutProgram]
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var myFoods: [SavedFood]
    @AppStorage("gympaper-theme") private var theme = "system"
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: ProfileSheet?
    /// Profile menus open as detail screens, not sheets
    enum ProfilePush: Hashable { case settings, goals, body, fast }
    @State private var push: ProfilePush?
    @State private var dataMsg: String?
    @State private var importing = false
    /// Try the intro without touching data
    @State private var onbPreview = false
    /// Opened from Today's profile button (sheet with a close button)
    var asSheet = false
    @Environment(\.dismiss) private var dismiss

    enum ProfileSheet: Identifiable {
        case settings, goals, body, measure(BodyMeasure?)
        var id: String {
            switch self {
            case .settings: "settings"; case .goals: "goals"; case .body: "body"
            case .measure(let m): "measure-\(m.map { "\($0.persistentModelID.hashValue)" } ?? "new")"
            }
        }
    }

    var body: some View {
        let p = profiles.first ?? UserProfile()
        let G = GoalState(startKg: p.startKg, goals: p.goals, measures: measures)
        BScreen(wash: asSheet ? .bar : .dominant) {
            BHeader(title: "Profil") {
                if asSheet { BRoundIcon(icon: "x", label: "Kapat") { dismiss() } }
            }

            // identity: avatar, name, one-line summary (Figma "Profile · Settings")
            VStack(spacing: 4) {
                Text(initials(p.name)).font(.bDisplay(26, relativeTo: .title)).foregroundStyle(Color.bHeroFg)
                    .frame(width: 84, height: 84).background(Color.bHero, in: Circle())
                    .padding(.bottom, 8)
                Text(p.name).font(.bDisplay(22, relativeTo: .title2)).foregroundStyle(Color.bFg).lineLimit(1)
                Text(summary(p, G)).font(.bXs).monospacedDigit().foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)

            groupLabel("Hedefler")
            VStack(spacing: 0) {
                listRow(symbol: "target", tint: .fitGreen, title: "Günlük hedefler",
                        sub: tl("Öğünler, kalori, makrolar, su ve adım")) { push = .settings }
                rowDivider
                listRow(symbol: "scalemass.fill", tint: .fitTime, title: "Kilo hedefleri", sub: goalsSub(G)) { push = .goals }
                rowDivider
                listRow(symbol: "flame.fill", tint: .fitKcal, title: "Vücut ve kalori",
                        sub: calorieTarget(p).map { String(localized: "Günlük \(fmt0($0)) kcal") } ?? tl("Bilgiler eksik")) { push = .body }
                rowDivider
                // switch right here; when on, the eating window settings open below (no detail screen)
                ProfileFastInline(profile: p, icon: rowIcon("moon.stars.fill", .fitPurple))
            }
            .bCard(padding: 0)

            groupLabel("Kütüphane")
            VStack(spacing: 0) {
                // value-based link so view and value links don't mix on the stack
                NavigationLink(value: WkRoute.programs) {
                    listRowLabel(symbol: "dumbbell.fill", tint: .fitBlue, title: "Antrenmanlarım", sub: String(localized: "\(myPrograms.count) program"))
                }
                .buttonStyle(.press)
                rowDivider
                NavigationLink { MyFoodsScreen() } label: {
                    listRowLabel(symbol: "fork.knife", tint: .orange, title: "Besinlerim", sub: String(localized: "\(myFoods.count) besin"))
                }
                .buttonStyle(.press)
                rowDivider
                NavigationLink { ProfileMeasuresScreen() } label: {
                    listRowLabel(symbol: "ruler", tint: .fitTime, title: "Ölçümlerim",
                                 sub: measures.isEmpty ? tl("Henüz ölçüm yok") : String(localized: "\(measures.count) ölçüm"))
                }
                .buttonStyle(.press)
            }
            .bCard(padding: 0)

            // App: notifications and appearance live here; no separate Settings screen
            groupLabel("Uygulama")
            VStack(spacing: 0) {
                NavigationLink { NotificationsScreen() } label: {
                    listRowLabel(symbol: "bell.badge.fill", tint: Color(red: 1.0, green: 0.23, blue: 0.19), title: "Bildirimler",
                                 sub: "Antrenman, öğün, su ve tartı hatırlatmaları")
                }
                .buttonStyle(.press)
                rowDivider
                // Night mode: one switch (on = dark, off = light); follows the system until first changed
                HStack(spacing: 12) {
                    rowIcon("moon.fill", Color(red: 0.36, green: 0.36, blue: 0.9))
                    Toggle(isOn: Binding(get: { theme == "dark" || (theme == "system" && scheme == .dark) },
                                         set: { theme = $0 ? "dark" : "light" })) {
                        Text("Gece modu").font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                    }
                    .tint(.green)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .bCard(padding: 0)

            if health.available && !health.authorized {
                Button { Task { await health.requestAccess() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(Color(red: 1, green: 0.18, blue: 0.33))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Apple Sağlık'ı bağla").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
                            Text("Adım, aktif kalori ve kilo otomatik gelsin").font(.bXs).foregroundStyle(Color.bMutedFg)
                        }
                        Spacer(minLength: 0)
                        Ti("chevron-right").foregroundStyle(Color.bMutedFg)
                    }
                    .bCard()
                }
                .buttonStyle(.press)
            }

            if let w = GymPaperApp.storageWarning {
                Text(w).font(.bXs).foregroundStyle(Color.bDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let dataMsg {
                Text(dataMsg).font(.bXs).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
            }

            // Data and about: same look as the settings list
            VStack(spacing: 0) {
                listRow(symbol: "square.and.arrow.down.fill", tint: .fitBlue, title: "Yedekten geri yükle",
                        sub: "GYM Paper yedeği ya da web (PWA) yedeği (JSON)") { importing = true }
                rowDivider
                listRow(symbol: "square.and.arrow.up.fill", tint: .fitTime, title: "Yedek al ve dışa aktar",
                        sub: "Tam yedek (JSON) ve tablolar (CSV)") { DataExport.share(ctx) }
                rowDivider
                linkRow(symbol: "hand.raised.fill", tint: .fitPurple, title: "Gizlilik politikası", url: "https://gympaper.vercel.app/gizlilik")
                rowDivider
                linkRow(symbol: "doc.text.fill", tint: .fitTime, title: "Lisanslar ve kaynaklar", url: "https://gympaper.vercel.app/lisanslar")
                rowDivider
                HStack(spacing: 12) {
                    rowIcon("info.circle.fill", Color.bMutedFg)
                    Text("Sürüm").font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                    Spacer(minLength: 0)
                    Text(version).font(.bSm).monospacedDigit().foregroundStyle(Color.bMutedFg)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
            .bCard(padding: 0)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { res in
                do {
                    let url = try res.get()
                    let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    let data = try SafeRead.data(url, limit: SafeRead.backupLimit)
                    // GYM Paper full backup first; otherwise the old web backup
                    if let full = AppBackup.parse(data) {
                        let r = Backup.restore(full, ctx: ctx)
                        dataMsg = String(localized: "Yedek geri yüklendi: \(r.programs) program, \(r.days) gün, \(r.foods) yeni besin, \(r.recipes) yeni tarif, \(r.measures) yeni ölçüm, \(r.savedMeals) kayıtlı öğün.")
                    } else {
                        let b = try PWABackup.parse(data)
                        let r = Importer.run(b, ctx: ctx)
                        dataMsg = String(localized: "Yedek yüklendi: \(r.programs) program, \(r.days) gün, \(r.foods) besin, \(r.recipes) tarif, \(r.measures) ölçüm.")
                    }
                    app.toast("Yedek yüklendi")
                } catch {
                    dataMsg = (error as? LocalizedError)?.errorDescription ?? String(localized: "Yedek okunamadı. GYM Paper ya da web (PWA) yedeği (JSON) seç.")
                    app.toast("Yedek okunamadı", kind: .error)
                }
            }

            // at the bottom: try the intro without touching data
            VStack(spacing: 0) {
                listRow(symbol: "sparkles", tint: .fitBlue, title: "Tanıtımı dene",
                        sub: "İlk açılış akışı baştan; verilerin değişmez") { onbPreview = true }
            }
            .bCard(padding: 0)
            .padding(.bottom, 8)
        }
        .navigationDestination(for: WkRoute.self) { r in WkRouteDestination(route: r) }
        .goalCelebration()
        .gymPaperTheme()
        .shot("prof.settings") { push = .settings }
        .shot("prof.body") { push = .body }
        .shot("prof.fast") { push = .fast }
        .shot("prof.measure") { sheet = .measure(nil) }
        .shotPush("prof.measures") { ProfileMeasuresScreen() }
        .shotPush("prof.foods") { MyFoodsScreen() }
        .shotPush("prof.notifications") { NotificationsScreen() }
        .navigationDestination(item: $push) { r in
            Group {
                switch r {
                case .settings: ProfileSettingsSheet()
                case .goals: ProfileGoalsSheet()
                case .body: ProfileBodySheet()
                case .fast: FastSettingsSheet(profile: profiles.first ?? Store.profile(ctx))
                }
            }
            .environment(\.bSheetPushed, true)
        }
        .fullScreenCover(isPresented: $onbPreview) {
            OnboardingView(onFinish: { onbPreview = false }, preview: true).gymPaperTheme()
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .settings: ProfileSettingsSheet()
            case .goals: ProfileGoalsSheet()
            case .body: ProfileBodySheet()
            case .measure(let m): MeasureSheet(edit: m)
            }
        }
    }

    private func groupLabel(_ t: String) -> some View {
        Text(tl(t).uppercased(with: Locale.current)).font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6)
            .foregroundStyle(Color.bMutedFg).padding(.top, 8).padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map { String($0) } }.joined().uppercased(with: Locale(identifier: "tr_TR"))
        return s.isEmpty ? "?" : s
    }
    /// "88,4 kg · hedef 80 kg · 1.989 kcal"
    private func summary(_ p: UserProfile, _ G: GoalState) -> String {
        var parts: [String] = []
        if let c = G.cur { parts.append("\(fmt1(c)) kg") }
        if let g = G.goals.last { parts.append(String(localized: "hedef \(fmt1(g)) kg")) }
        if let k = calorieTarget(p) { parts.append("\(fmt0(k)) kcal") }
        return parts.joined(separator: " · ")
    }
    private func goalsSub(_ G: GoalState) -> String {
        if G.goals.isEmpty { return tl("Hedef ekle") }
        if G.done { return tl("Bütün hedeflere ulaşıldı") }
        return String(localized: "\(G.idx + 1). hedefe \(fmt1(G.left)) kg")
    }

    private var rowDivider: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 62) }

    /// Menu row badge: 34 pt square, 9 pt corner; neutral icon and fill. `tint` is no longer used.
    private func rowIcon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.bFg.opacity(0.75))
            .frame(width: 34, height: 34)
            .background(Color.bFg.opacity(0.07), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
    }

    /// External link row (same look as a list row, arrow out on the right)
    private func linkRow(symbol: String, tint: Color, title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                rowIcon(symbol, tint)
                Text(tl(title)).font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.bMutedFg)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }

    /// Profile list row: badge, title, subtitle, chevron
    private func listRow(symbol: String, tint: Color, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { listRowLabel(symbol: symbol, tint: tint, title: title, sub: sub) }
            .buttonStyle(.press)
    }
    private func listRowLabel(symbol: String, tint: Color, title: String, sub: String) -> some View {
            HStack(spacing: 12) {
                rowIcon(symbol, tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tl(title)).font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                    Text(sub).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1)
                }
                Spacer(minLength: 0)
                Ti("chevron-right").foregroundStyle(Color.bMutedFg)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    // MARK: Kilo hedefleri

    // MARK: Calorie need + Health

    /// Daily calorie target; nil when details are missing
    private func calorieTarget(_ p: UserProfile) -> Double? {
        let e = Energy.summary(profile: p, health: health, day: Store.day(ctx, DayKey.today, create: false), latestMeasureKg: measures.first(where: { $0.kg != nil })?.kg, isToday: true)
        return e.missing.isEmpty ? e.target : nil
    }

    /// Colored tile: icon, big italic value, label
    /// `icon`: icon color (each tile its own meaning color); the value stays in the primary color
    private func tile(_ title: String, value: String, unit: String, symbol: String, tint: Color, icon: Color? = nil, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                let ic = icon ?? tint
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(ic)
                    .frame(width: 32, height: 32).background(ic.opacity(0.15), in: Circle())
                Spacer()
                Ti("chevron-right", size: 14).foregroundStyle(Color.bMutedFg)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.bNum(28)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(tl(unit)).font(.geist(13, .semibold, relativeTo: .footnote)).foregroundStyle(Color.bMutedFg).lineLimit(1) }
            }
            Text(tl(title)).font(.bDisplay(15, relativeTo: .subheadline)).foregroundStyle(Color.bFg).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 2)
        }
        // ~25% shorter so more tiles fit on the first screen
        .frame(maxWidth: .infinity, minHeight: wide ? 88 : 100, alignment: .leading)
        .bCard()
        .accessibilityElement(children: .combine)
    }

}

// MARK: - Measurements card

/// Weight chart (range picker, tap for value), latest value + change and recent entries
struct ProfileMeasuresCard: View {
    let measures: [BodyMeasure]          // yeniden eskiye
    let goal: Double?
    var onEdit: (BodyMeasure) -> Void
    var onDelete: (BodyMeasure) -> Void
    var showList = true
    @State private var range = 3
    init(measures: [BodyMeasure], goal: Double?, onEdit: @escaping (BodyMeasure) -> Void, onDelete: @escaping (BodyMeasure) -> Void, showList: Bool = true) {
        self.measures = measures; self.goal = goal; self.onEdit = onEdit; self.onDelete = onDelete; self.showList = showList
    }
    @State private var sel: Date?
    @State private var showAll = false

    private var weights: [(date: Date, kg: Double)] {
        measures.compactMap { m in m.kg.map { (m.date, $0) } }.sorted { $0.date < $1.date }
    }
    private func filtered(_ all: [(date: Date, kg: Double)]) -> [(date: Date, kg: Double)] {
        guard range > 0, let from = Calendar.current.date(byAdding: .month, value: -range, to: .now) else { return all }
        let f = all.filter { $0.date >= from }
        return f.count >= 2 ? f : Array(all.suffix(2))
    }

    var body: some View {
        let all = weights
        let pts = filtered(all)
        let last = all.last, prev = all.dropLast().last
        let delta = (last != nil && prev != nil) ? last!.kg - prev!.kg : nil
        VStack(alignment: .leading, spacing: 14) {
            // latest value + change
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let picked = sel.flatMap({ d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }) {
                    TodayValue(value: fmt1(picked.kg), suffix: " kg", size: 28)
                    Text(trShortDate(DayKey.of(picked.date))).font(.bXs).foregroundStyle(Color.bMutedFg)
                } else if let last {
                    TodayValue(value: fmt1(last.kg), suffix: " kg", size: 28)
                    if let delta, delta != 0 {
                        Text("\(delta < 0 ? "↓" : "↑") \(fmt1(abs(delta))) kg").font(.geist(12, .semibold)).monospacedDigit()
                            .foregroundStyle(delta < 0 ? Color.bSuccess : Color.bMutedFg)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((delta < 0 ? Color.bSuccess : Color.bMutedFg).opacity(0.12), in: Capsule())
                    }
                } else {
                    Text("Kilo kaydı yok").font(.bSm).foregroundStyle(Color.bMutedFg)
                }
                Spacer(minLength: 0)
            }
            .animation(.snappy(duration: 0.2), value: sel)

            if pts.count >= 2 {
                chart(pts)
                BSegmented(selection: $range, options: [(1, "1A"), (3, "3A"), (6, "6A"), (0, "Tümü")])
            }

            // recent entries
            if showList {
            let list = showAll ? measures : Array(measures.prefix(4))
            let prev = measures.prevKgMap()
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.persistentModelID) { i, m in
                    if i > 0 { Rectangle().fill(Color.bBorder).frame(height: 1) }
                    row(m, prevKg: prev[m.persistentModelID])
                        .bSwipeDelete { onDelete(m) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
            if measures.count > 4 {
                Button(showAll ? "Daha az göster" : "Tüm ölçümler (\(measures.count))") { withAnimation(.snappy) { showAll.toggle() } }
                    .buttonStyle(.b(.ghost, .regular, full: true))
            }
            }
        }
        .bCard()
    }

    private func chart(_ pts: [(date: Date, kg: Double)]) -> some View {
        let ys = pts.map(\.kg) + (goal.map { [$0] } ?? [])
        let lo = floor((ys.min() ?? 0) - 1.5), hi = ceil((ys.max() ?? 1) + 1.5)
        let picked = sel.flatMap { d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        return Chart {
            ForEach(pts, id: \.date) { p in
                AreaMark(x: .value("Tarih", p.date), yStart: .value("Alt", lo), yEnd: .value("Kilo", p.kg))
                    .foregroundStyle(LinearGradient(colors: [Color.bPrimary.opacity(0.25), Color.bPrimary.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Tarih", p.date), y: .value("Kilo", p.kg))
                    .foregroundStyle(Color.bPrimary).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let goal, goal >= lo, goal <= hi {
                RuleMark(y: .value("Hedef", goal))
                    .foregroundStyle(Color.bSuccess.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("hedef \(fmt1(goal))").font(.geist(10, .medium)).foregroundStyle(Color.bSuccess)
                    }
            }
            if let picked {
                RuleMark(x: .value("Seçili", picked.date)).foregroundStyle(Color.bFg.opacity(0.18))
                PointMark(x: .value("Tarih", picked.date), y: .value("Kilo", picked.kg))
                    .symbolSize(70).foregroundStyle(Color.bPrimary)
            } else if let l = pts.last {
                PointMark(x: .value("Tarih", l.date), y: .value("Kilo", l.kg)).symbolSize(55).foregroundStyle(Color.bPrimary)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXSelection(value: $sel)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [lo, ((lo + hi) / 2).rounded(), hi]) { v in
                AxisGridLine().foregroundStyle(Color.bBorder)
                AxisValueLabel { if let d = v.as(Double.self) { Text(fmt0(d)).font(.geist(10)).foregroundStyle(Color.bMutedFg) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: [pts.first?.date, pts.last?.date].compactMap { $0 }) { v in
                AxisValueLabel { if let d = v.as(Date.self) { Text(trShortDate(DayKey.of(d))).font(.geist(10)).foregroundStyle(Color.bMutedFg) } }
            }
        }
        .frame(height: 170)
        .sensoryFeedback(.selection, trigger: picked?.date)
        .accessibilityLabel("Kilo grafiği")
        // VoiceOver: latest value, change over the range and goal
        .accessibilityValue(chartSummary(pts))
    }

    private func chartSummary(_ pts: [(date: Date, kg: Double)]) -> String {
        guard let first = pts.first, let last = pts.last else { return "Ölçüm yok" }
        let ordered = first.date < last.date ? (first, last) : (last, first)
        let d = ordered.1.kg - ordered.0.kg
        var s = String(localized: "\(pts.count) ölçüm, son \(fmt1(ordered.1.kg)) kilo")
        if pts.count > 1 { s += d == 0 ? String(localized: ", değişim yok") : String(localized: ", dönemde \(fmt1(abs(d))) kilo \(d < 0 ? tl("azalma") : tl("artış"))") }
        if let goal { s += String(localized: ", hedef \(fmt1(goal)) kilo") }
        return s
    }

    private func row(_ m: BodyMeasure, prevKg: Double?) -> some View {
        let d = (m.kg != nil && prevKg != nil) ? m.kg! - prevKg! : nil
        return Button { onEdit(m) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trShortDate(DayKey.of(m.date))).font(.geist(14, .medium)).foregroundStyle(Color.bFg)
                    let extra = profileMeasureFields.dropFirst().compactMap { f in m[keyPath: f.key].map { "\(tl(f.label)) \(fmt1($0))" } }
                    if !extra.isEmpty { Text(extra.prefix(3).joined(separator: " · ")).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1) }
                }
                Spacer(minLength: 8)
                if let d, d != 0 {
                    Text("\(d < 0 ? "↓" : "↑") \(fmt1(abs(d)))").font(.geist(12, .medium)).monospacedDigit()
                        .foregroundStyle(d < 0 ? Color.bSuccess : Color.bMutedFg)
                }
                if let kg = m.kg {
                    (Text(fmt1(kg)).font(.bNum(16)) + Text(" kg").font(.bXs).foregroundStyle(Color.bMutedFg))
                        .monospacedDigit().foregroundStyle(Color.bFg)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }
}

// MARK: - Measurement form

struct MeasureSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]
    let cur: BodyMeasure?
    let quick: Bool
    @State private var date = Date.now
    @State private var vals: [String: String] = [:]

    init(quick: Bool) { self.quick = quick; self.cur = nil }
    init(edit: BodyMeasure?) { self.quick = false; self.cur = edit }

    private var fields: [(key: ReferenceWritableKeyPath<BodyMeasure, Double?>, label: String, unit: String)] {
        quick ? Array(profileMeasureFields.prefix(1)) : profileMeasureFields
    }
    private var parsed: [String: Double] {
        var o: [String: Double] = [:]
        // values outside a sane range aren't saved: weight 20–400 kg, girths 10–300 cm
        for f in profileMeasureFields {
            let v = trNum(vals[f.label] ?? ""), range: ClosedRange<Double> = f.unit == "kg" ? 20...400 : 10...300
            if range.contains(v) { o[f.label] = v }
        }
        return o
    }

    var body: some View {
        let last = measures.first
        BSheet(title: cur != nil ? "Ölçümü düzenle" : quick ? "Kilo gir" : "Yeni ölçüm") {
            BField(label: "Tarih") {
                DatePicker("Tarih", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).environment(\.locale, .current)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: quick ? 1 : 2), spacing: 12) {
                ForEach(fields, id: \.label) { f in
                    BField(label: "\(tl(f.label)) (\(f.unit))") {
                        TextField(last?[keyPath: f.key].map { fmt1($0) } ?? "", text: Binding(get: { vals[f.label] ?? "" }, set: { vals[f.label] = $0 }))
                            .keyboardType(.decimalPad).textFieldStyle(.b)
                    }
                }
            }
        } footer: {
            Button("Kaydet", action: save).buttonStyle(.b(.primary, .large, full: true)).disabled(parsed.isEmpty && cur == nil)
            if cur != nil {
                Button("Ölçümü sil", action: delete).buttonStyle(.b(.ghost, .regular, full: true)).bButtonFg(Color.bDestructive)
            }
        }
        .presentationDetents(quick ? Set([PresentationDetent.medium]) : Set([PresentationDetent.large]))
        .onAppear {
            guard let cur else { return }
            date = cur.date
            for f in profileMeasureFields { if let v = cur[keyPath: f.key] { vals[f.label] = fmt1(v) } }
        }
    }

    private func save() {
        let v = parsed
        let target: BodyMeasure
        var isNew = false
        if let cur { target = cur }
        else if let same = measures.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) { target = same }
        else { target = BodyMeasure(date: date, kg: nil); ctx.insert(target); isNew = true }
        let oldKg = target.kg
        target.date = date
        for f in fields {
            if let x = v[f.label] { target[keyPath: f.key] = x }
            else if cur != nil { target[keyPath: f.key] = nil }
        }
        Store.save(ctx)
        // if the day's weight didn't change, no second sample is written to Health
        if let kg = v["Kilo"], cur == nil, isNew || oldKg != kg { Task { await health.saveWeight(kg, at: date) } }
        // the calorie target prefers the Health weight; reflect today's weigh-in right away
        if let kg = v["Kilo"], Calendar.current.isDateInToday(date) { health.latestWeightKg = kg; health.latestWeightAt = date; Store.latestWeightAt = date }
        dismiss()
        app.toast("Ölçüm kaydedildi")
    }

    private func delete() {
        guard let cur else { return }
        let snap = (date: cur.date, vals: profileMeasureFields.map { cur[keyPath: $0.key] })
        ctx.delete(cur); Store.save(ctx)
        dismiss()
        app.toast("Ölçüm silindi", kind: .delete) { [ctx] in
            let m = BodyMeasure(date: snap.date, kg: nil)
            for (i, f) in profileMeasureFields.enumerated() { m[keyPath: f.key] = snap.vals[i] }
            ctx.insert(m); Store.save(ctx)
        }
    }
}

// MARK: - Ad

// MARK: - Daily goals

private struct ProfileSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var t: [String: String] = [:]
    @State private var meals: [Meal] = Meal.allCases
    @State private var loaded = false

    // [key, label, display multiplier, upper bound]
    private let TF: [(k: String, l: String, m: Double, max: Double)] = [
        ("kcal", "Kalori (kcal)", 1, 10000), ("p", "Protein (g)", 1, 500), ("c", "Karb. (g)", 1, 1000), ("f", "Yağ (g)", 1, 400),
        ("water", "Su hedefi (L)", 1000, 10000), ("waterStep", "Su adımı (ml)", 1, 2000), ("steps", "Adım hedefi", 1, 100000),
    ]

    var body: some View {
        BSheet(title: "Günlük hedefler") {
            VStack(alignment: .leading, spacing: 8) {
                (Text("Öğünler").font(.geist(14, .medium)).foregroundStyle(Color.bFg) + Text(" · günde kaç öğün yiyorsan onları seç").font(.bSm).foregroundStyle(Color.bMutedFg))
                HStack(spacing: 8) {
                    ForEach(Meal.allCases, id: \.self) { m in
                        let on = meals.contains(m)
                        // on: filled with a check; off: dashed outline with a plus (white vs. black alone was ambiguous)
                        Button { toggle(m) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: on ? "checkmark" : "plus").font(.system(size: 11, weight: .bold))
                                Text(m.nutShortLabel).font(.geist(14, on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(on ? Color.bBg : Color.bMutedFg)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Color.bFg : Color.clear, in: Capsule())
                            .overlay { if !on { Capsule().strokeBorder(Color.bMutedFg.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.press)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                Text(meals.count == 1 ? "Tek öğün: eklediğin her şey bu öğüne yazılır." : "\(meals.count) öğün. Kapattığın öğünlerdeki eski kayıtlar silinmez.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            // calories one row · macros side by side · water side by side · steps one row
            VStack(spacing: 12) {
                field("kcal")
                HStack(alignment: .top, spacing: 8) { field("p"); field("c"); field("f") }
                HStack(alignment: .top, spacing: 8) { field("water"); field("waterStep") }
                field("steps")
            }
        } footer: {
            Button("Kaydet", action: save).buttonStyle(.b(.primary, .large, full: true))
        }
        .onAppear(perform: load)
    }

    private func field(_ k: String) -> some View {
        let f = TF.first { $0.k == k }!
        return VStack(alignment: .leading, spacing: 6) {
            Text(tl(f.l)).font(.geist(12, .medium, relativeTo: .caption)).foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.8)
            TextField(k == "kcal" ? "Boş: otomatik hesaplanır" : "", text: Binding(get: { t[k] ?? "" }, set: { t[k] = $0 }))
                .keyboardType(.decimalPad).textFieldStyle(.b)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ k: Meal) {
        if meals.contains(k) { if meals.count > 1 { meals.removeAll { $0 == k } } }
        else { meals = Meal.allCases.filter { $0 == k || meals.contains($0) } }
    }

    private func load() {
        guard !loaded, let p = profiles.first else { return }
        loaded = true
        let cur: [String: Double] = ["kcal": p.manualKcal ?? 0, "p": p.proteinG, "c": p.carbsG, "f": p.fatG, "water": Double(p.waterMl), "waterStep": Double(p.waterStepMl), "steps": Double(p.stepGoal)]
        for f in TF { let v = (cur[f.k] ?? 0) / f.m; t[f.k] = v > 0 ? fmt(v.rounded(toPlaces: 2)).replacingOccurrences(of: ".", with: "") : "" }
        meals = p.meals
    }

    /// "2.500" thousands, "3.5" / "3,5" decimal (a US keyboard types "." as decimal)
    static func parseNum(_ raw: String) -> Double {
        var x = raw.trimmingCharacters(in: .whitespaces)
        if x.contains(",") { x = x.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else if let r = x.range(of: ".", options: .backwards), x.distance(from: r.upperBound, to: x.endIndex) == 3 { x = x.replacingOccurrences(of: ".", with: "") }
        return Double(x) ?? 0
    }

    private func save() {
        guard let p = profiles.first else { return }
        func val(_ k: String) -> Double? {
            guard let f = TF.first(where: { $0.k == k }) else { return nil }
            let v = (Self.parseNum(t[k] ?? "") * f.m).rounded()
            return v > 0 ? min(v, f.max) : nil
        }
        p.manualKcal = val("kcal").map { max(1000, $0) }   // very low targets aren't accepted
        if let v = val("p") { p.proteinG = v }
        if let v = val("c") { p.carbsG = v }
        if let v = val("f") { p.fatG = v }
        if let v = val("water") { p.waterMl = Int(v) }
        if let v = val("waterStep") { p.waterStepMl = Int(v) }
        if let v = val("steps") { p.stepGoal = Int(v) }
        p.meals = meals
        dismiss(); app.toast("Hedefler kaydedildi")
    }
}

// MARK: - Kilo hedefleri (GoalsSheet)

struct ProfileGoalsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var start = ""
    @State private var goals: [String] = []
    @State private var loaded = false
    var body: some View {
        BSheet(title: "Kilo hedefleri", description: "Ara hedefler sırayla takip edilir; birine ulaşınca sıradakine geçilir.") {
            BField(label: "Başlangıç kilosu (kg)", hint: "Toplam kaybın bu değere göre hesaplanır.") {
                TextField("", text: $start).keyboardType(.decimalPad).textFieldStyle(.b)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Hedefler").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
                ForEach(goals.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Text("\(i + 1). hedef").font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.6).frame(width: 64, alignment: .leading)
                        TextField("", text: Binding(get: { goals.indices.contains(i) ? goals[i] : "" }, set: { if goals.indices.contains(i) { goals[i] = $0 } }))
                            .keyboardType(.decimalPad).textFieldStyle(.b)
                            .overlay(alignment: .trailing) { Text("kg").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.trailing, 12) }
                            .accessibilityLabel("\(i + 1). hedef")
                        Button { goals.remove(at: i) } label: { Ti("trash") }.buttonStyle(.b(.ghost, .icon)).accessibilityLabel("Hedefi sil")
                    }
                }
                Button { goals.append("") } label: { BLabel("Hedef ekle", icon: "plus") }.buttonStyle(.b(.outline, .regular, full: true))
            }
        } footer: {
            Button("Kaydet", action: save).buttonStyle(.b(.primary, .large, full: true))
        }
        .onAppear {
            guard !loaded, let p = profiles.first else { return }
            loaded = true
            start = p.startKg.map(fmt1) ?? ""
            goals = p.goals.map(fmt1)
        }
    }
    private func save() {
        guard let p = profiles.first else { return }
        let s = trNum(start)
        p.startKg = (20...400).contains(s) ? s : nil
        p.goals = Array(Set(goals.map(trNum).filter { (20...400).contains($0) })).sorted(by: >)
        dismiss()
    }
}

// MARK: - Body and calories

private struct ProfileBodySheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \BodyMeasure.date, order: .reverse) private var measures: [BodyMeasure]

    var body: some View {
        if let p = profiles.first {
            @Bindable var p = p
            let e = Energy.summary(profile: p, health: health, day: Store.day(ctx, DayKey.today, create: false), latestMeasureKg: measures.first(where: { $0.kg != nil })?.kg, isToday: true)
            BSheet(title: "Vücut ve kalori", description: "Günlük kalori ihtiyacın bu bilgilerden hesaplanır.") {
                VStack(spacing: 0) {
                    row("Kilo", health.latestWeightKg.map { String(localized: "\(fmt1($0)) kg · Sağlık") })
                    row("Boy", health.heightCm.map { String(localized: "\(Int($0)) cm · Sağlık") })
                    row("Doğum tarihi", health.birthDate.map { String(localized: "\($0.formatted(.dateTime.day().month().year())) · Sağlık") })
                    row("Cinsiyet", health.sex.map { String(localized: "\(tl($0.label)) · Sağlık") }, last: true)
                }
                .bCard(padding: 0)
                Text("Sağlık'ta olmayanları aşağıdan gir.").font(.bXs).foregroundStyle(Color.bMutedFg)

                if health.sex == nil || health.birthDate == nil || health.heightCm == nil || health.latestWeightKg == nil {
                    VStack(alignment: .leading, spacing: 16) {
                        // an unset field must not look set with a default value; it says "Enter" first
                        if health.sex == nil {
                            BField(label: "Cinsiyet") {
                                if p.sex == nil {
                                    HStack(spacing: 8) {
                                        ForEach(Sex.allCases, id: \.self) { s in Button(tl(s.label)) { haptic(); p.sex = s }.buttonStyle(.b(.outline, full: true)) }
                                    }
                                } else {
                                    BSegmented(selection: Binding(get: { p.sex ?? .male }, set: { p.sex = $0 }), options: Sex.allCases.map { ($0, tl($0.label)) })
                                }
                            }
                        }
                        if health.birthDate == nil {
                            HStack {
                                Text("Doğum tarihi").font(.geist(14, .medium))
                                Spacer()
                                if p.birthDate == nil {
                                    Button("Gir") { p.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) }.buttonStyle(.b(.outline))
                                } else {
                                    DatePicker("Doğum tarihi", selection: Binding(get: { p.birthDate ?? .now }, set: { p.birthDate = $0 }),
                                               in: Calendar.current.date(byAdding: .year, value: -100, to: .now)!...Date.now, displayedComponents: .date)
                                        .labelsHidden().environment(\.locale, .current)
                                }
                            }
                        }
                        if health.heightCm == nil {
                            HStack {
                                Text("Boy").font(.geist(14, .medium))
                                Spacer()
                                if p.heightCm == nil {
                                    Button("Gir") { p.heightCm = 170 }.buttonStyle(.b(.outline))
                                } else {
                                    BStepper(value: Binding(get: { p.heightCm ?? 170 }, set: { p.heightCm = $0 }), step: 1, min: 120, max: 230, suffix: "cm", format: { "\(Int($0))" })
                                }
                            }
                        }
                        if health.latestWeightKg == nil {
                            HStack {
                                // with measurements, the current weight comes from them; this setting must not change the start weight
                                if let m = measures.first(where: { $0.kg != nil })?.kg {
                                    Text("Kilo").font(.geist(14, .medium))
                                    Spacer()
                                    Text("\(fmt1(m)) kg · Ölçümlerim").font(.bSm).foregroundStyle(Color.bMutedFg)
                                } else {
                                    Text("Kilo").font(.geist(14, .medium))
                                    Spacer()
                                    if p.startKg == nil {
                                        Button("Gir") { p.startKg = 75 }.buttonStyle(.b(.outline))
                                    } else {
                                        BStepper(value: Binding(get: { p.startKg ?? 75 }, set: { p.startKg = $0 }), step: 0.5, min: 30, max: 300, suffix: "kg")
                                    }
                                }
                            }
                        }
                    }
                    .foregroundStyle(Color.bFg)
                    .bCard()
                }

                VStack(alignment: .leading, spacing: 16) {
                    BField(label: "Aktivite seviyesi", hint: "Günlük hedef bununla hesaplanır; adım ve antrenman kalorisi hedefe eklenmez.") {
                        Picker("Aktivite seviyesi", selection: Binding(get: { p.activity }, set: { p.activity = $0 })) {
                            ForEach(ActivityLevel.allCases, id: \.self) { Text(tl($0.label)).tag($0) }
                        }
                        .pickerStyle(.menu).tint(Color.bFg)
                    }
                    BField(label: "Haftalık hedef") {
                        Picker("Haftalık hedef", selection: $p.weeklyLossKg) {
                            Text("Kiloyu koru").tag(0.0); Text("0,25 kg/hafta ver").tag(0.25); Text("0,5 kg/hafta ver").tag(0.5); Text("0,75 kg/hafta ver").tag(0.75); Text("1 kg/hafta ver").tag(1.0)
                        }
                        .pickerStyle(.menu).tint(Color.bFg)
                    }
                    Toggle(isOn: Binding(get: { p.manualKcal != nil }, set: { p.manualKcal = $0 ? (p.manualKcal ?? e.target.rounded()) : nil })) {
                        Text("Hedefi elle sabitle").font(.geist(14, .medium))
                    }
                    .tint(.green)
                    if p.manualKcal != nil {
                        HStack {
                            Text("Günlük hedef").font(.geist(14, .medium))
                            Spacer()
                            KcalInput(value: Binding(get: { p.manualKcal ?? 1800 }, set: { p.manualKcal = $0 }))
                        }
                    }
                }
                .foregroundStyle(Color.bFg)
                .bCard()

                if let n = e.need, let b = e.bmr {
                    Text("Bazal: \(fmt0(b)) kcal · İhtiyaç: \(fmt0(n)) kcal · Hedef: \(fmt0(e.target)) kcal. Önerilen hedef bazal metabolizmanın altına inmez. Değerler tahminidir, tıbbi tavsiye değildir.")
                        .font(.bXs).foregroundStyle(Color.bMutedFg)
                } else {
                    Text("Hesap için eksik: \(e.missing.joined(separator: ", ")).").font(.bXs).foregroundStyle(Color.bMutedFg)
                }
            }
        }
    }
    private func row(_ l: String, _ v: String?, last: Bool = false) -> some View {
        HStack {
            Text(tl(l)).font(.bSm).foregroundStyle(Color.bMutedFg)
            Spacer()
            Text(v ?? "—").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 16) } }
    }
}

struct ProfileTextButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(tl(title)).font(.geist(15, .semibold)).foregroundStyle(Color.bLink)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.press)
    }
}

// MARK: - Bildirimler

struct NotificationsScreen: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @AppStorage("ntf.workout") private var workout = true
    @AppStorage("ntf.openSession") private var openSession = true
    @AppStorage("ntf.food") private var food = true
    @AppStorage("ntf.water") private var water = false
    @AppStorage("ntf.weigh") private var weigh = true
    @AppStorage("ntf.weekly") private var weekly = true
    @AppStorage("ntf.goal") private var goal = true
    @AppStorage("ntf.fast") private var fast = true
    @AppStorage("ntf.workoutMin") private var workoutMin = 18 * 60
    @AppStorage("ntf.foodMin") private var foodMin = 21 * 60
    @AppStorage("ntf.weighDay") private var weighDay = 2
    @State private var denied = false

    private var sig: String { "\(workout)\(openSession)\(food)\(water)\(weigh)\(weekly)\(goal)\(fast)\(workoutMin)\(foodMin)\(weighDay)" }

    var body: some View {
        BScreen(pinHeader: false) {
            WkPushedHeader(title: "Bildirimler")   // GP-08
            if denied {
                Button {
                    if let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.slash.fill").font(.system(size: 18)).foregroundStyle(Color.bDestructive)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bildirimler kapalı").font(.geist(14, .medium)).foregroundStyle(Color.bFg)
                            Text("Hatırlatmaların gelmesi için Ayarlar'dan izin ver").font(.bXs).foregroundStyle(Color.bMutedFg)
                        }
                        Spacer(minLength: 0)
                        Ti("chevron-right").foregroundStyle(Color.bMutedFg)
                    }
                    .bCard()
                }
                .buttonStyle(.press)
            }
            ProfileSectionTitle("Antrenman")
            VStack(spacing: 0) {
                row("dumbbell.fill", "Antrenman günü", "O gün programın varsa ve başlamadıysan", $workout) {
                    timePicker($workoutMin)
                }
                divider
                row("timer", "Açık kalan antrenman", "2 saattir açıksa bitirip bitirmediğini sorar", $openSession)
            }
            .bCard(padding: 0)
            ProfileSectionTitle("Beslenme")
            VStack(spacing: 0) {
                row("fork.knife", "Akşam kaydı", "O gün hiçbir şey eklemediysen", $food) { timePicker($foodMin) }
                divider
                row("drop.fill", "Su", "11:00, 14:00 ve 17:00; hedefe ulaşınca durur", $water)
                divider
                row("moon.stars.fill", "Aralıklı oruç", "Oruç bitince ve yeme penceresi kapanmadan 30 dk önce", $fast)
            }
            .bCard(padding: 0)
            ProfileSectionTitle("İlerleme")
            VStack(spacing: 0) {
                row("scalemass.fill", "Haftalık tartı", "Seçtiğin gün sabah 08:30", $weigh) {
                    Picker("Gün", selection: $weighDay) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in Text(DayKey.calendar.weekdaySymbols(tr: d)).tag(d) }
                    }
                    .pickerStyle(.menu).tint(Color.bFg)
                }
                divider
                row("chart.bar.fill", "Haftalık özet", "Pazar 20:00: antrenman sayısı, hedefe kalan kilo", $weekly)
                divider
                row("trophy.fill", "Hedefe ulaşma", "Kilo hedefine ulaştığında bir kez", $goal)
            }
            .bCard(padding: 0)
        }
        .task { await refreshAuth() }
        .onChange(of: phase) { _, p in if p == .active { Task { await refreshAuth() } } }
        .onChange(of: sig) { _, _ in
            Notifier.reschedule(ctx)
            if !openSession { Notifier.openSession(nil) }
            Task { await Notifier.askOnce(); await refreshAuth(); Notifier.invalidate(); Notifier.reschedule(ctx) }
        }
    }

    private var divider: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 72) }

    private func refreshAuth() async {
        denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private func timePicker(_ m: Binding<Int>) -> some View {
        DatePicker("Saat", selection: Binding(
            get: { DayKey.calendar.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { let c = DayKey.calendar.dateComponents([.hour, .minute], from: $0); m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .environment(\.locale, .current)
    }

    private func row(_ symbol: String, _ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        row(symbol, title, sub, on) { EmptyView() }
    }

    private func row<X: View>(_ symbol: String, _ title: String, _ sub: String, _ on: Binding<Bool>, @ViewBuilder extra: () -> X) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.bPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.bPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                    Text(sub).font(.bXs).foregroundStyle(Color.bMutedFg).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(title, isOn: on).labelsHidden().tint(.green)
            }
            if on.wrappedValue && X.self != EmptyView.self {
                HStack { Spacer(minLength: 0); extra() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private extension Calendar {
    /// 1 = Pazar … 7 = Cumartesi
    func weekdaySymbols(tr d: Int) -> String {
        var c = Calendar(identifier: .gregorian); c.locale = .current
        return c.standaloneWeekdaySymbols[max(1, min(7, d)) - 1]
    }
}


/// Manual calorie target: tapping opens a number pad to type any value (800–6000)
struct KcalInput: View {
    @Binding var value: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 4) {
            TextField("1800", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.bNum(18))
                .focused($focused)
                .frame(width: 76)
            Text("kcal").font(.bSm).foregroundStyle(Color.bMutedFg)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(scheme == .dark ? Color.white.opacity(0.045) : Color.bCard, in: Capsule())
        .overlay { Capsule().strokeBorder(focused ? Color.bLink : (scheme == .light ? Color.bBorder : .clear), lineWidth: focused ? 1.5 : 1) }
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .onAppear { text = String(Int(value.rounded())) }
        .onChange(of: text) { _, t in
            let digits = String(t.filter(\.isNumber).prefix(4))
            if digits != t { text = digits; return }
            if let v = Double(digits), v >= 800, v <= 6000 { value = v }
        }
        .onChange(of: focused) { _, f in
            // no invalid value left when focus ends
            if !f { let v = min(6000, max(800, Double(text) ?? value)); value = v; text = String(Int(v)) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { focused = false }.fontWeight(.semibold)
            }
        }
        .accessibilityLabel("Günlük kalori hedefi")
    }
}


// MARK: - Data export
/// Shares the user's own data as CSV (for spreadsheets) and JSON (full copy)
@MainActor
enum DataExport {
    static func share(_ ctx: ModelContext) {
        let urls = make(ctx)
        guard !urls.isEmpty,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
    }

    private static func csvCell(_ v: String) -> String {
        v.contains(where: { ",\"\n;".contains($0) }) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }
    private static func num(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "" }

    static func make(_ ctx: ModelContext) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GYM-Paper-disa-aktarim", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let days = (try? ctx.fetch(FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let progs = (try? ctx.fetch(FetchDescriptor<WorkoutProgram>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let measures = (try? ctx.fetch(FetchDescriptor<BodyMeasure>(sortBy: [SortDescriptor(\.date)]))) ?? []
        var exName: [String: String] = [:]
        for p in progs { for e in p.blocks.allExercises { exName[e.id] = e.name } }
        let progName = Dictionary(progs.map { ($0.pid, $0.name) }, uniquingKeysWith: { a, _ in a })

        var sets = ["tarih,program,hareket,set,kg,tekrar,tamamlandi"]
        var food = ["tarih,ogun,besin,gram,kcal,protein_g,karbonhidrat_g,yag_g"]
        var daily = ["tarih,antrenman_tamam,antrenman_dk,su_ml,alinan_kcal"]
        for L in days {
            let pn = L.programIdRaw.flatMap { progName[$0] } ?? ""
            for (eid, arr) in L.sets.sorted(by: { $0.key < $1.key }) {
                for (i, x) in arr.enumerated() {
                    sets.append([L.date, csvCell(pn), csvCell(exName[eid] ?? eid), "\(i + 1)", num(x.kg), x.reps.map(String.init) ?? "", x.done ? "1" : "0"].joined(separator: ","))
                }
            }
            for e in L.entries {
                let m = e.macros
                food.append([L.date, e.meal.label, csvCell(e.name), num(e.g), num(m.kcal), num(m.p), num(m.c), num(m.f)].joined(separator: ","))
            }
            daily.append([L.date, L.workoutDone ? "1" : "0", "\(L.workoutSeconds / 60)", "\(L.waterMl)", num(L.eaten.kcal)].joined(separator: ","))
        }
        var meas = ["tarih," + profileMeasureFields.map { "\($0.label) (\($0.unit))" }.joined(separator: ",")]
        let df = ISO8601DateFormatter(); df.formatOptions = [.withFullDate]
        for m in measures { meas.append(df.string(from: m.date) + "," + profileMeasureFields.map { num(m[keyPath: $0.key]) }.joined(separator: ",")) }

        var out: [URL] = []
        func write(_ name: String, _ lines: [String]) {
            let u = dir.appendingPathComponent(name)
            // BOM so Excel opens Turkish characters correctly
            if (try? ("\u{FEFF}" + lines.joined(separator: "\n")).write(to: u, atomically: true, encoding: .utf8)) != nil { out.append(u) }
        }
        write("antrenman-setleri.csv", sets); write("beslenme.csv", food); write("gunluk-ozet.csv", daily); write("olcumler.csv", meas)
        // full backup: restorable via Profile › Restore from backup (foods, recipes, visuals, saved meals included)
        if let d = try? AppBackup.encoder.encode(Backup.make(ctx)) {
            let u = dir.appendingPathComponent("gym-paper-yedek-\(DayKey.today).json")
            if (try? d.write(to: u)) != nil { out.insert(u, at: 0) }
        }
        return out
    }
}

// MARK: - GYM Paper full backup: export and restore (iPhone only; Store.swift is shared with the watch)

/// The app's own backup. Profile, programs, days, measurements, foods (with images), recipes,
/// exercise visuals, saved meals and recipe notes in one JSON file.
struct AppBackup: Codable {
    static let formatID = "gympaper-backup"
    var format = AppBackup.formatID
    var version = 1
    var exportedAt = Date.now
    var appVersion: String?
    var profile: Profile
    var programs: [Program]
    var days: [Day]
    var measures: [Measure]
    var foods: [Food]
    var recipes: [RecipeX]
    var media: [Media]
    var savedMeals: [NutTemplate]
    var recipeNotes: [String: String]

    struct Profile: Codable {
        var name: String; var startKg: Double?; var goals: [Double]; var sex: String?; var birthDate: Date?; var heightCm: Double?
        var activity: String; var weeklyLossKg: Double; var useMeasuredActivity: Bool
        var proteinG: Double; var carbsG: Double; var fatG: Double; var manualKcal: Double?
        var waterMl: Int; var waterStepMl: Int; var stepGoal: Int; var meals: String
        var schedule: [ScheduleEntry]; var fastOn: Bool; var fast: FastPlan
    }
    struct Program: Codable { var pid: String; var name: String; var short: String?; var blocks: [Block]; var archived: Bool; var createdAt: Date }
    struct Day: Codable {
        var date: String; var uid: String; var programIdRaw: String?; var workoutDone: Bool; var waterMl: Int; var steps: Int
        var entries: [FoodEntry]; var sets: [String: [SetLog]]; var exDone: [String: Bool]
        var workoutSeconds: Int; var workoutKcal: Double; var hkSaved: Bool
    }
    struct Measure: Codable {
        var uid: String; var date: Date; var kg: Double?; var waistCm: Double?; var hipCm: Double?; var chestCm: Double?
        var rightArmCm: Double?; var leftArmCm: Double?; var thighCm: Double?; var shoulderCm: Double?
    }
    struct Food: Codable { var name: String; var per100: Macros; var portions: [String: Double]; var barcode: String?; var createdAt: Date; var image: Data? }
    struct RecipeX: Codable { var name: String; var servings: Int; var items: [RecipeItem]; var createdAt: Date }
    struct Media: Codable { var key: String; var frame0: Data?; var frame1: Data?; var updatedAt: Date }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// Whether the file is a GYM Paper backup (otherwise the old web backup is tried)
    static func parse(_ data: Data) -> AppBackup? {
        guard let b = try? decoder.decode(AppBackup.self, from: data), b.format == formatID else { return nil }
        return b
    }
}

@MainActor
enum Backup {
    struct Result { var programs = 0, days = 0, measures = 0, foods = 0, recipes = 0, savedMeals = 0 }

    static func make(_ ctx: ModelContext) -> AppBackup {
        let p = Store.profile(ctx)
        func all<T: PersistentModel>(_ t: T.Type) -> [T] { (try? ctx.fetch(FetchDescriptor<T>())) ?? [] }
        let local = NutLocal.shared
        let profile = AppBackup.Profile(
            name: p.name, startKg: p.startKg, goals: p.goals, sex: p.sexRaw, birthDate: p.birthDate, heightCm: p.heightCm,
            activity: p.activityRaw, weeklyLossKg: p.weeklyLossKg, useMeasuredActivity: p.useMeasuredActivity,
            proteinG: p.proteinG, carbsG: p.carbsG, fatG: p.fatG, manualKcal: p.manualKcal,
            waterMl: p.waterMl, waterStepMl: p.waterStepMl, stepGoal: p.stepGoal, meals: p.mealsRaw,
            schedule: p.schedule, fastOn: p.fastOn, fast: p.fast)
        var programs: [AppBackup.Program] = []
        for x in all(WorkoutProgram.self).sorted(by: { $0.createdAt < $1.createdAt }) {
            programs.append(AppBackup.Program(pid: x.pid, name: x.name, short: x.short, blocks: x.blocks, archived: x.archived, createdAt: x.createdAt))
        }
        var days: [AppBackup.Day] = []
        for x in all(DayLog.self).sorted(by: { $0.date < $1.date }) {
            days.append(AppBackup.Day(date: x.date, uid: x.uid, programIdRaw: x.programIdRaw, workoutDone: x.workoutDone, waterMl: x.waterMl, steps: x.steps,
                                      entries: x.entries, sets: x.sets, exDone: x.exDone, workoutSeconds: x.workoutSeconds, workoutKcal: x.workoutKcal, hkSaved: x.hkSaved))
        }
        var measures: [AppBackup.Measure] = []
        for x in all(BodyMeasure.self).sorted(by: { $0.date < $1.date }) {
            measures.append(AppBackup.Measure(uid: x.uid, date: x.date, kg: x.kg, waistCm: x.waistCm, hipCm: x.hipCm, chestCm: x.chestCm,
                                              rightArmCm: x.rightArmCm, leftArmCm: x.leftArmCm, thighCm: x.thighCm, shoulderCm: x.shoulderCm))
        }
        var foods: [AppBackup.Food] = []
        for x in all(SavedFood.self).sorted(by: { $0.createdAt < $1.createdAt }) {
            foods.append(AppBackup.Food(name: x.name, per100: x.per100, portions: x.portions, barcode: x.barcode, createdAt: x.createdAt, image: x.imageData))
        }
        var recipes: [AppBackup.RecipeX] = []
        for x in all(Recipe.self).sorted(by: { $0.createdAt < $1.createdAt }) {
            recipes.append(AppBackup.RecipeX(name: x.name, servings: x.servings, items: x.items, createdAt: x.createdAt))
        }
        var media: [AppBackup.Media] = []
        for x in all(ExerciseMedia.self) { media.append(AppBackup.Media(key: x.key, frame0: x.frame0, frame1: x.frame1, updatedAt: x.updatedAt)) }
        return AppBackup(appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                         profile: profile, programs: programs, days: days, measures: measures, foods: foods,
                         recipes: recipes, media: media, savedMeals: local.templates, recipeNotes: local.notes)
    }

    /// Restore merges and never deletes: the profile is replaced; programs with the same id are updated;
    /// day food/set lists merge and numbers take the larger; missing measurements, foods, recipes, visuals and saved meals are added.
    static func restore(_ b: AppBackup, ctx: ModelContext) -> Result {
        var r = Result()
        let p = Store.profile(ctx), x = b.profile
        p.name = x.name; p.startKg = x.startKg; p.goals = x.goals; p.sexRaw = x.sex; p.birthDate = x.birthDate; p.heightCm = x.heightCm
        p.activityRaw = x.activity; p.weeklyLossKg = x.weeklyLossKg; p.useMeasuredActivity = x.useMeasuredActivity
        p.proteinG = x.proteinG; p.carbsG = x.carbsG; p.fatG = x.fatG; p.manualKcal = x.manualKcal
        p.waterMl = x.waterMl; p.waterStepMl = x.waterStepMl; p.stepGoal = x.stepGoal; p.mealsRaw = x.meals
        p.schedule = x.schedule; p.fastOn = x.fastOn; p.fast = x.fast

        let progs = Dictionary(Store.programs(ctx, includeArchived: true).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for y in b.programs {
            let prog = progs[y.pid] ?? { let n = WorkoutProgram(pid: y.pid, name: y.name); n.createdAt = y.createdAt; ctx.insert(n); return n }()
            prog.name = y.name; prog.short = y.short; prog.blocks = y.blocks; prog.archived = y.archived
            r.programs += 1
        }
        for d in b.days {
            let day = Store.day(ctx, d.date, create: false) ?? { let n = DayLog(date: d.date); n.uid = d.uid.isEmpty ? n.uid : d.uid; ctx.insert(n); return n }()
            if day.programIdRaw == nil { day.programIdRaw = d.programIdRaw }
            day.workoutDone = day.workoutDone || d.workoutDone
            day.waterMl = max(day.waterMl, d.waterMl); day.steps = max(day.steps, d.steps)
            day.entries = DayMerge.entries(day.entries, d.entries)
            day.sets = DayMerge.sets(day.sets, d.sets)
            day.exDone = DayMerge.flags(day.exDone, d.exDone)
            day.workoutSeconds = max(day.workoutSeconds, d.workoutSeconds); day.workoutKcal = max(day.workoutKcal, d.workoutKcal)
            day.hkSaved = day.hkSaved || d.hkSaved
            r.days += 1
        }
        let measures = (try? ctx.fetch(FetchDescriptor<BodyMeasure>())) ?? []
        var byUid = Dictionary(measures.filter { !$0.uid.isEmpty }.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for m in b.measures {
            let x = byUid[m.uid] ?? { let n = BodyMeasure(date: m.date, kg: nil); if !m.uid.isEmpty { n.uid = m.uid }; ctx.insert(n); byUid[n.uid] = n; r.measures += 1; return n }()
            let vals: [(ReferenceWritableKeyPath<BodyMeasure, Double?>, Double?)] = [
                (\.kg, m.kg), (\.waistCm, m.waistCm), (\.hipCm, m.hipCm), (\.chestCm, m.chestCm),
                (\.rightArmCm, m.rightArmCm), (\.leftArmCm, m.leftArmCm), (\.thighCm, m.thighCm), (\.shoulderCm, m.shoulderCm)]
            for (k, v) in vals where x[keyPath: k] == nil { x[keyPath: k] = v }
        }
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var foods = Dictionary(((try? ctx.fetch(FetchDescriptor<SavedFood>())) ?? []).map { (norm($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        for f in b.foods {
            if let have = foods[norm(f.name)] { if have.imageData == nil { have.imageData = f.image }; continue }
            let n = SavedFood(name: f.name, per100: f.per100, portions: f.portions, barcode: f.barcode)
            n.createdAt = f.createdAt; n.imageData = f.image
            ctx.insert(n); foods[norm(f.name)] = n; r.foods += 1
        }
        var recipeNames = Set(((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).map { norm($0.name) })
        for y in b.recipes where recipeNames.insert(norm(y.name)).inserted {
            let n = Recipe(name: y.name, servings: y.servings, items: y.items); n.createdAt = y.createdAt
            ctx.insert(n); r.recipes += 1
        }
        var mediaKeys = Set(((try? ctx.fetch(FetchDescriptor<ExerciseMedia>())) ?? []).map(\.key))
        for m in b.media where mediaKeys.insert(m.key).inserted {
            let n = ExerciseMedia(key: m.key); n.frame0 = m.frame0; n.frame1 = m.frame1; n.updatedAt = m.updatedAt
            ctx.insert(n)
        }
        let local = NutLocal.shared
        let have = Set(local.templates.map(\.id))
        let add = b.savedMeals.filter { !have.contains($0.id) }
        if !add.isEmpty { local.templates += add; r.savedMeals = add.count }
        var notes = local.notes
        for (k, v) in b.recipeNotes where notes[k] == nil { notes[k] = v }
        if notes != local.notes { local.notes = notes }
        Store.save(ctx)
        return r
    }
}

/// Weight goals: current weight, total change, goals 1-2-3 with the next one's progress (Progress tab)
struct WeightGoalsCard: View {
    let G: GoalState
    var onAdd: () -> Void = {}
    /// Off on Progress: the weight card above already shows the current weight
    var showCurrent = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !showCurrent {
                Text("Kilo hedefleri").font(.geist(16, .semibold, relativeTo: .headline)).foregroundStyle(Color.bFg)
            }
            // big current weight + total change
            if showCurrent { HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şimdi").font(.bXs).foregroundStyle(Color.bMutedFg)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(G.cur.map(fmt1) ?? "–").font(.bNum(46, relativeTo: .largeTitle)).foregroundStyle(Color.bFg)
                            .lineLimit(1).minimumScaleFactor(0.5)   // keep "88.4" from breaking
                        if G.cur != nil { Text("kg").font(.bDisplay(18, relativeTo: .title3)).foregroundStyle(Color.bMutedFg) }
                    }
                }
                Spacer()
                if G.start != nil, G.cur != nil, !G.pts.isEmpty, G.lost != 0 {
                    Text((G.lost > 0 ? "↓ " : "↑ ") + fmt1(abs(G.lost)) + " kg")
                        .font(.bNum(15)).foregroundStyle(G.lost > 0 ? Color.bSuccess : Color.fitKcal)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background((G.lost > 0 ? Color.bSuccess : Color.fitKcal).opacity(0.12), in: Capsule())
                }
            } }
            if G.goals.isEmpty {
                Button { onAdd() } label: { BLabel("Hedef ekle", icon: "plus") }.buttonStyle(.b(.outline, .regular, full: true))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(G.goals.enumerated()), id: \.offset) { i, g in
                        // a goal above the start (weight gain) isn't "reached" from the start; without weight it doesn't say "0 kg to go"
                        let reached = (G.cur ?? .infinity) <= g && g < (G.start ?? .infinity)
                        let active = G.cur != nil && !G.done && i == G.idx
                        // goals top to bottom 1, 2, 3; the progress bar only on the next goal
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("\(i + 1). hedef").font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1).minimumScaleFactor(0.6).frame(width: 56, alignment: .leading)
                                (Text(fmt1(g)).font(.bNum(15)) + Text(" kg").font(.bXs)).foregroundStyle(Color.bFg)
                                Spacer()
                                if reached { BBadge(variant: .success) { Ti("circle-check-filled", size: 12); Text("Ulaşıldı") } }
                                else if active { BBadge(variant: .primary) { Text("\(fmt1(G.left)) kg kaldı").monospacedDigit() } }
                                else if let c = G.cur { BBadge(variant: .outline) { Text("\(fmt1(max(0, c - g))) kg kaldı").monospacedDigit() } }
                                else { BBadge(variant: .outline) { Text("Sırada") } }
                            }
                            if active { BProgress(value: G.pct, label: String(localized: "\(i + 1). hedefe ilerleme")) }
                        }
                    }
                }
            }
        }
        .bCard()
    }
}

/// Profile › Goals: intermittent fasting as a switch; when on, the eating window and quick picks open below.
/// Every change is saved right away (no detail screen, no Save button).
struct ProfileFastInline<I: View>: View {
    @Environment(\.modelContext) private var ctx
    let profile: UserProfile
    let icon: I
    @State private var on = false
    @State private var start = 20 * 60
    @State private var end = 12 * 60
    @State private var loaded = false
    private var plan: FastPlan { FastPlan(startMin: start, endMin: end) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon
                Toggle(isOn: $on.animation(.snappy)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aralıklı oruç").font(.bDisplay(16, relativeTo: .body)).foregroundStyle(Color.bFg)
                        if on { Text("\(FastSettingsSheet.dur(plan.eatingMin)) yeme aralığı · \(FastSettingsSheet.dur(plan.durMin)) oruç").font(.bXs).foregroundStyle(Color.bMutedFg) }
                    }
                }
                .tint(.green)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if on {
                VStack(spacing: 0) {
                    divider
                    timeRow("Yemeye başla", $end)
                    divider
                    timeRow("Yemeyi bırak", $start)
                    divider
                    HStack(spacing: 8) {
                        ForEach(FastPlan.presets, id: \.hours) { p in
                            let sel = plan.durMin == p.hours * 60
                            Button { haptic(); start = (end + (24 - p.hours) * 60) % 1440 } label: {
                                Text(p.label).font(.bNum(15))
                                    .foregroundStyle(sel ? Color.bBg : Color.bFg)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(sel ? Color.bFg : Color.clear, in: Capsule())
                                    .overlay { if !sel { Capsule().strokeBorder(Color.bBorder) } }
                            }
                            .buttonStyle(.press)
                            .accessibilityAddTraits(sel ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            guard !loaded else { return }; loaded = true
            on = profile.fastOn; start = profile.fast.startMin; end = profile.fast.endMin
        }
        .onChange(of: on) { save() }
        .onChange(of: start) { save() }
        .onChange(of: end) { save() }
    }

    private var divider: some View { Rectangle().fill(Color.bBorder).frame(height: 1).padding(.leading, 62) }

    private func timeRow(_ title: String, _ m: Binding<Int>) -> some View {
        HStack {
            Text(tl(title)).font(.geist(15, .medium)).foregroundStyle(Color.bFg)
            Spacer()
            DatePicker(tl(title), selection: Binding(
                get: { DayKey.calendar.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                set: { let c = DayKey.calendar.dateComponents([.hour, .minute], from: $0); m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        .padding(.leading, 62).padding(.trailing, 16).frame(minHeight: 52)
    }

    private func save() {
        guard loaded else { return }
        var f = profile.fast
        let p = plan
        f.startMin = p.startMin; f.durMin = p.durMin
        profile.fast = f
        profile.fastOn = on
        Store.save(ctx)
        LiveFast.sync(profile)
        Notifier.reschedule(ctx)
    }
}
