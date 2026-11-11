import SwiftUI
import SwiftData
import VisionKit
import AVFoundation
import GymPaperKit

// Add food: Search (My foods + built-in list + online) · Barcode · Recipe · Template
// PWA AddFoodSheet + Amount + Scanner + RecipePick + Templates

/// Where the added food goes
enum NutTarget: Identifiable {
    case log(date: String, meal: Meal?)
    case myfood
    case recipe(Recipe)
    case template(String)
    /// Adds the food to a list (saved meal draft, a meal group in the log); never written to the log directly
    case collect(String, (FoodEntry) -> Void)
    var id: String {
        switch self {
        case .log(let d, let m): "log\(d)\(m?.rawValue ?? "")"
        case .myfood: "myfood"
        case .recipe(let r): "recipe\(r.persistentModelID.hashValue)"
        case .template(let t): "tpl\(t)"
        case .collect(let k, _): "collect\(k)"
        }
    }
    var isLog: Bool { if case .log = self { true } else { false } }
    var isTemplate: Bool { if case .template = self { true } else { false } }
    var isMyFood: Bool { if case .myfood = self { true } else { false } }
    var isCollect: Bool { if case .collect = self { true } else { false } }
}

struct AddFoodSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var saved: [SavedFood]
    let target: NutTarget

    enum Mode: Hashable { case search, mine, barcode, recipe, template }
    @State private var mode = Mode.search
    @State private var q = ""
    @State private var onlineState: OnlineState = .idle
    @State private var pick: FoodItem?
    @State private var pickLastG: Double?
    @State private var label: String?           // barcode not found → save from label
    @State private var meal: Meal = .ara
    @State private var mealSet = false
    @State private var sub: NutSheet?
    /// Saved meals: whether the list is open; this-time-only draft of the picked meal (not written to the template)
    @State private var mealsOpen = false
    @State private var mealQ = ""
    @State private var draft: NutMealDraft?
    /// The search field auto-focuses only on first open
    @State private var focusSearch = true
    @State private var reported: Set<String> = []

    enum OnlineState: Equatable { case idle, loading, done([FoodItem]), error(String) }

    init(date: String, meal: Meal?) { self.target = .log(date: date, meal: meal) }
    init(target: NutTarget) { self.target = target }

    private var title: String {
        switch target {
        case .recipe: "Malzeme ekle"
        case .myfood: "Besinlerime ekle"
        case .template: "Kayıtlı öğüne ekle"
        case .collect: "Öğüne besin ekle"
        case .log: "Yediğini ekle"
        }
    }

    var body: some View {
        BSheet(title: draft?.name ?? (mealsOpen ? String(localized: "Kayıtlı öğünler") : pick?.name ?? (label != nil ? String(localized: "Etiketten kaydet") : title))) {
            if draft != nil {
                draftEditor
            } else if mealsOpen {
                mealsList
            } else if let code = label, pick == nil {
                NutLabelForm(code: code, onBack: { label = nil }) { food in
                    if target.isMyFood { app.toast("Besinlerime kaydedildi"); haptic(); dismiss() } else { label = nil; pickLastG = nil; pick = food }
                }
            } else if let food = pick {
                NutAmount(food: food, lastG: pickLastG, target: target, meal: $meal, onBack: { pick = nil }) { g, lbl in done(food, g: g, label: lbl) }
            } else {
                // the meal is preselected: the meal card's meal when opened from it, by time of day from Today
                if target.isLog { NutMealField(meal: $meal) }
                BSegmented(selection: $mode, options: modes, neutral: true)
                switch mode {
                case .template: templates
                case .recipe: recipePick
                case .search: search
                case .mine: myFoods
                case .barcode:
                    NutScanner(onFound: { f in pickLastG = nil; pick = f }, onManual: { label = $0 })
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !mealSet else { return }
            mealSet = true
            if case .log(_, let m) = target { meal = m ?? nutDefaultMeal(profiles.first) } else { meal = nutDefaultMeal(profiles.first) }
        }
        .sheet(item: $sub) { s in NutSheetHost(sheet: s, date: .constant(DayKey.today), open: { sub = $0 }) }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.24), value: pick?.id)
    }

    private var modes: [(Mode, String)] {
        // Log food: Search · My foods · Barcode
        // "Arama", not "Ara": the meal picker above already has "Ara" (snack)
        if target.isLog || target.isCollect { return [(.search, "Arama"), (.mine, "Besinlerim"), (.barcode, "Barkod")] }
        var m: [(Mode, String)] = [(.search, "Arama"), (.barcode, "Barkod")]
        if target.isTemplate { m.append((.recipe, "Tarif")) }
        return m
    }

    private var mine: [FoodItem] {
        saved.map { FoodItem(id: "mine-\($0.persistentModelID.hashValue)", name: $0.name, per100: $0.per100, portions: $0.portions, source: .mine, barcode: $0.barcode) }
    }

    // MARK: Besinlerim

    @ViewBuilder private var myFoods: some View {
        savedMeals
        Button { sub = .foodEdit(nil) } label: { BLabel("Yeni besin", icon: "plus") }.buttonStyle(.b(.outline, full: true))
        if mine.isEmpty {
            Text("Henüz besin yok. Sık yediklerini kaydet; buradan tek dokunuşla eklersin.")
                .font(.bSm).foregroundStyle(Color.bMutedFg).padding(.horizontal, 4)
        } else {
            NutList(items: mine) { f in
                NutFoodRow(title: f.name, sub: String(localized: "100 g · \(fmt0(f.per100.kcal)) kcal · P \(fmt1(f.per100.p))")) { pickLastG = nil; pick = f }
            }
        }
    }

    // MARK: Ara

    @ViewBuilder private var search: some View {
        let term = q.trimmingCharacters(in: .whitespaces)
        let local = term.isEmpty ? mine : FoodSearch.local(term, mine: mine)
        let recent = term.isEmpty ? nutRecentFoods(ctx) : []
        NutSearchField(placeholder: "Besin ara: tavuk, yulaf, pizza…", text: $q, autoFocus: $focusSearch)
            .onChange(of: q) { onlineState = .idle }
        if term.isEmpty { savedMeals }
        if term.isEmpty && !recent.isEmpty {
            NutSectionTitle("Son eklenenler")
            NutList(items: recent) { r in
                NutFoodRow(title: r.food.name, sub: String(localized: "son: \(fmt0(r.lastG)) g · \(fmt0(r.food.per100.kcal * r.lastG / 100)) kcal")) { pickLastG = r.lastG; pick = r.food }
            }
        }
        if term.isEmpty && !local.isEmpty { NutSectionTitle("Besinlerim") }
        if term.isEmpty && local.isEmpty && recent.isEmpty {
            Text("Yediğin besinin adını yaz. Listede yoksa internette ararız ya da barkodunu okutursun.")
                .font(.bSm).foregroundStyle(Color.bMutedFg).padding(.horizontal, 4)
        }
        if !term.isEmpty || !local.isEmpty {
            if local.isEmpty {
                Text("Listede yok. İnternette arayabilirsin.").font(.bSm).foregroundStyle(Color.bMutedFg)
                    .padding(.horizontal, 16).padding(.vertical, 12).bCard(padding: 0)
            } else {
                NutList(items: local) { f in
                    NutFoodRow(title: f.name, sub: String(localized: "100 g · \(fmt0(f.per100.kcal)) kcal · P \(fmt1(f.per100.p))"), action: { pickLastG = nil; pick = f }) {
                        if f.source == .mine && !term.isEmpty { BBadge(variant: .soft) { Text("Benim") } }
                    }
                }
            }
        }
        if term.count > 1 {
            switch onlineState {
            case .idle:
                Button { Task { await goOnline(term) } } label: { BLabel(String(localized: "İnternette ara: “\(term)”"), icon: "world") }
                    .buttonStyle(.b(.outline, full: true))
            case .loading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("İnternette aranıyor") }
                    .font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity).padding(.vertical, 12)
            case .error(let msg):
                VStack(alignment: .leading, spacing: 8) {
                    Text(msg).font(.bSm).foregroundStyle(Color.bDestructive)
                    Button { Task { await goOnline(term) } } label: { BLabel("Tekrar dene", icon: "world") }.buttonStyle(.b(.outline, full: true))
                }
            case .done(let items):
                NutSectionTitle("İnternetten · FatSecret, Open Food Facts")
                if items.isEmpty {
                    Text("Sonuç yok. Farklı bir kelime dene ya da besini elle ekle.").font(.bSm).foregroundStyle(Color.bMutedFg)
                        .padding(.horizontal, 16).padding(.vertical, 12).bCard(padding: 0)
                } else {
                    NutList(items: items) { f in
                        NutFoodRow(title: f.name, sub: String(localized: "100 g · \(fmt0(f.per100.kcal)) kcal · P \(fmt1(f.per100.p))"), url: f.imageURL) { pickLastG = nil; pick = f }
                    }
                }
            }
            reportButton(term)
        }
    }

    /// If the food isn't found, report it with one tap; frequent requests are added to the built-in list
    @ViewBuilder private func reportButton(_ term: String) -> some View {
        let key = TextNorm.norm(term)
        if reported.contains(key) {
            Label("Bildirildi, teşekkürler", systemImage: "checkmark").font(.bSm).foregroundStyle(Color.bMutedFg)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            Button {
                haptic(); reported.insert(key)
                Task { await FoodRequests.send(term) }
                app.toast("Teşekkürler, listeye eklemeye çalışacağız")
            } label: { BLabel(String(localized: "Aradığın yok mu? “\(term)” eksik diye bildir"), icon: "mail-forward") }
                .buttonStyle(.b(.ghost, full: true))
        }
    }

    private func goOnline(_ term: String) async {
        onlineState = .loading
        let r = await FoodService.online(term)
        guard q.trimmingCharacters(in: .whitespaces) == term else { return }
        if let e = r.error, r.items.isEmpty { onlineState = .error(e) } else { onlineState = .done(r.items) }
    }

    // MARK: Tarif

    @ViewBuilder private var recipePick: some View {
        NutRecipePickList { f in pickLastG = nil; pick = f }
    }

    // MARK: Saved meals (log: menu → list → edit for this time → add)

    /// The list can grow (100+ meals): a single menu row in the tab; tapping opens a separate list
    @ViewBuilder private var savedMeals: some View {
        if target.isLog {
            let n = NutLocal.shared.templates.filter { !$0.items.isEmpty }.count
            Button { haptic(); mealQ = ""; withAnimation(.snappy) { mealsOpen = true } } label: {
                HStack(spacing: 12) {
                    Ti("template", size: 18).foregroundStyle(Color.bPrimary).frame(width: 36, height: 36)
                        .background(Color.bPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kayıtlı öğünler").font(.geist(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Color.bFg)
                        Text(n == 0 ? String(localized: "Beslenme'deki öğün kartından kaydet") : String(localized: "\(n) öğün"))
                            .font(.bXs).foregroundStyle(Color.bMutedFg)
                    }
                    Spacer(minLength: 0)
                    Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
                }
                .padding(.horizontal, 12).frame(minHeight: 60).contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .bCard(padding: 0)
        }
    }

    @ViewBuilder private var mealsList: some View {
        let all = NutLocal.shared.templates.filter { !$0.items.isEmpty }
        let nq = TextNorm.norm(mealQ)
        let list = all.filter { nq.isEmpty || TextNorm.norm($0.name).contains(nq) }
        Button { withAnimation(.snappy) { mealsOpen = false } } label: { BLabel("Geri", icon: "chevron-left") }
            .buttonStyle(.b(.ghost, .small)).frame(maxWidth: .infinity, alignment: .leading)
        if all.count > 6 { NutSearchField(placeholder: "Kayıtlı öğün ara", text: $mealQ) }
        if all.isEmpty {
            Text("Henüz kayıtlı öğünün yok. Beslenme'de bir öğün kartındaki kaydet ikonuyla kaydedebilirsin.")
                .font(.bSm).foregroundStyle(Color.bMutedFg).padding(.horizontal, 4)
        } else {
            NutList(items: list) { t in
                Button { open(t) } label: {
                    HStack(spacing: 12) {
                        NutThumb()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                            Text("\(t.items.count) kalem · \(fmt0(t.kcal)) kcal · P \(fmt0(t.p)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Ti("chevron-right", size: 16).foregroundStyle(Color.bMutedFg)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.press)
            }
        }
    }

    /// Picked meal: grams and items are edited for this entry only; the template doesn't change
    private func open(_ t: NutTemplate) {
        haptic()
        if case .log(_, let fixed) = target, fixed == nil, let m = t.meal { meal = m }
        withAnimation(.snappy) { draft = NutMealDraft(name: t.name, items: t.items.map { var x = $0; x.id = UUID().uuidString; x.group = nil; x.groupName = nil; return x }) }
    }

    @ViewBuilder private var draftEditor: some View {
        Button { withAnimation(.snappy) { draft = nil } } label: { BLabel("Kayıtlı öğünler", icon: "chevron-left") }
            .buttonStyle(.b(.ghost, .small)).frame(maxWidth: .infinity, alignment: .leading)
        NutMealField(meal: $meal)
        NutMealEditor(items: Binding(get: { draft?.items ?? [] }, set: { draft?.items = $0 })) {
            sub = .add(.collect("draft", { e in draft?.items.append(e) }))
        }
        Text("Buradaki değişiklikler yalnız bu kayda uygulanır; kayıtlı öğün değişmez.")
            .font(.bXs).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
        let kcal = (draft?.items ?? []).reduce(0) { $0 + $1.macros.kcal }
        Button { commitDraft() } label: { BLabel(String(localized: "Ekle · \(fmt0(kcal)) kcal"), icon: "plus") }
            .buttonStyle(.b(.primary, .large, full: true)).disabled((draft?.items ?? []).isEmpty)
    }

    private func commitDraft() {
        guard let d = draft, !d.items.isEmpty else { return }
        let date: String = { if case .log(let x, _) = target { return x }; return DayKey.today }()
        let gid = UUID().uuidString, m = meal
        haptic()
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(d.name) eklendi")) { E in
            E += d.items.map { var x = $0; x.id = UUID().uuidString; x.meal = m; x.group = gid; x.groupName = d.name; return x }
        }
        dismiss()
    }

    // MARK: Template

    @ViewBuilder private var templates: some View {
        let store = NutLocal.shared
        let list = store.templates.filter { !$0.items.isEmpty }
        let create = Button { newTemplate() } label: { BLabel("Yeni şablon", icon: "plus") }.buttonStyle(.b(.outline, full: true))
        if list.isEmpty {
            NutEmpty(icon: "template", title: "Henüz şablon yok", text: "Besin ve tariflerden bir şablon oluştur ya da günlükteki öğün kartından kaydet; tek dokunuşla eklersin.") { create }
        } else {
            NutMealField(meal: $meal)
            NutList(items: list) { t in
                HStack(spacing: 4) {
                    Button { addTemplate(t) } label: {
                        HStack(spacing: 12) {
                            NutThumb()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                                Text("\(t.items.count) kalem · \(fmt0(t.kcal)) kcal · P \(fmt0(t.p)) g").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 56).contentShape(Rectangle())
                    }
                    .buttonStyle(.press)
                    Button { sub = .template(id: t.id, isNew: false) } label: { Ti("pencil") }
                        .buttonStyle(.b(.ghost, .iconLarge)).bButtonFg(Color.bMutedFg).accessibilityLabel("\(t.name) şablonunu düzenle")
                    Button { deleteTemplate(t) } label: { Ti("trash") }
                        .buttonStyle(.b(.ghost, .iconLarge)).bButtonFg(Color.bMutedFg).accessibilityLabel("\(t.name) şablonunu sil")
                }
                .padding(.leading, 12).padding(.trailing, 4)
            }
            create
        }
    }

    private func newTemplate() {
        let t = NutTemplate(name: "Yeni şablon", meal: meal, items: [])
        NutLocal.shared.templates.insert(t, at: 0)
        sub = .template(id: t.id, isNew: true)
    }
    private func addTemplate(_ t: NutTemplate) {
        guard case .log(let date, _) = target else { return }
        haptic()
        let m = meal
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(t.name) eklendi")) { E in
            E += t.items.map { var x = $0; x.id = UUID().uuidString; x.meal = m; return x }
        }
        dismiss()
    }
    private func deleteTemplate(_ t: NutTemplate) {
        let store = NutLocal.shared
        guard let i = store.templates.firstIndex(where: { $0.id == t.id }) else { return }
        store.templates.remove(at: i)
        app.toast(String(localized: "\(t.name) silindi"), kind: .delete) { store.templates.insert(t, at: min(i, store.templates.count)) }
    }

    // MARK: Ekle

    private func done(_ food: FoodItem, g: Double, label lbl: String) {
        switch target {
        case .myfood:
            let exists = saved.contains { nutSameName($0.name, food.name) }
            if !exists { FoodService.save(food, ctx: ctx); Store.save(ctx) }
            app.toast(exists ? "Zaten Besinlerim’de" : "Besinlerime kaydedildi")
        case .log(let date, _):
            let m = meal
            NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(m.nutShortLabel) öğününe eklendi")) { E in
                E.append(NutEntries.entry(from: food, g: g, meal: m, label: lbl))
            }
            if food.source == .off || food.source == .fatsecret, !saved.contains(where: { nutSameName($0.name, food.name) }) {
                FoodService.save(food, ctx: ctx)
            }
        case .recipe(let r):
            r.items = r.items + [RecipeItem(name: food.name, g: g, per100: food.per100)]
            Store.save(ctx)
            app.toast("Malzeme eklendi") { if !r.items.isEmpty { r.items = Array(r.items.dropLast()) } }
        case .template(let id):
            let e = NutEntries.entry(from: food, g: g, meal: meal, label: lbl)
            NutLocal.shared.update(id) { $0.items.append(e) }
            app.toast("Kayıtlı öğüne eklendi")
        case .collect(_, let add):
            add(NutEntries.entry(from: food, g: g, meal: meal, label: lbl))
        }
        haptic()
        dismiss()
    }
}

