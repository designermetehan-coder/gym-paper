import SwiftUI
import SwiftData
import GymPaperKit

// Nutrition sheets: edit entry, save/edit template, edit food, recipe, recipe form, type it in
// PWA: EntrySheet, SaveTemplateSheet, TemplateForm, FoodEditSheet, RecipeSheet, RecipeForm, CheatSheet

/// Multiline input (textarea)
struct NutTextArea: View {
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 80
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(tl(placeholder)).font(.geist(16)).foregroundStyle(Color.bMutedFg).padding(.horizontal, 12).padding(.vertical, 8).allowsHitTesting(false)
            }
            TextEditor(text: $text).font(.geist(16)).scrollContentBackground(.hidden)
                .padding(.horizontal, 7).padding(.vertical, 0)
        }
        .frame(minHeight: minHeight)
        .background(scheme == .dark ? Color.white.opacity(0.045) : Color.clear, in: RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous))
        .overlay { if scheme == .light { RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).strokeBorder(Color.bInput) } }
    }
}

/// Four macro inputs (kcal · Protein · Carbs · Fat)
struct NutMacroInputs: View {
    @Binding var kcal: String
    @Binding var p: String
    @Binding var c: String
    @Binding var f: String
    var body: some View {
        HStack(spacing: 8) {
            cell("kcal", $kcal); cell("Protein", $p); cell("Karb.", $c); cell("Yağ", $f)
        }
    }
    private func cell(_ l: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tl(l)).font(.bXs).foregroundStyle(Color.bMutedFg)
            TextField("", text: b).keyboardType(.decimalPad).textFieldStyle(.b).accessibilityLabel(tl(l))
                .onChange(of: b.wrappedValue) { _, v in let x = nutDecimal(v); if x != v { b.wrappedValue = x } }
        }
    }
}

// MARK: - Edit entry

struct NutEntrySheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query private var days: [DayLog]
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var saved: [SavedFood]
    let date: String
    let id: String
    /// This day only
    init(date: String, id: String) {
        self.date = date; self.id = id
        _days = Query(filter: #Predicate<DayLog> { $0.date == date })
    }
    @State private var g = ""
    @State private var meal: Meal = .ara
    @State private var loaded: FoodEntry?

    var body: some View {
        let live = days.day(date)?.entries.first { $0.id == id }
        let e = live ?? loaded
        let gv = nutNum(g), gOk = nutOkG(gv)
        let x = e.map { $0.per100.scaled((gOk ? gv : 0) / 100) } ?? .zero
        let name = e.map { $0.foodName.isEmpty ? $0.name : $0.foodName } ?? ""
        BSheet(title: name) {
            NutMealField(meal: $meal)
            BField(label: "Gram", hint: !gOk ? String(localized: "0'dan büyük, en fazla \(fmt0(nutMaxG)) g olmalı.") : nil) {
                TextField("", text: $g).keyboardType(.decimalPad).textFieldStyle(.b)
                    .onChange(of: g) { _, v in let c = nutDecimal(v); if c != v { g = c } }
            }
            NutMacroGrid(m: x)
            if let e, !saved.contains(where: { nutSameName($0.name, name) }) {
                Button {
                    if !saved.contains(where: { nutSameName($0.name, name) }) { ctx.insert(SavedFood(name: name, per100: e.per100)); Store.save(ctx) }
                    app.toast("Besinlerime kaydedildi")
                } label: { BLabel("Besinlerime kaydet", icon: "bookmark") }
                .buttonStyle(.b(.outline, full: true))
            }
        } footer: {
            Button("Kaydet") { save(e) }.buttonStyle(.b(.primary, .large, full: true)).disabled(!gOk || e == nil)
            Button { remove(e) } label: { BLabel("Sil", icon: "trash") }.buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard loaded == nil, let live else { if live == nil { dismiss() }; return }
            loaded = live; meal = live.meal; g = nutInput((live.g * 10).rounded() / 10)
        }
    }

    private func save(_ e: FoodEntry?) {
        guard let e else { return }
        let gv = nutNum(g), m = meal
        NutEntries.change(ctx, date: date, app: nil) { E in
            guard let i = E.firstIndex(where: { $0.id == id }) else { return }
            E[i].meal = m
            if gv != (e.g * 10).rounded() / 10 { E[i].g = gv; E[i].name = "\(fmt1(gv)) g \(e.foodName.isEmpty ? e.name : e.foodName)" }
        }
        dismiss()
    }
    private func remove(_ e: FoodEntry?) {
        guard let e else { return }
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(e.foodName.isEmpty ? e.name : e.foodName) silindi"), kind: .delete) { E in
            E.removeAll { $0.id == id }
        }
        dismiss()
    }
}

