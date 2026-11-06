import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BalliKit

// Beslenme ekranının veri yardımcıları (PWA lib/store.jsx · nutrition, recipeTotals, recentFoods, şablonlar)

let nutMaxG: Double = 10_000
func nutOkG(_ g: Double) -> Bool { g > 0 && g <= nutMaxG }

/// "12,5" → 12.5; geçersizse 0
func nutNum(_ s: String) -> Double { trNum(s) }
/// Yalnız rakam, virgül, nokta
func nutDecimal(_ s: String) -> String { s.filter { $0.isNumber || $0 == "," || $0 == "." } }
/// 12.5 → "12,5" (tr) / "12.5" (en); binlik ayırıcı yok (giriş alanı için)
func nutInput(_ v: Double) -> String { v.isFinite ? v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(.current)) : "–" }

private var nutTR: Locale { .current }
func nutShortDate(_ key: String) -> String {
    DayKey.date(key)?.formatted(.dateTime.day().month(.abbreviated).locale(nutTR)) ?? key
}
func nutSameName(_ a: String, _ b: String) -> Bool { TextNorm.norm(a) == TextNorm.norm(b) }

/// Öğün seçenekleri: kullanıcının açtığı öğünler (+ düzenlenen kaydın öğünü)
func nutMeals(_ profile: UserProfile?, include: Meal? = nil) -> [Meal] {
    let on = profile?.meals ?? Meal.allCases
    return Meal.allCases.filter { on.contains($0) || $0 == include }
}
func nutDefaultMeal(_ profile: UserProfile?) -> Meal { Meal.default(enabled: profile?.meals ?? Meal.allCases) }

extension Meal: @retroactive Identifiable { public var id: String { rawValue } }
extension Meal { var nutShortLabel: String {
        // "Ara" (ara öğün) anahtarı aramadaki "Ara" ile çakışmasın: çeviride tam ad kullanılır
        let short = label.replacingOccurrences(of: " öğün", with: "")
        let full = tl(label)
        return full != label ? (self == .ara ? full : tl(short)) : short
    } }

// MARK: - Günlük kayıtlar + geri alma

@MainActor
enum NutEntries {
    /// Günün kayıtlarını değiştirir; mesaj verilirse "Geri al"lı toast gösterir
    static func change(_ ctx: ModelContext, date: String, app: AppState?, toast msg: String? = nil, kind: ToastItem.Kind = .ok,
                       _ f: (inout [FoodEntry]) -> Void) {
        guard let d = Store.day(ctx, date) else { return }
        let before = d.entries
        var list = before
        f(&list)
        d.entries = list
        Store.save(ctx)
        if let msg, let app {
            // Geri alma yalnız bu değişikliği tersine çevirir; aradaki başka düzenlemeler korunur (NU-06)
            let after = list
            app.toast(msg, kind: kind) {
                guard let d = Store.day(ctx, date) else { return }
                let beforeById = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let afterIds = Set(after.map(\.id))
                let added = afterIds.subtracting(beforeById.keys)
                var cur = d.entries.filter { !added.contains($0.id) }
                for i in cur.indices {
                    if let b = beforeById[cur[i].id], let a = after.first(where: { $0.id == b.id }), a != b, cur[i] == a { cur[i] = b }
                }
                for (i, b) in before.enumerated() where !afterIds.contains(b.id) && !cur.contains(where: { $0.id == b.id }) {
                    cur.insert(b, at: min(i, cur.count))
                }
                d.entries = cur; Store.save(ctx)
            }
        }
    }

    static func entry(from food: FoodItem, g: Double, meal: Meal, label: String? = nil) -> FoodEntry {
        FoodEntry(meal: meal, name: label ?? "\(fmt1(g)) g \(food.name)", foodName: food.name, g: g, per100: food.per100)
    }
}

// MARK: - Son eklenenler

struct NutRecent: Identifiable { var food: FoodItem; var lastG: Double; var id: String { food.id } }

@MainActor
func nutRecentFoods(_ ctx: ModelContext, limit: Int = 8) -> [NutRecent] {
    var d = FetchDescriptor<DayLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
    d.fetchLimit = 60
    let days = (try? ctx.fetch(d)) ?? []
    var seen = Set<String>(), out: [NutRecent] = []
    for day in days {
        for e in day.entries.reversed() {
            let n = e.foodName.isEmpty ? e.name : e.foodName
            guard !seen.contains(n), e.g > 0 else { continue }
            seen.insert(n)
            out.append(NutRecent(food: FoodItem(id: "r-\(e.id)", name: n, per100: e.per100, source: .mine), lastG: e.g))
            if out.count >= limit { return out }
        }
    }
    return out
}

