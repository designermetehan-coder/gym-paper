import Foundation
import SwiftData
import BalliKit

/// Besin arama/barkod: Besinlerim + yerleşik liste (çevrimdışı) → FatSecret (varsa) → Open Food Facts
@MainActor
enum FoodService {
    nonisolated static let supabaseURL = "https://YOUR-PROJECT-REF.supabase.co"
    // Herkese açık (anon) anahtar; yetkiler sunucudaki kurallarla sınırlı
    nonisolated static let anonKey = "YOUR_SUPABASE_ANON_KEY"
    nonisolated static let off = OpenFoodFacts()
    nonisolated static let fatsecret = FatSecretProxy(endpoint: URL(string: "\(supabaseURL)/functions/v1/fatsecret")!, anonKey: anonKey)

    static func mine(_ ctx: ModelContext) -> [FoodItem] {
        ((try? ctx.fetch(FetchDescriptor<SavedFood>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []).map {
            FoodItem(id: "mine-\($0.persistentModelID.hashValue)", name: $0.name, per100: $0.per100, portions: $0.portions, source: .mine, barcode: $0.barcode)
        }
    }

    /// Çevrimiçi arama: FatSecret ve OFF birlikte; biri hata verirse diğeri yine gelir
    static func online(_ q: String) async -> (items: [FoodItem], error: String?) {
        async let fs = fsSearch(q)
        async let of = offSearch(q)
        let a = await fs, b = await of
        switch b {
        case .success(let x): return (FoodSearch.dedupe(a + x), nil)
        case .failure(let e): return (a, a.isEmpty ? ((e as? LocalizedError)?.errorDescription ?? "Arama yapılamadı.") : nil)
        }
    }

    private nonisolated static func fsBarcode(_ d: String) async -> FoodItem? { try? await fatsecret.barcode(d) }
    private nonisolated static func offBarcode(_ d: String) async -> Result<FoodItem, Error> {
        do { return .success(try await off.barcode(d)) } catch { return .failure(error) }
    }
    private nonisolated static func fsSearch(_ q: String) async -> [FoodItem] { (try? await fatsecret.search(q)) ?? [] }
    private nonisolated static func offSearch(_ q: String) async -> Result<[FoodItem], Error> {
        do { return .success(try await off.search(q)) } catch { return .failure(error) }
    }

    /// Barkod: önce Besinlerim (çevrimdışı), sonra FatSecret, sonra OFF
    static func barcode(_ code: String, ctx: ModelContext) async throws -> FoodItem {
        let digits = code.filter(\.isNumber)
        if let m = mine(ctx).first(where: { $0.barcode == digits }) { return m }
        // İki kaynak birlikte sorulur; yavaş ağda toplam bekleme yarıya iner (NU-46)
        async let fs = fsBarcode(digits)
        async let of = offBarcode(digits)
        if let f = await fs { return f }
        return try await of.get()
    }

    /// Çevrimiçi bulunan ürünü Besinlerim'e kaydeder (aynı ad varsa barkodu ekler)
    @discardableResult
    static func save(_ f: FoodItem, ctx: ModelContext) -> SavedFood {
        let all = (try? ctx.fetch(FetchDescriptor<SavedFood>())) ?? []
        if let same = all.first(where: { TextNorm.norm($0.name) == TextNorm.norm(f.name) }) {
            if same.barcode == nil { same.barcode = f.barcode }
            return same
        }
        let s = SavedFood(name: f.name, per100: f.per100, portions: f.portions, barcode: f.barcode)
        ctx.insert(s)
        return s
    }
}
