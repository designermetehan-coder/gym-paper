import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers
import GymPaperKit

// Nutrition tab:
// Log (day navigation, summary, meal cards) · My foods · Recipes

/// Sheets opened from the tab
enum NutSheet: Identifiable {
    case entry(date: String, id: String)
    case saveTemplate(meal: Meal, items: [FoodEntry])
    case template(id: String, isNew: Bool)
    case foodEdit(SavedFood?)
    case recipe(Recipe)
    case recipeForm(Recipe, isNew: Bool)
    case add(NutTarget)
    /// Group added to the log from a saved meal ("Breakfast plate")
    case group(date: String, gid: String)
    var id: String {
        switch self {
        case .entry(let d, let i): "e\(d)\(i)"
        case .saveTemplate(let m, _): "st\(m.rawValue)"
        case .template(let i, _): "t\(i)"
        case .foodEdit(let f): "fe\(f.map { "\($0.persistentModelID.hashValue)" } ?? "new")"
        case .recipe(let r): "r\(r.persistentModelID.hashValue)"
        case .recipeForm(let r, _): "rf\(r.persistentModelID.hashValue)"
        case .add(let t): "add\(t.id)"
        case .group(let d, let g): "g\(d)\(g)"
        }
    }
}

struct NutritionView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var date = DayKey.today
    @State private var sheet: NutSheet?
    /// After midnight, move to the new day if the user was looking at "today"
    @State private var shownToday = DayKey.today
    @Environment(\.scenePhase) private var phase

    var body: some View {
        BScreen {
            // the streak (meal or workout) lives on Today
            BHeader(title: "Beslenme")
            NutDiary(date: $date, sheet: $sheet)
        }
        .sheet(item: $sheet) { s in NutSheetHost(sheet: s, date: $date, open: { sheet = $0 }) }
        .onChange(of: phase) { _, p in if p == .active { rollDay() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in rollDay() }
    }

    private func rollDay() {
        let t = DayKey.today
        guard t != shownToday else { return }
        if date == shownToday { date = t }
        shownToday = t
    }
}

/// Sheet content (separate so sheets can nest)
struct NutSheetHost: View {
    let sheet: NutSheet
    @Binding var date: String
    var open: (NutSheet) -> Void
    var body: some View {
        switch sheet {
        case .entry(let d, let id): NutEntrySheet(date: d, id: id)
        case .saveTemplate(let m, let items): NutSaveTemplateSheet(meal: m, items: items)
        case .template(let id, let isNew): NutTemplateForm(id: id, isNew: isNew)
        case .foodEdit(let f): NutFoodEditSheet(food: f)
        case .recipe(let r): NutRecipeSheet(recipe: r)
        case .recipeForm(let r, let isNew): NutRecipeForm(recipe: r, isNew: isNew)
        case .add(let t): AddFoodSheet(target: t)
        case .group(let d, let g): NutGroupSheet(date: d, gid: g)
        }
    }
}

// MARK: - Shared parts

/// Summary: calories left hero + macros
struct NutSummary: View {
    var eaten: Macros
    var target: Macros
    var compact = false
    var body: some View {
        let left = target.kcal - eaten.kcal
        let pct = eaten.kcal / max(1, target.kcal)
        VStack(spacing: 12) {
            // Dark hero: calories left + ring (Figma "Nutrition day")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(left >= 0 ? "Kalan" : "Hedefin üstünde").font(.bSm).foregroundStyle(Color.bHeroMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(left < 0 ? "+" + fmt0(-left) : fmt0(left)).font(.bNum(46, relativeTo: .largeTitle)).foregroundStyle(left < 0 ? Color(red: 1, green: 0.39, blue: 0.4) : Color.bHeroFg)
                            .contentTransition(.numericText(value: left))
                        Text("kcal").font(.bSm).foregroundStyle(Color.bHeroMuted)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    Text(String(localized: "\(fmt0(eaten.kcal)) yendi · hedef \(fmt0(target.kcal))")).font(.bXs).monospacedDigit().foregroundStyle(Color.bHeroMuted)
                }
                Spacer(minLength: 0)
                if !compact {
                    ZStack {
                        Circle().stroke(Color.bHeroFill, lineWidth: 10)
                        Circle().trim(from: 0, to: min(1, pct)).stroke(Color.bHeroAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                        Ti("flame", size: 22).foregroundStyle(Color.bHeroAccent)
                    }
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                }
            }
            .bHeroCard()
            NutMacroRow(eat: eaten, plan: target)
        }
        .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.6).delay(0.2), value: eaten)
    }
}