// MARK: - Save meal (saved meal = template)

struct NutSaveTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let meal: Meal
    let items: [FoodEntry]
    @State private var name = ""

    var body: some View {
        let kcal = items.reduce(0) { $0 + $1.macros.kcal }
        let ok = !name.trimmingCharacters(in: .whitespaces).isEmpty
        BSheet(title: "Öğünü kaydet", description: String(localized: "\(items.count) besin · \(fmt0(kcal)) kcal")) {
            BField(label: "Öğün adı") { TextField("", text: $name).textFieldStyle(.b).onSubmit(save) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { e in Text("· \(e.name)").lineLimit(1) }
            }
            .font(.bSm).foregroundStyle(Color.bMutedFg)
        } footer: {
            Button { save() } label: { BLabel("Kaydet", icon: "template") }.buttonStyle(.b(.primary, .large, full: true)).disabled(!ok)
        }
        .presentationDetents([.medium, .large])
        .onAppear { if name.isEmpty { name = String(localized: "\(meal.nutShortLabel) · \(items.count) besin") } }
    }
    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty else { return }
        NutLocal.shared.templates.insert(NutTemplate(name: n, meal: meal, items: items.map { var x = $0; x.id = UUID().uuidString; x.group = nil; x.groupName = nil; return x }), at: 0)
        haptic(); app.toast("Öğün kaydedildi"); dismiss()
    }
}

// MARK: - Edit template

struct NutTemplateForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let id: String
    let isNew: Bool
    @State private var sub: NutSheet?
    @State private var deleted = false

    var body: some View {
        let store = NutLocal.shared
        let t = store.template(id)
        let items = t?.items ?? []
        let kcal = items.reduce(0) { $0 + $1.macros.kcal }, p = items.reduce(0) { $0 + $1.macros.p }
        BSheet(title: isNew ? "Yeni kayıtlı öğün" : "Kayıtlı öğünü düzenle", description: String(localized: "\(items.count) kalem · \(fmt0(kcal)) kcal · P \(fmt0(p)) g")) {
            if t != nil {
                BField(label: "Öğün adı") {
                    TextField("", text: Binding(get: { store.template(id)?.name ?? "" }, set: { v in store.update(id) { $0.name = String(v.prefix(60)) } }))
                        .textFieldStyle(.b)
                }
                NutMealField(meal: Binding(get: { store.template(id)?.meal ?? .ara }, set: { v in store.update(id) { $0.meal = v } }))
                // grams are edited inline; items can be added/removed
                NutMealEditor(items: Binding(get: { store.template(id)?.items ?? [] }, set: { v in store.update(id) { $0.items = v } })) {
                    sub = .add(.template(id))
                }
            }
        } footer: {
            Button { dismiss() } label: { BLabel("Bitti", icon: "check") }.buttonStyle(.b(.primary, .large, full: true))
            if !isNew {
                Button("Kayıtlı öğünü sil") {
                    guard let t, let i = store.templates.firstIndex(where: { $0.id == id }) else { return }
                    deleted = true
                    store.templates.remove(at: i)
                    app.toast(String(localized: "\(t.name) silindi"), kind: .delete) { store.templates.insert(t, at: min(i, store.templates.count)) }
                    dismiss()
                }
                .buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
            }
        }
        .presentationDetents([.large])
        .sheet(item: $sub) { s in NutSheetHost(sheet: s, date: .constant(DayKey.today), open: { sub = $0 }) }
        .onDisappear {
            guard !deleted, let t = store.template(id) else { return }
            if isNew && t.items.isEmpty { store.templates.removeAll { $0.id == id } }
            else if t.name.trimmingCharacters(in: .whitespaces).isEmpty { store.update(id) { $0.name = String(localized: "Kayıtlı öğün") } }
        }
    }
}