// MARK: - Search field

struct NutSearchField: View {
    var placeholder: String
    @Binding var text: String
    /// When true, the keyboard opens once visible, then it's set to false (first open only)
    var autoFocus: Binding<Bool>? = nil
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Ti("search").foregroundStyle(Color.bMutedFg)
            TextField(tl(placeholder), text: $text).font(.geist(16)).autocorrectionDisabled().submitLabel(.search)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.bMutedFg) }.buttonStyle(.plain)
                    .accessibilityLabel("Temizle")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        // white fill, no border
        .background(scheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
        .task {
            guard let a = autoFocus, a.wrappedValue else { return }
            a.wrappedValue = false
            // let the page transition finish, then bring up the keyboard
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

/// Missing food report: only the search text is sent. If the server is down it waits in a queue and retries on the next report.
enum FoodRequests {
    private static let key = "fd.pending"
    static func send(_ q: String) async {
        let t = String(q.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard t.count >= 2 else { return }
        var pending = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !pending.contains(t) { pending.append(t) }
        var left: [String] = []
        for p in pending.suffix(30) {
            do { _ = try await SocialAPI.rpc("fd_request", ["p_q": p, "p_norm": TextNorm.norm(p)], as: SocialAPI.Empty.self) }
            catch { left.append(p) }
        }
        UserDefaults.standard.set(left, forKey: key)
    }
}

// MARK: - Recipe picker

struct NutRecipePickList: View {
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    var onPick: (FoodItem) -> Void
    private struct Row: Identifiable { var r: Recipe; var f: FoodItem; var id: String { f.id } }
    var body: some View {
        let list = recipes.compactMap { r in r.asFood.map { Row(r: r, f: $0) } }
        if list.isEmpty {
            NutEmpty(icon: "chef-hat", title: "Eklenebilir tarif yok", text: "Tarifler sekmesinde malzemeleriyle bir tarif oluştur; buradan eklersin.")
        } else {
            NutList(items: list) { x in
                let pg = x.f.portions["porsiyon"] ?? 100
                let m = x.f.per100.scaled(pg / 100)
                NutFoodRow(title: x.f.name, sub: String(localized: "1 porsiyon · \(fmt0(m.kcal)) kcal · P \(fmt1(m.p))"), thumb: 56, action: { onPick(x.f) }) {
                    Ti("chevron-right").foregroundStyle(Color.bMutedFg)
                }
            }
        }
    }
}

// MARK: - Miktar

struct NutAmount: View {
    let food: FoodItem
    var lastG: Double?
    let target: NutTarget
    @Binding var meal: Meal
    var onBack: () -> Void
    var onDone: (Double, String) -> Void
    @State private var unit = "g"
    @State private var qty = ""
    @State private var ready = false

    private var units: [(String, Double)] { [("g", 1)] + food.portions.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    private var grams: Double { (unit == "g" ? 1 : food.portions[unit] ?? 0) * nutNum(qty) }

    var body: some View {
        let g = grams, valid = nutOkG(g)
        let x = food.per100.scaled((valid ? g : 0) / 100)
        let label = unit == "g" ? "\(fmt1(g)) g \(food.name)" : "\(fmt1(nutNum(qty))) \(unit) \(food.name)"
        HStack(spacing: 12) {
            NutThumb(url: food.imageURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("100 g: \(fmt0(food.per100.kcal)) kcal · P \(fmt1(food.per100.p)) · K \(fmt1(food.per100.c)) · Y \(fmt1(food.per100.f))")
                // data source attribution (ODbL / FatSecret terms)
                if food.source == .off { Text("Kaynak: Open Food Facts (ODbL)").font(.bXs) }
                if food.source == .fatsecret {
                    Link("Powered by FatSecret", destination: URL(string: "https://www.fatsecret.com")!).font(.bXs)
                }
            }
            .font(.bSm).foregroundStyle(Color.bMutedFg).monospacedDigit()
        }
        if target.isLog { NutMealField(meal: $meal) }
        if !target.isMyFood {
            BField(label: "Birim") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(units, id: \.0) { u, ug in
                            Button {
                                let keep = valid ? g : 100
                                unit = u
                                qty = u == "g" ? fmt0(keep).replacingOccurrences(of: ".", with: "") : "1"
                            } label: {
                                HStack(spacing: 6) {
                                    Text(u)
                                    if u != "g" { Text("\(fmt1(ug)) g").opacity(0.6).monospacedDigit() }
                                }
                            }
                            .buttonStyle(.b(unit == u ? .primary : .outline))
                        }
                    }
                    .padding(.vertical, 10)
                }
                .padding(.vertical, -10)
            }
            BField(label: unit == "g" ? "Gram" : "Adet / miktar", hint: !valid && !qty.isEmpty ? String(localized: "0'dan büyük, en fazla \(fmt0(nutMaxG)) g olmalı.") : nil) {
                TextField("", text: $qty).keyboardType(.decimalPad).textFieldStyle(.b)
                    .onChange(of: qty) { _, v in let c = nutDecimal(v); if c != v { qty = c } }
            }
            NutMacroGrid(m: x)
        }
        VStack(spacing: 8) {
            Button { onDone(g, label) } label: { BLabel(target.isMyFood ? "Besinlerime kaydet" : "Ekle", icon: "plus") }
                .buttonStyle(.b(.primary, .large, full: true)).disabled(!target.isMyFood && !valid)
            Button("Geri", action: onBack).buttonStyle(.b(.ghost, full: true))
        }
        .onAppear {
            guard !ready else { return }
            ready = true
            if let lastG { unit = "g"; qty = fmt0(lastG).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "") }
            else if let first = units.dropFirst().first { unit = first.0; qty = "1" }
            else { unit = "g"; qty = "100" }
        }
    }
}