/// Week of day circles: number in a ring — green on target / done, red over, muted empty/future,
/// faint for rest days; selected filled. Shared by Nutrition, Workout and Today.
struct NutDayRings: View {
    enum DayStatus { case onTarget, over, empty, future, rest }
    @Binding var selected: Int
    var wk: Int
    var todayIndex: Int
    /// Workout plans ahead: future days stay tappable there
    var allowFuture = false
    var status: (Int) -> DayStatus
    /// Optional VoiceOver value per day (Workout: done / workout planned / rest)
    var value: ((Int) -> String)? = nil
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let st = status(i), sel = selected == i
                Button { haptic(); selected = i } label: {
                    VStack(spacing: 6) {
                        Text(DayKey.dayShort[i]).font(.geist(11, i == todayIndex ? .bold : .medium, relativeTo: .caption2))
                            .foregroundStyle(i == todayIndex ? Color.bFg : Color.bMutedFg)
                        ZStack {
                            Circle().fill(sel ? Color.bCard : Color.clear)
                            Circle().strokeBorder(ring(st), lineWidth: st == .onTarget || st == .over ? 2.5 : 1.5)
                            Text("\(Int(Wk.weekDate(i, wk).suffix(2)) ?? 0)").font(.bDisplay(15, relativeTo: .body))
                                .foregroundStyle(st == .future || st == .rest ? Color.bMutedFg : Color.bFg)
                        }
                        .frame(width: 38, height: 38).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background { if sel { RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).fill(Color.bCard.opacity(0.7)) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press)
                .disabled(st == .future && !allowFuture)
                .accessibilityLabel(DayKey.dayLong[i])
                .accessibilityValue(value?(i) ?? (st == .onTarget ? tl("Hedefte") : st == .over ? tl("Hedefin üstünde") : tl("Kayıt yok")))
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .animation(.snappy, value: selected)
    }
    private func ring(_ s: DayStatus) -> Color {
        switch s { case .onTarget: .bSuccess; case .over: .bDestructive; case .empty: Color.bFg.opacity(0.15); case .future, .rest: Color.bFg.opacity(0.08) }
    }
}

struct NutMacroRow: View {
    var eat: Macros
    var plan: Macros
    var body: some View {
        HStack(spacing: 10) {
            cell("Protein", eat.p, plan.p, .bProtein)
            cell("Karb.", eat.c, plan.c, .bCarb)
            cell("Yağ", eat.f, plan.f, .bFat)
        }
    }
    private func cell(_ l: String, _ v: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(fmt0(v)).font(.bNum(20)) + Text(" /\(fmt0(goal)) g").font(.bXs).foregroundColor(Color.bMutedFg))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            BProgress(value: v / max(1, goal), tint: tint, height: 5, label: l)
            Text(tl(l)).font(.bXs).foregroundStyle(Color.bMutedFg).lineLimit(1)
        }
        .foregroundStyle(Color.bFg)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bCard, in: RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Small ring next to a macro title
struct MacroMiniRing: View {
    var value: Double; var tint: Color
    var body: some View {
        BRings(rings: [(value, tint)], size: 16, stroke: 3) { EmptyView() }
    }
}

/// Four-macro table on bg-muted
struct NutMacroGrid: View {
    var m: Macros
    var whole = false
    var body: some View {
        HStack {
            ForEach([("kcal", m.kcal), ("Protein", m.p), ("Karb.", m.c), ("Yağ", m.f)], id: \.0) { l, v in
                VStack(spacing: 2) {
                    Text(l).font(.bXs).foregroundStyle(Color.bMutedFg)
                    Text(whole ? fmt0(v) : fmt1(v)).font(.bNum(16))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.bMuted, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
    }
}

struct NutThumb: View {
    var url: String? = nil
    var size: CGFloat = 40
    var name: String? = nil
    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { placeholder }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
    }
    private var placeholder: some View {
        let _ = FoodImages.shared.version
        return ZStack {
            Color.bMuted
            if let n = name, let img = FoodImages.get(n) { Image(uiImage: img).resizable().scaledToFill() }
            else if let e = name.flatMap(FoodEmoji.of) { Text(e).font(.system(size: size * 0.52)) }
            else { Ti("tools-kitchen-2", size: 16).foregroundStyle(Color.bMutedFg) }
        }
    }
}

struct NutEmpty<A: View>: View {
    var icon: String
    var title: String
    var text: String? = nil
    @ViewBuilder var action: A
    var body: some View {
        VStack(spacing: 8) {
            Ti(icon, size: 24).foregroundStyle(Color.bMutedFg)
            Text(tl(title)).font(.geist(16, .medium))
            if let text { Text(tl(text)).font(.bSm).foregroundStyle(Color.bMutedFg).multilineTextAlignment(.center) }
            action
        }
        .padding(.horizontal, 24).padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous).strokeBorder(Color.bBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
extension NutEmpty where A == EmptyView {
    init(icon: String, title: String, text: String? = nil) { self.init(icon: icon, title: title, text: text) { EmptyView() } }
}

struct NutSectionTitle<A: View>: View {
    var title: String
    @ViewBuilder var action: A
    var body: some View {
        HStack {
            Text(tl(title).uppercased(with: .current)).font(.geist(12, .medium, relativeTo: .caption)).tracking(0.6).foregroundStyle(Color.bMutedFg)
            Spacer()
            action
        }
        .padding(.top, 8)
    }
}
extension NutSectionTitle where A == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Divided rows inside a card
struct NutDivider: View { var body: some View { Rectangle().fill(Color.bBorder).frame(height: 1) } }

/// List card: dividers between rows
struct NutList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                if i > 0 { NutDivider() }
                row(x)
            }
        }
        .bCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
    }
}

/// Food row (thumbnail + name + subtitle)
struct NutFoodRow<Trailing: View>: View {
    var title: String
    var sub: String
    var url: String? = nil
    var thumb: CGFloat = 40
    var action: () -> Void
    @ViewBuilder var trailing: Trailing
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                NutThumb(url: url, size: thumb, name: title)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                    Text(tl(sub)).font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(NutRowPress())
    }
}
extension NutFoodRow where Trailing == EmptyView {
    init(title: String, sub: String, url: String? = nil, thumb: CGFloat = 40, action: @escaping () -> Void) {
        self.init(title: title, sub: sub, url: url, thumb: thumb, action: action) { EmptyView() }
    }
}