// MARK: - Tarifler

struct NutRecipeTotals { var total: Macros; var perServing: Macros; var grams: Double }

extension Recipe {
    /// Kalıcı, cihazlar arası aynı kalan anahtar (not ve kimlik için)
    var nutKey: String { String(Int(createdAt.timeIntervalSince1970 * 1000)) }
    var totals: NutRecipeTotals {
        let t = items.reduce(Macros.zero) { $0 + $1.per100.scaled(max(0, $1.g) / 100) }
        let g = items.reduce(0) { $0 + max(0, $1.g) }
        let sv = Double(max(1, servings))
        return NutRecipeTotals(total: t, perServing: t.scaled(1 / sv), grams: g)
    }
    /// Tarif, "porsiyon" birimli bir besin gibi eklenir
    var asFood: FoodItem? {
        let t = totals
        guard t.grams > 0, !items.isEmpty else { return nil }
        return FoodItem(id: "rc-\(nutKey)", name: name.isEmpty ? "Adsız tarif" : name, per100: t.total.scaled(100 / t.grams),
                        portions: ["porsiyon": t.grams / Double(max(1, servings))], source: .recipe)
    }
}

// MARK: - Yerel küçük veriler: öğün şablonları, tarif notları

struct NutTemplate: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var meal: Meal?
    var items: [FoodEntry]
    var kcal: Double { items.reduce(0) { $0 + $1.macros.kcal } }
    var p: Double { items.reduce(0) { $0 + $1.macros.p } }
}

@MainActor
@Observable
final class NutLocal {
    static let shared = NutLocal()
    private let tKey = "balli.mealTemplates", nKey = "balli.recipeNotes"
    var templates: [NutTemplate] { didSet { save(templates, tKey) } }
    var notes: [String: String] { didSet { save(notes, nKey) } }

    private init() {
        let ud = UserDefaults.standard
        templates = ud.data(forKey: "balli.mealTemplates").flatMap { try? JSONDecoder().decode([NutTemplate].self, from: $0) } ?? []
        notes = ud.data(forKey: "balli.recipeNotes").flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    private func save<T: Encodable>(_ v: T, _ k: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: k) }
    }
    func template(_ id: String) -> NutTemplate? { templates.first { $0.id == id } }
    func update(_ id: String, _ f: (inout NutTemplate) -> Void) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        f(&templates[i])
    }
}

// MARK: - Trend

struct NutTrendRow: Identifiable { var k: String; var kcal: Double; var p: Double; var logged: Bool; var id: String { k } }
struct NutTrend { var rows: [NutTrendRow]; var logged: Int; var avg: Double; var pOk: Int; var pPct: Double; var weights: [Double] }

@MainActor
func nutTrend(_ ctx: ModelContext, range: Int, proteinGoal: Double) -> NutTrend {
    let today = DayKey.today
    let keys = (0..<range).map { DayKey.shift(today, days: $0 - range + 1) }
    let first = keys.first ?? today
    let all = ((try? ctx.fetch(FetchDescriptor<DayLog>())) ?? []).filter { $0.date >= first }
    let byKey = Dictionary(all.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    let rows = keys.map { k -> NutTrendRow in
        let d = byKey[k]; let e = d?.eaten ?? .zero
        return NutTrendRow(k: k, kcal: e.kcal, p: e.p, logged: !(d?.entries.isEmpty ?? true))
    }
    let logged = rows.filter(\.logged)
    let avg = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.kcal } / Double(logged.count)
    let pOk = logged.filter { $0.p >= 0.9 * proteinGoal }.count
    let start = DayKey.date(first) ?? .now
    let ms = ((try? ctx.fetch(FetchDescriptor<BodyMeasure>(sortBy: [SortDescriptor(\.date)]))) ?? []).filter { $0.date >= start }.compactMap(\.kg)
    return NutTrend(rows: rows, logged: logged.count, avg: avg, pOk: pOk, pPct: logged.isEmpty ? 0 : Double(pOk) / Double(logged.count), weights: ms)
}