// MARK: - Barkod

/// Camera permission status and request (barcode and QR scanner)
enum CameraAccess {
    static func status() -> AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static func request() async -> AVAuthorizationStatus {
        if status() == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
        return status()
    }
}

struct NutScanner: View {
    @Environment(\.modelContext) private var ctx
    var onFound: (FoodItem) -> Void
    var onManual: (String) -> Void
    @State private var code = ""
    @State private var last = ""
    @State private var looking = false
    @State private var error: String?
    @State private var run = 0
    /// Camera permission: asked on first open (without it DataScanner shows "unavailable")
    @State private var cam = CameraAccess.status()

    var body: some View {
        let canScan = DataScannerViewController.isSupported && cam == .authorized
        ZStack {
            Color.black
            if canScan && error == nil && !looking {
                BarcodeScannerView { c in if !looking { lookup(c) } }.id(run)
            }
            Rectangle().fill(Color.bPrimary.opacity(0.8)).frame(height: 2).padding(.horizontal, 32).allowsHitTesting(false)
            if looking || error != nil || !canScan {
                VStack(spacing: 12) {
                    if looking { Text("Ürün aranıyor…") }
                    else if let error {
                        Text(tl(error))
                        Button("Tekrar tara") { self.error = nil; run += 1 }.buttonStyle(.b(.secondary))
                    } else if cam == .notDetermined { ProgressView().tint(.white) }
                    else { Text("Kameraya erişilemedi. Ayarlardan kamera izni ver ya da barkodu elle yaz.") }
                }
                .font(.bSm).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(24)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: BRadius.card, style: .continuous))
        .task { cam = await CameraAccess.request() }
        HStack(spacing: 8) {
            TextField("Barkodu elle yaz", text: $code).keyboardType(.numberPad).textFieldStyle(.b)
                .onChange(of: code) { _, v in let d = v.filter(\.isNumber); if d != v { code = d } }
                .onSubmit { if !code.isEmpty { lookup(code) } }
            Button("Bul") { lookup(code) }.buttonStyle(.b(.primary)).disabled(code.isEmpty || looking)
        }
        if error != nil, !last.isEmpty {
            Button { onManual(last) } label: { BLabel("Etiketten kaydet", icon: "tag") }.buttonStyle(.b(.outline, full: true))
        }
        Text("Önce Besinlerim'e, sonra FatSecret ve Open Food Facts'e bakılır. Bulunamazsa ürünü paketteki etiketten bir kez kaydet; sonraki okutmada hemen gelir.")
            .font(.bXs).foregroundStyle(Color.bMutedFg)
    }