/// Accent fill while a row is pressed
struct NutRowPress: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.background(c.isPressed ? Color.bAccent : Color.clear)
    }
}

/// Meal picker: hidden when only one meal is used
struct NutMealField: View {
    @Binding var meal: Meal
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    var body: some View {
        let ms = nutMeals(profiles.first, include: meal)
        if ms.count > 1 {
            BField(label: "Öğün") {
                BSegmented(selection: $meal, options: ms.map { ($0, $0.nutShortLabel) })
            }
        }
    }
}

// MARK: - Log

struct NutDiary: View {
    /// Meal shown in the log (segmented); nil = the meal for this time of day
    @State private var mealSel: Meal?
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(AppState.self) private var app
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    /// Only the selected week's days and the day before; not the whole history on every render
    @Query private var days: [DayLog]
    @Binding var date: String
    @Binding var sheet: NutSheet?
    init(date: Binding<String>, sheet: Binding<NutSheet?>) {
        _date = date; _sheet = sheet
        let d = date.wrappedValue
        let monday = DayKey.shift(d, days: -DayKey.weekday(d))
        let from = DayKey.shift(monday, days: -1), to = DayKey.shift(monday, days: 6)
        _days = Query(filter: #Predicate<DayLog> { $0.date >= from && $0.date <= to })
    }

    var body: some View {
        let profile = profiles.first ?? UserProfile()
        let day = days.day(date)
        let yKey = DayKey.shift(date, days: -1)
        let yest = days.day(yKey)
        let entries = day?.entries ?? []
        let e = Energy.summary(profile: profile, health: health, day: day, latestMeasureKg: Store.latestWeight(ctx), isToday: date == DayKey.today)
        let target = Macros(kcal: e.target, p: profile.proteinG, c: profile.carbsG, f: profile.fatG)
        let on = profile.meals
        let meals = Meal.allCases.filter { m in on.contains(m) || entries.contains { $0.meal == m } }

        // Day picker: week of day rings (on target, over, empty)
        let wk = Self.weekOffset(date)
        NutDayRings(selected: Binding(get: { DayKey.weekday(date) }, set: { date = min(Wk.weekDate($0, wk), DayKey.today) }), wk: wk,
                    todayIndex: wk == 0 ? DayKey.weekday(DayKey.today) : -1) { i in
            let k = Wk.weekDate(i, wk)
            let kc = days.day(k)?.eaten.kcal ?? 0
            guard k <= DayKey.today, kc > 0 else { return k > DayKey.today ? .future : .empty }
            return kc <= target.kcal * 1.05 ? .onTarget : .over
        }

        // nutrition summary and (when on) fasting are separate cards; no action on the fasting card
        NutSummary(eaten: day?.eaten ?? .zero, target: target)
        if profile.fastOn {
            FastCard(profile: profile, embedded: true).bCard()
        }

        // one meal at a time, picked with a segmented control (defaults to the meal for this time of day);
        // no global "Log food": the meal card has its own button, and the add screen opens with that meal
        let cur = mealSel.flatMap { meals.contains($0) ? $0 : nil } ?? Meal.default(enabled: meals)
        let list = entries.filter { $0.meal == cur }
        let ylist = (yest?.entries ?? []).filter { $0.meal == cur }
        // picker sits inside the card, at the top (like the muscle card); one meal shows at a time
        mealCard(cur, list: list, ylist: ylist,
                 picker: meals.count > 1 ? AnyView(BSegmented(selection: Binding(get: { cur }, set: { m in withAnimation(.snappy(duration: 0.25)) { mealSel = m } }),
                                                              options: meals.map { ($0, $0.nutShortLabel) })) : nil)
    }

    /// Week offset of the selected day relative to this week (0 = this week, -1 = last week)
    static func weekOffset(_ d: String) -> Int {
        let m1 = DayKey.shift(d, days: -DayKey.weekday(d)), m0 = DayKey.shift(DayKey.today, days: -DayKey.weekday(DayKey.today))
        guard let a = DayKey.date(m1), let b = DayKey.date(m0) else { return 0 }
        return Int((a.timeIntervalSince(b) / 86400 / 7).rounded())
    }

    @ViewBuilder private func mealCard(_ m: Meal, list: [FoodEntry], ylist: [FoodEntry], picker: AnyView? = nil) -> some View {
        let kcal = list.reduce(0) { $0 + $1.macros.kcal }, p = list.reduce(0) { $0 + $1.macros.p }
        VStack(spacing: 0) {
            if let picker {
                VStack(alignment: .leading, spacing: 10) {
                    picker
                    Text(list.isEmpty ? "Henüz eklenmedi" : "\(fmt0(kcal)) kcal · P \(fmt0(p)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                        .padding(.horizontal, 4)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
            } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tl(m.label)).font(.geist(16, .semibold))
                    Text(list.isEmpty ? "Boş" : "\(fmt0(kcal)) kcal · P \(fmt0(p)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            }

            if !list.isEmpty {
                VStack(spacing: 0) {
                    ForEach(NutDiaryRow.rows(list)) { row in
                      VStack(spacing: 0) {
                        NutDivider()
                        if case .group(let gid, let name, let items) = row.kind {
                            groupRow(gid: gid, name: name, items: items)
                        } else if case .single(let e) = row.kind {
                            singleRow(e)
                        }
                      }
                      // new entries slide in from the top
                      .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.35).delay(0.25), value: list.map(\.id))
            }
            mealActions(m, list: list, ylist: ylist)
        }
        .bCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
    }

    /// Meal card footer: Log food (opens with this meal) · Save meal as template
    private func mealActions(_ m: Meal, list: [FoodEntry], ylist: [FoodEntry]) -> some View {
        VStack(spacing: 0) {
            if !list.isEmpty { NutDivider() }
            HStack(spacing: 8) {
                Button { app.open(.addFood(date: date, meal: m)) } label: { BLabel("Yediğini ekle", icon: "plus") }
                    .buttonStyle(.b(.secondary, .small))
                    .accessibilityLabel("\(m.nutShortLabel) öğününe yediğini ekle")
                if !list.isEmpty {
                    Button { sheet = .saveTemplate(meal: m, items: list) } label: { BLabel("Şablon olarak kaydet", icon: "template") }
                        .buttonStyle(.b(.ghost, .small)).bButtonFg(Color.bMutedFg)
                        .accessibilityLabel("\(m.nutShortLabel) öğününü şablon olarak kaydet")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    /// Single food row
    private func singleRow(_ e: FoodEntry) -> some View {
        Button { sheet = .entry(date: date, id: e.id) } label: {
                            HStack(spacing: 12) {
                                NutThumb(size: 36, name: e.foodName.isEmpty ? e.name : e.foodName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                                    Text("P \(fmt1(e.macros.p)) · K \(fmt1(e.macros.c)) · Y \(fmt1(e.macros.f)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit()
                                }
                                Spacer(minLength: 0)
                                (Text(fmt0(e.macros.kcal)).font(.bSm) + Text(" kcal").font(.bXs).foregroundStyle(Color.bMutedFg)).monospacedDigit().foregroundStyle(Color.bFg)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(NutRowPress())
                        .bSwipeDelete { remove(e) }
                        .contextMenu {
                            Button(role: .destructive) { remove(e) } label: { Label("Sil", systemImage: "trash") }
                        }
    }

    /// Group added from a saved meal: one row; tapping opens it for editing
    private func groupRow(gid: String, name: String, items: [FoodEntry]) -> some View {
        let t = items.reduce(Macros.zero) { $0 + $1.macros }
        return Button { sheet = .group(date: date, gid: gid) } label: {
            HStack(spacing: 12) {
                Ti("template", size: 18).foregroundStyle(Color.bPrimary).frame(width: 36, height: 36)
                    .background(Color.bPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                    Text("\(items.count) kalem · P \(fmt1(t.p)) · K \(fmt1(t.c)) · Y \(fmt1(t.f)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
                (Text(fmt0(t.kcal)).font(.bSm) + Text(" kcal").font(.bXs).foregroundStyle(Color.bMutedFg)).monospacedDigit().foregroundStyle(Color.bFg)
            }
            .padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(NutRowPress())
        .bSwipeDelete { removeGroup(gid, name: name) }
        .contextMenu {
            Button(role: .destructive) { removeGroup(gid, name: name) } label: { Label("Sil", systemImage: "trash") }
        }
        .accessibilityHint("İçeriği görmek ve düzenlemek için dokun")
    }

    private func removeGroup(_ gid: String, name: String) {
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(name) silindi"), kind: .delete) { E in
            E.removeAll { $0.group == gid }
        }
    }

    private func copy(_ m: Meal, _ items: [FoodEntry]) {
        haptic()
        // yesterday's groups get a new group id today
        var gmap: [String: String] = [:]
        for g in Set(items.compactMap(\.group)) { gmap[g] = UUID().uuidString }
        NutEntries.change(ctx, date: date, app: app, toast: "Dünkü öğün eklendi") { E in
            E += items.map { var x = $0; x.id = UUID().uuidString; x.meal = m; x.group = x.group.flatMap { gmap[$0] }; return x }
        }
    }
    private func remove(_ e: FoodEntry) {
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(e.foodName.isEmpty ? e.name : e.foodName) silindi"), kind: .delete) { E in
            E.removeAll { $0.id == e.id }
        }
    }
}

struct NutTrendSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthService.self) private var health
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Binding var date: String
    @State private var range = 7

    var body: some View {
        let profile = profiles.first ?? UserProfile()
        let e = Energy.summary(profile: profile, health: health, day: nil, latestMeasureKg: Store.latestWeight(ctx), isToday: true)
        let kcal = e.target
        let data = nutTrend(ctx, range: range, proteinGoal: profile.proteinG)
        let mx = max(kcal * 1.25, data.rows.map(\.kcal).max() ?? 0, 1)
        BSheet(title: "Beslenme trendi", description: "Bir güne dokun, o günün kaydına git.") {
            BSegmented(selection: $range, options: [(7, "Son 7 gün"), (30, "Son 30 gün")])
            HStack {
                stat("Ort. kalori", data.logged > 0 ? fmt0(data.avg) : "–")
                stat("Protein hedefi", data.logged > 0 ? "%\(fmt0(data.pPct * 100))" : "–")
                stat("Kayıtlı gün", "\(data.logged)/\(range)")
            }
            GeometryReader { g in
                ZStack(alignment: .bottomLeading) {
                    Path { p in let y = g.size.height * (1 - kcal / mx); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                        .stroke(Color.bFg.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    HStack(alignment: .bottom, spacing: range == 7 ? 8 : 2) {
                        ForEach(data.rows) { r in
                            let sel = r.k == date, over = r.kcal > kcal * 1.1
                            Button { date = r.k; dismiss() } label: {
                                VStack(spacing: 3) {
                                    Spacer(minLength: 0)
                                    UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5)
                                        .fill(!r.logged ? Color.bFg.opacity(0.1) : over ? Color.bDestructive.opacity(sel ? 1 : 0.4) : Color.bPrimary.opacity(sel ? 1 : 0.35))
                                        .frame(maxWidth: range == 7 ? 28 : .infinity)
                                        .frame(height: r.logged ? max(4, (g.size.height - 8) * r.kcal / mx) : 4)
                                    Circle().fill(sel ? Color.bFg : .clear).frame(width: 4, height: 4)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // going over the goal isn't conveyed by color alone
                            .accessibilityLabel("\(nutShortDate(r.k)): \(r.logged ? "\(fmt0(r.kcal)) kcal\(over ? ", hedefin üstünde" : "")" : "kayıt yok")")
                        }
                    }
                }
            }
            .frame(height: 144)
            .animation(.easeOut(duration: 0.5), value: range)
            if range == 7 {
                HStack(spacing: 8) {
                    ForEach(data.rows) { r in
                        Text(DayKey.dayShort[DayKey.weekday(r.k)]).font(.geist(11, r.k == date ? .semibold : .regular, relativeTo: .caption2)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(r.k == date ? Color.bFg : Color.bMutedFg).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, -8)
            }
            HStack {
                HStack(spacing: 6) {
                    Rectangle().stroke(Color.bFg.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 16, height: 1)
                    Text("Hedef \(fmt0(kcal)) kcal")
                }
                Spacer()
                if data.weights.count > 1, let a = data.weights.first, let b = data.weights.last {
                    let wd = b - a
                    HStack(spacing: 6) {
                        NutSpark(pts: data.weights).stroke(Color.bMutedFg, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 36, height: 14)
                        Text("Kilo \(wd > 0 ? "+" : wd < 0 ? "−" : "")\(fmt1(abs(wd))) kg").monospacedDigit()
                    }
                }
            }
            .font(.bXs).foregroundStyle(Color.bMutedFg)
        }
        .presentationDetents([.medium, .large])
    }
    private func stat(_ l: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(tl(l)).font(.bXs).foregroundStyle(Color.bMutedFg)
            Text(v).font(.bNum(16))
        }
        .frame(maxWidth: .infinity)
    }
}

struct NutSpark: Shape {
    var pts: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard pts.count > 1, let mn = pts.min(), let mx = pts.max() else { return p }
        for (i, v) in pts.enumerated() {
            let x = r.width * Double(i) / Double(pts.count - 1)
            let y = mx == mn ? r.height / 2 : r.height - (v - mn) / (mx - mn) * r.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - Besinlerim

/// Profile › My foods: your own foods, add and edit (pushed screen)
struct MyFoodsScreen: View {
    @State private var sheet: NutSheet?
    @State private var date = DayKey.today
    var body: some View {
        BScreen(pinHeader: false) {
            WkPushedHeader(eyebrow: "Profil", title: "Besinlerim")
            NutSavedMeals(sheet: $sheet)
            NutMyFoods(sheet: $sheet)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { s in NutSheetHost(sheet: s, date: $date, open: { sheet = $0 }) }
    }
}

struct NutMyFoods: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var foods: [SavedFood]
    @Binding var sheet: NutSheet?
    @State private var q = ""

    var body: some View {
        let nq = TextNorm.norm(q)   // "cig" also finds "Çiğ"
        let list = foods.filter { nq.isEmpty || TextNorm.norm($0.name).contains(nq) }
        if foods.isEmpty {
            // empty state: one primary action; search/barcode secondary
            BEmpty(symbol: "fork.knife", title: "Henüz besin yok", text: "Sık yediğin besinleri kaydet; yediğini eklerken en üstte çıkarlar.",
                   action: "Yeni besin") { sheet = .foodEdit(nil) }
            Button { sheet = .add(.myfood) } label: { BLabel("Ara ya da barkod okut", icon: "world") }
                .buttonStyle(.b(.ghost, full: true))
        } else {
        HStack(spacing: 8) {
            Button { sheet = .foodEdit(nil) } label: { BLabel("Yeni besin", icon: "plus") }.buttonStyle(.b(.primary, full: true))
            Button { sheet = .add(.myfood) } label: { BLabel("Ara / barkod", icon: "world") }.buttonStyle(.b(.outline, full: true))
        }
        TextField("Besinlerimde ara", text: $q).textFieldStyle(.b)
        if list.isEmpty {
            Text("Aramana uyan besin yok.").font(.bSm).foregroundStyle(Color.bMutedFg)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            NutList(items: list) { f in
                NutFoodRow(title: f.name, sub: String(localized: "100 g · \(fmt0(f.per100.kcal)) kcal · P \(fmt1(f.per100.p)) · K \(fmt1(f.per100.c)) · Y \(fmt1(f.per100.f))"),
                           action: { sheet = .foodEdit(f) }) {
                    Ti("chevron-right").foregroundStyle(Color.bMutedFg)
                }
                .bSwipeDelete { del(f) }
            }
        }
        }
    }
    private func del(_ f: SavedFood) {
        let name = f.name, per = f.per100, por = f.portions, bc = f.barcode
        withAnimation { ctx.delete(f) }
        Store.save(ctx)
        app.toast(String(localized: "\(name) silindi"), kind: .delete) {
            ctx.insert(SavedFood(name: name, per100: per, portions: por, barcode: bc)); Store.save(ctx)
        }
    }
}

// MARK: - Saved meals (Profile › My foods › Saved meals)

/// Single row above My foods: opens its own screen like My programs; the screen stays short even with a long list
struct NutSavedMeals: View {
    @Binding var sheet: NutSheet?
    var body: some View {
        let n = NutLocal.shared.templates.filter { !$0.items.isEmpty }.count
        NavigationLink { SavedMealsScreen() } label: {
            HStack(spacing: 12) {
                Ti("template", size: 18).foregroundStyle(Color.bPrimary).frame(width: 36, height: 36)
                    .background(Color.bPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kayıtlı öğünlerim").font(.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                    Text(n == 0 ? String(localized: "Sık yediğin öğünleri kaydet") : String(localized: "\(n) öğün")).font(.bXs).foregroundStyle(Color.bMutedFg)
                }
                Spacer(minLength: 0)
                Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
            }
            .padding(.horizontal, 12).frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .bCard(padding: 0)
        NutSectionTitle("Besinler")
    }
}

/// Saved meals: search, open, edit (name, meal, items and grams), delete, create
struct SavedMealsScreen: View {
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var sheet: NutSheet?
    @State private var date = DayKey.today
    @State private var q = ""

    var body: some View {
        let store = NutLocal.shared
        let all = store.templates.filter { !$0.items.isEmpty }
        let nq = TextNorm.norm(q)
        let list = all.filter { nq.isEmpty || TextNorm.norm($0.name).contains(nq) }
        BScreen(pinHeader: false) {
            WkPushedHeader(eyebrow: "Besinlerim", title: "Kayıtlı öğünlerim")
            Button { newMeal() } label: { BLabel("Yeni kayıtlı öğün", icon: "plus") }.buttonStyle(.b(.primary, full: true))
            if all.count > 6 { TextField("Kayıtlı öğünlerde ara", text: $q).textFieldStyle(.b) }
            if all.isEmpty {
                BEmpty(symbol: "fork.knife", title: "Henüz kayıtlı öğün yok",
                       text: "Beslenme'de bir öğün kartındaki kaydet ikonuna bas ya da buradan yeni bir öğün oluştur; yediğini eklerken Kayıtlı öğünler'den seçersin.")
            } else if list.isEmpty {
                Text("Aramana uyan öğün yok.").font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                NutList(items: list) { t in
                    NutFoodRow(title: t.name, sub: String(localized: "\(t.items.count) kalem · \(fmt0(t.kcal)) kcal · P \(fmt0(t.p)) g"),
                               action: { sheet = .template(id: t.id, isNew: false) }) {
                        Ti("chevron-right").foregroundStyle(Color.bMutedFg)
                    }
                    .bSwipeDelete { delete(t) }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { s in NutSheetHost(sheet: s, date: $date, open: { sheet = $0 }) }
    }

    private func newMeal() {
        let t = NutTemplate(name: String(localized: "Kayıtlı öğün"), meal: nutDefaultMeal(profiles.first), items: [])
        NutLocal.shared.templates.insert(t, at: 0)
        sheet = .template(id: t.id, isNew: true)
    }
    private func delete(_ t: NutTemplate) {
        let store = NutLocal.shared
        guard let i = store.templates.firstIndex(where: { $0.id == t.id }) else { return }
        withAnimation { _ = store.templates.remove(at: i) }
        app.toast(String(localized: "\(t.name) silindi"), kind: .delete) { store.templates.insert(t, at: min(i, store.templates.count)) }
    }
}

// MARK: - Sharing

struct NutShareBar: View {
    enum Kind { case foods, recipes }
    var kind: Kind
    @Environment(\.modelContext) private var ctx
    @Environment(AppState.self) private var app
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var foods: [SavedFood]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var importing = false

    var body: some View {
        let rs = recipes.filter { !$0.name.isEmpty && !$0.items.isEmpty }
        let empty = kind == .foods ? foods.isEmpty : rs.isEmpty
        HStack(spacing: 8) {
            ShareLink(item: NutShare.export(foods: kind == .foods ? foods : [], recipes: kind == .recipes ? rs : []),
                      preview: SharePreview("GYM Paper paylaşımı")) {
                BLabel(kind == .foods ? "Besinleri paylaş" : "Tarifleri paylaş", icon: "share-2")
            }
            .buttonStyle(.b(.outline, full: true)).disabled(empty)
            Button { importing = true } label: { BLabel("İçe al", icon: "file-import") }.buttonStyle(.b(.outline, full: true))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case .success(let url) = r { NutShare.importFile(url, ctx: ctx, app: app) }
        }
    }
}

// MARK: - Tarifler

struct NutRecipes: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Binding var sheet: NutSheet?

    var body: some View {
        Button {
            let r = Recipe(name: "", servings: 2, items: [])
            ctx.insert(r)
            sheet = .recipeForm(r, isNew: true)
        } label: { BLabel("Yeni tarif", icon: "plus") }
        .buttonStyle(.b(.primary, full: true))
        if recipes.isEmpty {
            NutEmpty(icon: "chef-hat", title: "Tarif defterin boş", text: "Malzemeleri gramajıyla gir; porsiyon başı kalori ve makro otomatik hesaplanır.")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(recipes) { r in
                    Button { sheet = .recipe(r) } label: { card(r) }.buttonStyle(.press)
                }
            }
        }
    }

    private func card(_ r: Recipe) -> some View {
        let t = r.totals
        return VStack(alignment: .leading, spacing: 0) {
            ZStack { Color.bMuted; Ti("chef-hat", size: 28).foregroundStyle(Color.bMutedFg) }
                .aspectRatio(4 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name.isEmpty ? "Adsız tarif" : r.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                Text("\(fmt0(t.perServing.kcal)) kcal · P \(fmt0(t.perServing.p)) g / porsiyon").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
            }
            .padding(12)
        }
        .bCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
    }
}

// MARK: - Log rows: single food or saved meal group

struct NutDiaryRow: Identifiable {
    enum Kind { case single(FoodEntry), group(String, String, [FoodEntry]) }
    var id: String
    var kind: Kind

    /// Items with the same group id collapse into one row where they first appear
    static func rows(_ list: [FoodEntry]) -> [NutDiaryRow] {
        var out: [NutDiaryRow] = [], seen = Set<String>()
        for e in list {
            if let g = e.group {
                guard seen.insert(g).inserted else { continue }
                let items = list.filter { $0.group == g }
                out.append(NutDiaryRow(id: "g" + g, kind: .group(g, e.groupName ?? String(localized: "Kayıtlı öğün"), items)))
            } else {
                out.append(NutDiaryRow(id: e.id, kind: .single(e)))
            }
        }
        return out
    }
}

/// Group in the log: shows its contents, grams and items can be edited; changes update that day's calories
struct NutGroupSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let date: String
    let gid: String
    @State private var items: [FoodEntry] = []
    @State private var name = ""
    @State private var meal: Meal = .kahvalti
    @State private var loaded = false
    @State private var sub: NutSheet?

    var body: some View {
        BSheet(title: name.isEmpty ? String(localized: "Kayıtlı öğün") : name) {
            BField(label: "Ad") { TextField("", text: $name).textFieldStyle(.b) }
            NutMealField(meal: $meal)
            NutMealEditor(items: $items) { sub = .add(.collect("group", { e in items.append(e) })) }
        } footer: {
            Button { save() } label: { BLabel("Kaydet", icon: "check") }.buttonStyle(.b(.primary, .large, full: true))
            Button("Öğünü sil") { delete() }.buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
        }
        .presentationDetents([.large])
        .sheet(item: $sub) { s in NutSheetHost(sheet: s, date: .constant(date), open: { sub = $0 }) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let all = Store.day(ctx, date, create: false)?.entries ?? []
            items = all.filter { $0.group == gid }
            name = items.first?.groupName ?? ""
            meal = items.first?.meal ?? nutDefaultMeal(nil)
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Kayıtlı öğün") : String(name.prefix(60))
        let m = meal, list = items
        haptic()
        NutEntries.change(ctx, date: date, app: app, toast: list.isEmpty ? String(localized: "\(n) silindi") : String(localized: "\(n) güncellendi")) { E in
            let at = E.firstIndex { $0.group == gid } ?? E.count
            E.removeAll { $0.group == gid }
            let new = list.map { var x = $0; x.meal = m; x.group = gid; x.groupName = n; return x }
            E.insert(contentsOf: new, at: min(at, E.count))
        }
        dismiss()
    }

    private func delete() {
        let n = name
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(n) silindi"), kind: .delete) { E in E.removeAll { $0.group == gid } }
        dismiss()
    }
}