// MARK: - Paylaşım dosyası (PWA ile aynı biçim: balli-share v1)

struct NutShareFile: Codable {
    struct Food: Codable { var name: String; var per100: Macros; var portions: [String: Double]?; var barcode: String? }
    struct RItem: Codable { var name: String; var g: Double; var per100: Macros }
    struct Rec: Codable { var name: String; var servings: Int?; var note: String?; var items: [RItem] }
    var app = "balli-share"
    var v = 1
    var sharedAt: String = ISO8601DateFormatter().string(from: .now)
    var foods: [Food]? = []
    var recipes: [Rec]? = []
}

struct NutShareDoc: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("balli-paylasim.json")
    }
}

@MainActor
enum NutShare {
    static func export(foods: [SavedFood], recipes: [Recipe]) -> NutShareDoc {
        var f = NutShareFile()
        f.foods = foods.map { .init(name: $0.name, per100: $0.per100, portions: $0.portions, barcode: $0.barcode) }
        f.recipes = recipes.map { r in .init(name: r.name, servings: r.servings, note: NutLocal.shared.notes[r.nutKey], items: r.items.map { .init(name: $0.name, g: $0.g, per100: $0.per100) }) }
        return NutShareDoc(data: (try? JSONEncoder().encode(f)) ?? Data())
    }

    /// İçe alır; aynı adlı olanları atlar. Dönüş: toast mesajı ve geri alma
    static func importFile(_ url: URL, ctx: ModelContext, app: AppState) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { app.toast("Dosya okunamadı.", kind: .error); return }
        guard let j = try? JSONDecoder().decode(NutShareFile.self, from: data), j.app == "balli-share" else {
            app.toast("Bu bir GYM Paper paylaşım dosyası değil.", kind: .error); return
        }
        let haveF = Set(((try? ctx.fetch(FetchDescriptor<SavedFood>())) ?? []).map { TextNorm.norm($0.name) })
        let haveR = Set(((try? ctx.fetch(FetchDescriptor<Recipe>())) ?? []).map { TextNorm.norm($0.name) })
        func cap(_ m: Macros) -> Macros { Macros(kcal: min(900, m.kcal), p: min(100, m.p), c: min(100, m.c), f: min(100, m.f)) }
        var newF: [SavedFood] = [], newR: [Recipe] = [], seenF = haveF, seenR = haveR
        for f in j.foods ?? [] {
            let n = f.name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty, !seenF.contains(TextNorm.norm(n)) else { continue }
            seenF.insert(TextNorm.norm(n))
            newF.append(SavedFood(name: String(n.prefix(120)), per100: cap(f.per100), portions: (f.portions ?? [:]).filter { $0.value > 0 }, barcode: f.barcode?.filter(\.isNumber)))
        }
        for (i, r) in (j.recipes ?? []).enumerated() {
            let n = r.name.trimmingCharacters(in: .whitespaces); guard !n.isEmpty, !seenR.contains(TextNorm.norm(n)) else { continue }
            seenR.insert(TextNorm.norm(n))
            let rec = Recipe(name: String(n.prefix(120)), servings: min(50, max(1, r.servings ?? 1)),
                             items: r.items.prefix(60).map { RecipeItem(name: $0.name, g: min(10_000, max(0, $0.g)), per100: cap($0.per100)) })
            rec.createdAt = Date(timeIntervalSinceNow: Double(i) * 0.002)
            newR.append(rec)
            if let note = r.note, !note.isEmpty { NutLocal.shared.notes[rec.nutKey] = String(note.prefix(2000)) }
        }
        guard !newF.isEmpty || !newR.isEmpty else { app.toast("Yeni bir şey yok, hepsi zaten sende"); return }
        newF.forEach { ctx.insert($0) }; newR.forEach { ctx.insert($0) }
        Store.save(ctx)
        let msg = [newF.isEmpty ? nil : String(localized: "\(newF.count) besin"), newR.isEmpty ? nil : String(localized: "\(newR.count) tarif")].compactMap { $0 }.joined(separator: ", ") + String(localized: " eklendi")
        app.toast(msg) {
            newF.forEach { ctx.delete($0) }; newR.forEach { ctx.delete($0) }; Store.save(ctx)
        }
    }
}
