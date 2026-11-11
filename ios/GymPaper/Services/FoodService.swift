import Foundation
import SwiftData
import GymPaperKit

/// Food search/barcode: My foods + built-in list (offline) → FatSecret (if configured) → Open Food Facts
@MainActor
enum FoodService {
    nonisolated static let off = OpenFoodFacts()
    /// Without a configured backend (open-source default) FatSecret is off and search uses Open Food Facts
    nonisolated static let fatsecret: FatSecretProxy? = AppConfig.backend.map {
        FatSecretProxy(endpoint: $0.url.appendingPathComponent("functions/v1/fatsecret"), anonKey: $0.anonKey)
    }

    static func mine(_ ctx: ModelContext) -> [FoodItem] {
        ((try? ctx.fetch(FetchDescriptor<SavedFood>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []).map {
            FoodItem(id: "mine-\($0.persistentModelID.hashValue)", name: $0.name, per100: $0.per100, portions: $0.portions, source: .mine, barcode: $0.barcode)
        }
    }

    /// Online search: FatSecret and OFF together; if one fails the other still answers
    static func online(_ q: String) async -> (items: [FoodItem], error: String?) {
        async let fs = fsSearch(q)
        async let of = offSearch(q)
        let a = await fs, b = await of
        switch b {
        case .success(let x): return (FoodSearch.dedupe(a + x), nil)
        case .failure(let e): return (a, a.isEmpty ? ((e as? LocalizedError)?.errorDescription ?? "Arama yapılamadı.") : nil)
        }
    }

    private nonisolated static func fsBarcode(_ d: String) async -> FoodItem? { try? await fatsecret?.barcode(d) }
    private nonisolated static func offBarcode(_ d: String) async -> Result<FoodItem, Error> {
        do { return .success(try await off.barcode(d)) } catch { return .failure(error) }
    }
    private nonisolated static func fsSearch(_ q: String) async -> [FoodItem] { (try? await fatsecret?.search(q)) ?? [] }
    private nonisolated static func offSearch(_ q: String) async -> Result<[FoodItem], Error> {
        do { return .success(try await off.search(q)) } catch { return .failure(error) }
    }

    /// Barcode: My foods first (offline), then FatSecret, then OFF
    static func barcode(_ code: String, ctx: ModelContext) async throws -> FoodItem {
        let digits = code.filter(\.isNumber)
        if let m = mine(ctx).first(where: { $0.barcode == digits }) { return m }
        // both sources are queried together; total wait on a slow network is halved
        async let fs = fsBarcode(digits)
        async let of = offBarcode(digits)
        if let f = await fs { return f }
        return try await of.get()
    }

    /// Saves a product found online to My foods (adds the barcode if the name exists)
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