    private func lookup(_ raw: String) {
        let c = raw.filter(\.isNumber); guard !c.isEmpty, !looking else { return }   // avoid a double search
        last = c; looking = true; error = nil
        Task {
            defer { looking = false }
            do { let f = try await FoodService.barcode(c, ctx: ctx); onFound(f) }
            catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Ürün bulunamadı" }
        }
    }
}

// MARK: - Saved meal draft and meal editor

/// This-time copy of a saved meal: gram and item changes aren't written to the template
struct NutMealDraft: Equatable {
    var name: String
    var items: [FoodEntry]
}

/// Meal contents: each item's grams are edited inline, items can be deleted, new foods added
struct NutMealEditor: View {
    @Binding var items: [FoodEntry]
    var onAdd: () -> Void

    var body: some View {
        let kcal = items.reduce(0) { $0 + $1.macros.kcal }, p = items.reduce(0) { $0 + $1.macros.p }
        NutSectionTitle(title: String(localized: "İçindekiler · \(fmt0(kcal)) kcal · P \(fmt0(p)) g")) {
            Button { onAdd() } label: { BLabel("Besin ekle", icon: "plus") }.buttonStyle(.b(.ghost, .small))
        }
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                if i > 0 { NutDivider() }
                HStack(spacing: 10) {
                    NutThumb(size: 36, name: e.foodName.isEmpty ? e.name : e.foodName)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.foodName.isEmpty ? e.name : e.foodName).font(.geist(14, .medium, relativeTo: .subheadline)).lineLimit(1).foregroundStyle(Color.bFg)
                        Text("\(fmt0(e.macros.kcal)) kcal · P \(fmt1(e.macros.p)) · K \(fmt1(e.macros.c)) · Y \(fmt1(e.macros.f))")
                            .font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit().lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    NutGramField(g: Binding(get: { items.first { $0.id == e.id }?.g ?? e.g },
                                            set: { v in
                        guard let j = items.firstIndex(where: { $0.id == e.id }) else { return }
                        items[j].g = v
                        // the label updates with the grams ("120 g Egg")
                        if !items[j].foodName.isEmpty { items[j].name = "\(fmt1(v)) g \(items[j].foodName)" }
                    }))
                    Button { withAnimation(.snappy) { items.removeAll { $0.id == e.id } } } label: { Ti("trash") }
                        .buttonStyle(.b(.ghost, .iconLarge)).bButtonFg(Color.bMutedFg)
                        .accessibilityLabel("\(e.name) kaldır")
                }
                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
            }
            if items.isEmpty {
                Button { onAdd() } label: {
                    Text("Besin ekle.").font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .bCard(padding: 0)
    }
}

/// Inline gram field: calories update as you type; the old value stays when invalid or empty
struct NutGramField: View {
    @Binding var g: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 2) {
            TextField("0", text: $text)
                .keyboardType(.decimalPad).focused($focused)
                .multilineTextAlignment(.trailing).monospacedDigit()
                .font(.geist(15, .semibold, relativeTo: .body)).foregroundStyle(Color.bFg)
                .frame(width: 52)
            Text("g").font(.bXs).foregroundStyle(Color.bMutedFg)
        }
        .padding(.horizontal, 8).frame(height: 36)
        .background(Color.bFg.opacity(0.07), in: RoundedRectangle(cornerRadius: BRadius.small, style: .continuous))
        .contentShape(Rectangle()).onTapGesture { focused = true }
        .onAppear { text = fmt1(g) }
        .onChange(of: g) { _, v in if !focused { text = fmt1(v) } }
        .onChange(of: text) { _, v in
            let c = nutDecimal(v); if c != v { text = c; return }
            let x = nutNum(c)
            if nutOkG(x), x != g { g = x }
        }
        .onChange(of: focused) { _, f in if !f { text = fmt1(g) } }
        .accessibilityElement(children: .combine).accessibilityLabel("Gram")
    }
}
