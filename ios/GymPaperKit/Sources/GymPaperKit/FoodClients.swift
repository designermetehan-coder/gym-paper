import Foundation

public enum FoodLookupError: Error, LocalizedError, Equatable {
    case offline, notFound, missingNutrition, unavailable, server
    public var errorDescription: String? {
        switch self {
        case .offline: "İnternet bağlantısı yok."
        case .notFound: "Bu barkod kayıtlı değil."
        case .missingNutrition: "Ürünün besin değerleri eksik."
        case .unavailable: "Bu kaynak şu an kullanılamıyor."
        case .server: "Arama yapılamadı. Tekrar dene."
        }
    }
}

/// Open Food Facts: free, open data (ODbL). Barcode + text search.
public struct OpenFoodFacts: Sendable {
    public var session: URLSession = .shared
    public init() {}
    static let base = "https://world.openfoodfacts.org"
    static let fields = "code,product_name,product_name_tr,brands,nutriments,serving_quantity,image_front_small_url"

    /// The new search engine first (search-a-licious; Turkish products first), the old search as fallback
    public func search(_ q: String) async throws -> [FoodItem] {
        async let tr = fastSearch(q, turkey: true)
        async let all = fastSearch(q, turkey: false)
        let a = (try? await tr) ?? [], b = (try? await all) ?? []
        let merged = FoodSearch.dedupe(a + b)
        if !merged.isEmpty { return merged }
        return try await legacySearch(q)
    }

    func fastSearch(_ q: String, turkey: Bool) async throws -> [FoodItem] {
        var c = URLComponents(string: "https://search.openfoodfacts.org/search")!
        let query = turkey ? "\(q) AND countries_tags:\"en:turkey\"" : q
        c.queryItems = [.init(name: "q", value: query), .init(name: "page_size", value: "20"), .init(name: "langs", value: "tr,en"),
                        .init(name: "fields", value: Self.fields)]
        let data = try await get(c.url!)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["hits"] as? [[String: Any]] ?? []).compactMap(Self.item)
    }

    func legacySearch(_ q: String) async throws -> [FoodItem] {
        var c = URLComponents(string: "\(Self.base)/cgi/search.pl")!
        c.queryItems = [.init(name: "search_terms", value: q), .init(name: "search_simple", value: "1"), .init(name: "action", value: "process"),
                        .init(name: "json", value: "1"), .init(name: "page_size", value: "15"), .init(name: "fields", value: Self.fields)]
        let data = try await get(c.url!)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["products"] as? [[String: Any]] ?? []).compactMap(Self.item)
    }

    public func barcode(_ code: String) async throws -> FoodItem {
        let digits = code.filter(\.isNumber); guard !digits.isEmpty else { throw FoodLookupError.notFound }
        // only 404 means "not listed"; server errors/timeouts stay "try again"
        let data = try await get(URL(string: "\(Self.base)/api/v2/product/\(digits).json?fields=\(Self.fields)")!)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (obj?["status"] as? NSNumber)?.intValue == 1, let p = obj?["product"] as? [String: Any] else { throw FoodLookupError.notFound }
        guard let item = Self.item(p) else { throw FoodLookupError.missingNutrition }
        return item
    }

    /// Converts product JSON to FoodItem; nil without energy
    public static func item(_ p: [String: Any]) -> FoodItem? {
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double? {
            if let v = n[k] as? NSNumber { return v.doubleValue }
            if let s = n[k] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let pp = num("proteins_100g"), cc = num("carbohydrates_100g"), ff = num("fat_100g")
        // without any macros the product isn't trusted (so it isn't added as "P 0")
        guard pp != nil || cc != nil || ff != nil else { return nil }
        // macros per 100 g can't exceed 100 g
        guard (pp ?? 0) <= 100, (cc ?? 0) <= 100, (ff ?? 0) <= 100, (pp ?? 0) + (cc ?? 0) + (ff ?? 0) <= 105 else { return nil }
        var kcal = num("energy-kcal_100g")
        // fix kJ written into the kcal field (~4.2× what the macros imply)
        let est = (pp ?? 0) * 4 + (cc ?? 0) * 4 + (ff ?? 0) * 9
        if let k = kcal, k > 950, est > 0, abs(k / 4.184 - est) / est < 0.25 { kcal = k / 4.184 }
        if kcal == nil, let kj = num("energy_100g"), kj > 0 { kcal = kj / 4.184 }
        if (kcal ?? 0) <= 0 { kcal = est }
        guard let kcal, kcal.isFinite, kcal > 0, kcal <= 950 else { return nil }
        let code = (p["code"] as? String) ?? ""
        let name = [(p["product_name_tr"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (p["product_name"] as? String),
                    (p["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let serving = (p["serving_quantity"] as? NSNumber)?.doubleValue ?? (p["serving_quantity"] as? String).flatMap(Double.init)
        return FoodItem(id: code.isEmpty ? "off-n-\(TextNorm.norm(name))" : "off-\(code)", name: name.isEmpty ? "Adsız ürün" : name,
                        per100: Macros(kcal: kcal, p: max(0, pp ?? 0), c: max(0, cc ?? 0), f: max(0, ff ?? 0)),
                        portions: (serving ?? 0) > 0 ? ["porsiyon": serving!] : [:], source: .off, barcode: code.isEmpty ? nil : code,
                        imageURL: p["image_front_small_url"] as? String)
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("GYMPaper/1.0 (iOS; https://gympaper.vercel.app)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw FoodLookupError.notFound }
            guard code == 200 else { throw FoodLookupError.server }
            return data
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(e.code) {
            throw FoodLookupError.offline
        } catch let e as URLError where e.code == .timedOut {
            throw FoodLookupError.server
        }
    }
}

/// FatSecret: keys live on the GYM Paper server (Supabase function `fatsecret`), not in the app.
/// Returns 503 when the server has no key; the app silently skips this layer.
public struct FatSecretProxy: Sendable {
    public var endpoint: URL
    public var anonKey: String
    public var session: URLSession = .shared
    public init(endpoint: URL, anonKey: String) { self.endpoint = endpoint; self.anonKey = anonKey }

    public func search(_ q: String) async throws -> [FoodItem] { try await call(["q": q]) }
    public func barcode(_ code: String) async throws -> FoodItem {
        guard let f = try await call(["barcode": code.filter(\.isNumber)]).first else { throw FoodLookupError.notFound }
        return f
    }

    private func call(_ params: [String: String]) async throws -> [FoodItem] {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!, timeoutInterval: 10)
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let (data, resp) = try await session.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 404: throw FoodLookupError.notFound
        case 503: throw FoodLookupError.unavailable
        default: throw FoodLookupError.server
        }
        struct R: Decodable { let foods: [FoodItem] }
        return try JSONDecoder().decode(R.self, from: data).foods.map { var f = $0; f.source = .fatsecret; return f }
    }
}