// MARK: - Edit food / new food

struct NutFoodEditSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    let food: SavedFood?
    @Query private var allFoods: [SavedFood]
    @State private var name = ""
    @State private var kcal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var portions = ""
    @State private var loaded = false
    @State private var photo: UIImage?
    @State private var photoChanged = false

    var body: some View {
        BSheet(title: food == nil ? "Yeni besin" : "Besini düzenle") {
            BField(label: "Fotoğraf", hint: "İsteğe bağlı; listede besinin yanında görünür.") {
                WkPhotoSlot(title: "", image: $photo) { photoChanged = true }.frame(maxWidth: 160)
            }
            BField(label: "Ad") { TextField("ör. Annemin mercimek köftesi", text: $name).textFieldStyle(.b) }
            BField(label: "100 g başına değerler") { NutMacroInputs(kcal: $kcal, p: $p, c: $c, f: $f) }
            BField(label: "Porsiyonlar", hint: "Her satıra birim = gram. Örn: adet = 55, dilim = 30") {
                NutTextArea(placeholder: "adet = 55\nporsiyon = 200", text: $portions)
            }
        } footer: {
            if let w = valueWarning {
                Text(w).font(.bXs).foregroundStyle(Color.bDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Kaydet") { save() }.buttonStyle(.b(.primary, .large, full: true))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || valueWarning != nil)
            if let food {
                Button("Besinlerimden sil") {
                    let copy = (food.name, food.per100, food.portions, food.barcode, food.createdAt, food.imageData)
                    ctx.delete(food); Store.save(ctx)
                    FoodImages.put(copy.0, nil)
                    app.toast(String(localized: "\(copy.0) silindi"), kind: .delete) {
                        let s = SavedFood(name: copy.0, per100: copy.1, portions: copy.2, barcode: copy.3); s.createdAt = copy.4
                        s.imageData = copy.5
                        ctx.insert(s); Store.save(ctx)
                        if let d = copy.5 { FoodImages.put(copy.0, UIImage(data: d)) }   // bring the photo back too
                    }
                    dismiss()
                }
                .buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            guard let food else { return }
            name = food.name
            photo = food.imageData.flatMap(UIImage.init(data:))
            kcal = nutInput(food.per100.kcal); p = nutInput(food.per100.p); c = nutInput(food.per100.c); f = nutInput(food.per100.f)
            portions = food.portions.sorted { $0.key < $1.key }.map { "\($0.key) = \(nutInput($0.value))" }.joined(separator: "\n")
        }
    }

    /// Label form rules: at most 900 kcal per 100 g; macros can't add up to more than 100 g
    private var valueWarning: String? {
        let k = nutNum(kcal), sum = nutNum(p) + nutNum(c) + nutNum(f)
        if k > 900 { return String(localized: "100 g'da en çok 900 kcal olabilir.") }
        if sum > 100 { return String(localized: "Protein + karbonhidrat + yağ 100 g'ı geçemez.") }
        if k == 0 && sum == 0 { return String(localized: "Kalori ya da makro gir.") }
        // no second food with the same name; search and barcode couldn't tell which to pick
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, allFoods.contains(where: { $0.persistentModelID != food?.persistentModelID && nutSameName($0.name, n) }) {
            return String(localized: "Bu adla bir besin zaten var.")
        }
        return nil
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty, valueWarning == nil else { return }
        var por: [String: Double] = [:]
        for line in portions.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, nutNum(parts[1]) > 0 { por[parts[0]] = nutNum(parts[1]) }
        }
        var m = Macros(kcal: max(0, nutNum(kcal)), p: max(0, nutNum(p)), c: max(0, nutNum(c)), f: max(0, nutNum(f)))
        if m.kcal == 0 { m.kcal = (m.p * 4 + m.c * 4 + m.f * 9).rounded() }   // empty calories come from macros
        let target: SavedFood
        if let food {
            if food.name != n, food.imageData != nil { FoodImages.put(food.name, nil) }
            food.name = n; food.per100 = m; food.portions = por; target = food
        } else { target = SavedFood(name: n, per100: m, portions: por); ctx.insert(target) }
        if photoChanged { FoodImages.shared.set(target, image: photo) }
        else if let d = target.imageData { FoodImages.put(n, UIImage(data: d)) }
        Store.save(ctx)
        dismiss()
    }
}

// MARK: - Tarif

struct NutRecipeSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    let recipe: Recipe
    @State private var n: Double = 1
    @State private var meal: Meal = .ara
    @State private var sub: NutSheet?
    @State private var ready = false

    var body: some View {
        let r = recipe
        let t = r.totals
        let canAdd = t.grams > 0 && !r.items.isEmpty
        let portionG = t.grams / Double(max(1, r.servings))
        let note = NutLocal.shared.notes[r.nutKey] ?? ""
        BSheet(title: r.name.isEmpty ? "Adsız tarif" : r.name, description: String(localized: "\(r.servings) porsiyon · porsiyon \(fmt0(portionG)) g")) {
            NutMacroGrid(m: t.perServing, whole: true)
            NutSectionTitle(title: "Malzemeler") {
                Button { sub = .recipeForm(r, isNew: false) } label: { BLabel("Düzenle", icon: "pencil") }.buttonStyle(.b(.ghost, .small))
            }
            VStack(spacing: 0) {
                ForEach(Array(r.items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { NutDivider() }
                    HStack(alignment: .top) {
                        Text(it.name).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(fmt1(it.g)) g").foregroundStyle(Color.bMutedFg).monospacedDigit()
                    }
                    .font(.bSm).padding(.horizontal, 16).padding(.vertical, 8)
                }
                if r.items.isEmpty {
                    Text("Malzeme eklenmemiş.").font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .bCard(padding: 0)
            if !r.items.isEmpty && !canAdd {
                Text("Malzemelerin gramajını gir; toplam 0 g olan tarif eklenemez.").font(.bSm).foregroundStyle(Color.bDestructive)
            }
            if !note.isEmpty { Text(note).font(.bSm).foregroundStyle(Color.bMutedFg) }
            NutSectionTitle("Bugüne ekle")
            NutMealField(meal: $meal)
            BField(label: "Porsiyon") { BStepper(value: $n, step: 0.5, min: 0.5) }
        } footer: {
            Button { add(portionG: portionG) } label: { BLabel(String(localized: "Bugüne ekle · \(fmt0(t.perServing.kcal * n)) kcal"), icon: "plus") }
                .buttonStyle(.b(.primary, .large, full: true)).disabled(!canAdd || !nutOkG(portionG * n))
        }
        .presentationDetents([.large])
        .sheet(item: $sub, onDismiss: {
            // close this page too if the recipe was deleted from the edit screen
            if recipe.isDeleted || recipe.modelContext == nil { dismiss() }
        }) { s in NutSheetHost(sheet: s, date: .constant(DayKey.today), open: { sub = $0 }) }
        .onAppear { if !ready { ready = true; meal = nutDefaultMeal(profiles.first) } }
    }

    private func add(portionG: Double) {
        guard !recipe.isDeleted, recipe.modelContext != nil, nutOkG(portionG * n), let food = recipe.asFood else { return }
        let m = meal, g = portionG * n, lbl = String(localized: "\(fmt1(n)) porsiyon \(food.name)")
        NutEntries.change(ctx, date: DayKey.today, app: app, toast: "Bugüne eklendi") { E in
            E.append(NutEntries.entry(from: food, g: g, meal: m, label: lbl))
        }
        haptic(); dismiss()
    }
}

struct NutRecipeForm: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Bindable var recipe: Recipe
    let isNew: Bool
    @State private var confirm = false
    @State private var sub: NutSheet?
    @State private var deleted = false

    var body: some View {
        let t = recipe.totals
        let key = recipe.nutKey
        BSheet(title: isNew ? "Yeni tarif" : "Tarifi düzenle") {
            BField(label: "Tarif adı") { TextField("ör. Sebzeli fırın kıyma", text: $recipe.name).textFieldStyle(.b) }
            BField(label: "Kaç porsiyon çıkıyor?") {
                BStepper(value: Binding(get: { Double(recipe.servings) }, set: { recipe.servings = max(1, Int($0)) }), step: 1, min: 1, format: { fmt0($0) })
            }
            NutSectionTitle(title: "Malzemeler") {
                Button { sub = .add(.recipe(recipe)) } label: { BLabel("Malzeme", icon: "plus") }.buttonStyle(.b(.ghost, .small))
            }
            VStack(spacing: 0) {
                ForEach(Array(recipe.items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { NutDivider() }
                    // row id depends on the ingredient count: deleting must not shift old grams to another row
                    NutIngredientRow(recipe: recipe, index: i, item: it).id("\(recipe.items.count)-\(i)-\(it.name)")
                }
                if recipe.items.isEmpty {
                    Text("Malzeme ekle; makrolar otomatik hesaplanır.").font(.bSm).foregroundStyle(Color.bMutedFg).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .bCard(padding: 0)
            Text("Toplam \(fmt1(t.grams)) g · \(fmt0(t.total.kcal)) kcal · porsiyon başı \(fmt0(t.perServing.kcal)) kcal, P \(fmt0(t.perServing.p)) g")
                .font(.bSm).foregroundStyle(Color.bMutedFg).monospacedDigit()
            BField(label: "Yapılış / not") {
                NutTextArea(placeholder: "", text: Binding(get: { NutLocal.shared.notes[key] ?? "" }, set: { NutLocal.shared.notes[key] = String($0.prefix(2000)) }))
            }
        } footer: {
            Button { dismiss() } label: { BLabel("Bitti", icon: "check") }.buttonStyle(.b(.primary, .large, full: true))
            if !isNew {
                if confirm {
                    Button("Evet, tarifi sil") { delete() }.buttonStyle(.b(.destructive, full: true))
                } else {
                    Button("Tarifi sil") { confirm = true }.buttonStyle(.b(.ghost, full: true)).bButtonFg(Color.bDestructive)
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $sub) { s in NutSheetHost(sheet: s, date: .constant(DayKey.today), open: { sub = $0 }) }
        .onDisappear {
            if !deleted && isNew && recipe.name.trimmingCharacters(in: .whitespaces).isEmpty && recipe.items.isEmpty { ctx.delete(recipe) }
            Store.save(ctx)
        }
    }

    private func delete() {
        let copy = (recipe.name, recipe.servings, recipe.items, recipe.createdAt)
        deleted = true
        ctx.delete(recipe); Store.save(ctx)
        app.toast(String(localized: "\(copy.0.isEmpty ? tl("Tarif") : copy.0) silindi"), kind: .delete) {
            let r = Recipe(name: copy.0, servings: copy.1, items: copy.2); r.createdAt = copy.3
            ctx.insert(r); Store.save(ctx)
        }
        dismiss()
    }
}

/// Ingredient row: raw text is kept locally (so "12," doesn't jump while typing)
struct NutIngredientRow: View {
    @Bindable var recipe: Recipe
    let index: Int
    let item: RecipeItem
    @State private var v = ""
    @State private var ready = false
    var body: some View {
        HStack(spacing: 8) {
            Text(item.name).font(.bSm).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                TextField("", text: $v).keyboardType(.decimalPad).multilineTextAlignment(.trailing).textFieldStyle(.b)
                    .padding(.trailing, 0)
                    .onChange(of: v) { _, x in
                        let c = nutDecimal(x); if c != x { v = c; return }
                        guard index < recipe.items.count else { return }
                        var list = recipe.items; list[index].g = min(nutMaxG, max(0, nutNum(c))); recipe.items = list
                    }
                Text("g").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.trailing, 10).allowsHitTesting(false)
            }
            .frame(width: 96)
            .accessibilityLabel("\(item.name) gram")
            Button {
                guard index < recipe.items.count else { return }
                var list = recipe.items; list.remove(at: index); recipe.items = list
            } label: { Ti("trash") }
            .buttonStyle(.b(.ghost, .iconLarge)).accessibilityLabel("Malzemeyi sil")
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
        .onAppear { if !ready { ready = true; v = item.g > 0 ? nutInput(item.g) : "" } }
    }
}

// MARK: - Yazarak gir

struct CheatSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var saved: [SavedFood]
    let date: String

    struct Row: Identifiable {
        let id = UUID()
        var raw: String
        var line: ParsedLine
        var food: FoodItem?
        var cands: [FoodItem]
        var g: Double
        var gs: String?
        var miss = false
        var err: String?
    }
    @State private var text = ""
    @State private var rows: [Row]?
    @State private var busy: UUID?
    @State private var meal: Meal = .ara
    @State private var ready = false

    var body: some View {
        let ok = (rows ?? []).filter { $0.food != nil && nutOkG($0.g) }
        let tot = ok.reduce(Macros.zero) { $0 + $1.food!.per100.scaled($1.g / 100) }
        BSheet(title: "Yazarak gir", description: "Her satıra bir besin yaz. Örn. 2 yumurta, 1,5 dilim ekmek.") {
            NutTextArea(placeholder: "2 dilim pizza\n1 kutu kola\nyarım porsiyon patates kızartması", text: $text, minHeight: 96)
                .onChange(of: text) { rows = nil }
            NutMealField(meal: $meal)
            if rows == nil {
                Button("Hesapla") { calc() }.buttonStyle(.b(.primary, full: true))
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let rows {
                NutMacroGrid(m: tot, whole: true)
                VStack(spacing: 8) {
                    ForEach(rows) { r in rowCard(r) }
                }
                Text("Değerler ortalama porsiyonlara göre tahmindir; besini ya da gramı değiştirerek düzeltebilirsin. Sık yediğin bir şeyse sonra Besinlerim'e kaydedebilirsin.")
                    .font(.bXs).foregroundStyle(Color.bMutedFg)
            }
        } footer: {
            if rows != nil {
                Button("\(fmt0(tot.kcal)) kcal kaydet") { save(ok, tot) }.buttonStyle(.b(.primary, .large, full: true)).disabled(ok.isEmpty)
            }
        }
        .presentationDetents([.large])
        .onAppear { if !ready { ready = true; meal = nutDefaultMeal(profiles.first) } }
    }

    @ViewBuilder private func rowCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(r.raw).font(.geist(14, .medium, relativeTo: .subheadline)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let f = r.food, nutOkG(r.g) { Text("\(fmt0(f.per100.kcal * r.g / 100)) kcal").font(.bXs).foregroundStyle(Color.bMutedFg).monospacedDigit() }
            }
            // an invalid amount must not be dropped silently
            if r.food != nil && !nutOkG(r.g) {
                Text("Miktar 0'dan büyük, en fazla \(fmt0(nutMaxG)) g olmalı; bu satır kaydedilmez.").font(.bXs).foregroundStyle(Color.bDestructive)
            } else if let f = r.food, !TextParser.isExact(r.line, food: f) {
                Text("Miktar tahmini; gramı kontrol et.").font(.bXs).foregroundStyle(Color.bMutedFg)
            }
            if let f = r.food {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(r.cands) { c in
                            Button(c.name) { setRow(r.id) { $0.food = c; $0.g = TextParser.grams($0.line, food: c); $0.gs = nil } }
                        }
                    } label: {
                        HStack {
                            Text(f.name).lineLimit(1).foregroundStyle(Color.bFg)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Color.bMutedFg)
                        }
                        .font(.geist(16)).padding(.horizontal, 12).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: BRadius.inner, style: .continuous).strokeBorder(Color.bInput))
                    }
                    .accessibilityLabel("Eşleşen besin")
                    ZStack(alignment: .trailing) {
                        TextField("", text: Binding(get: { r.gs ?? nutInput((r.g * 10).rounded() / 10) },
                                                    set: { v in let c = nutDecimal(v); setRow(r.id) { $0.gs = c; $0.g = nutNum(c) } }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).textFieldStyle(.b)
                        Text("g").font(.bXs).foregroundStyle(Color.bMutedFg).padding(.trailing, 10).allowsHitTesting(false)
                    }
                    .frame(width: 96).accessibilityLabel("Gram")
                }
            } else {
                HStack(spacing: 8) {
                    Text(r.err.map(tl) ?? (r.miss ? String(localized: "İnternette de bulunamadı.") : String(localized: "Listede eşleşme yok.")))
                        .font(.bXs).foregroundStyle(r.err != nil ? Color.bDestructive : Color.bMutedFg)
                    Spacer(minLength: 0)
                    if !r.miss {
                        Button { Task { await findOnline(r) } } label: {
                            HStack(spacing: 6) {
                                if busy == r.id { ProgressView().controlSize(.mini) } else { Ti("world") }
                                Text(r.err != nil ? "Tekrar dene" : "İnternette ara")
                            }
                        }
                        .buttonStyle(.b(.outline, .small)).disabled(busy == r.id)
                    }
                }
            }
        }
        .bCard(padding: 12)
    }

    private func setRow(_ id: UUID, _ f: (inout Row) -> Void) {
        guard var list = rows, let i = list.firstIndex(where: { $0.id == id }) else { return }
        f(&list[i]); rows = list
    }

    private func calc() {
        let mine = saved.map { FoodItem(id: "mine-\($0.persistentModelID.hashValue)", name: $0.name, per100: $0.per100, portions: $0.portions, source: .mine) }
        rows = TextParser.split(text).map { raw in
            let p = TextParser.parseLine(raw)
            let cands = Array(FoodSearch.local(p.name, mine: mine).prefix(6))
            let f = cands.first
            return Row(raw: p.raw, line: p, food: f, cands: cands, g: f.map { TextParser.grams(p, food: $0) } ?? 0)
        }
    }

    private func findOnline(_ r: Row) async {
        busy = r.id
        defer { busy = nil }
        let res = await FoodService.online(r.line.name.isEmpty ? r.raw : r.line.name)
        if let first = res.items.first {
            setRow(r.id) { $0.food = first; $0.cands = Array(res.items.prefix(6)); $0.g = TextParser.grams($0.line, food: first); $0.gs = nil; $0.err = nil }
        } else if let e = res.error {
            setRow(r.id) { $0.err = e }
        } else {
            setRow(r.id) { $0.miss = true; $0.err = nil }
        }
    }

    private func save(_ ok: [Row], _ tot: Macros) {
        let m = meal
        NutEntries.change(ctx, date: date, app: app, toast: String(localized: "\(fmt0(tot.kcal)) kcal eklendi")) { E in
            E += ok.compactMap { r in r.food.map { NutEntries.entry(from: $0, g: r.g, meal: m, label: r.raw) } }
        }
        haptic(); dismiss()
    }
}
