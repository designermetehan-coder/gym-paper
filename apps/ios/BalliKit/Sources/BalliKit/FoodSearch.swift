import Foundation

// Besin verisi 3 katman: (1) uygulama içi Türk besin listesi + Besinlerim, (2) Open Food Facts (barkod/çevrimiçi),
// (3) FatSecret (Ballı sunucusu üzerinden; anahtar tanımlanınca açılır).

public struct FoodItem: Codable, Hashable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case builtin, mine, off, fatsecret, recipe }
    public var id: String
    public var name: String
    public var per100: Macros
    public var portions: [String: Double]
    public var tags: String
    public var source: Source
    public var barcode: String?
    public var imageURL: String?
    public init(id: String, name: String, per100: Macros, portions: [String: Double] = [:], tags: String = "", source: Source, barcode: String? = nil, imageURL: String? = nil) {
        self.id = id; self.name = name; self.per100 = per100; self.portions = portions; self.tags = tags; self.source = source; self.barcode = barcode; self.imageURL = imageURL
    }
    enum CodingKeys: String, CodingKey { case id, name, per100, portions, tags, source, barcode, imageURL }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        per100 = try c.decode(Macros.self, forKey: .per100)
        portions = (try? c.decode([String: Double].self, forKey: .portions)) ?? [:]
        tags = (try? c.decode(String.self, forKey: .tags)) ?? ""
        source = (try? c.decode(Source.self, forKey: .source)) ?? .builtin
        barcode = try? c.decode(String.self, forKey: .barcode)
        imageURL = try? c.decode(String.self, forKey: .imageURL)
    }
    public var sourceLabel: String {
        switch source { case .builtin: "Ballı"; case .mine: "Besinlerim"; case .off: "Open Food Facts"; case .fatsecret: "FatSecret"; case .recipe: "Tarif" }
    }
}

public enum TextNorm {
    /// Türkçe harfleri sadeleştirir, küçük harfe çevirir, noktalama atar ("Çiğ Köfte" → "cig kofte")
    private static let tr = Locale(identifier: "tr_TR")   // her çağrıda yeni Locale yok (PF-14)
    public static func norm(_ s: String) -> String {
        let lower = s.lowercased(with: tr)
        var out = ""
        for ch in lower {
            switch ch {
            case "ı", "i", "î": out.append("i")
            case "ş": out.append("s"); case "ğ": out.append("g"); case "ü", "û": out.append("u")
            case "ö": out.append("o"); case "ç": out.append("c"); case "â": out.append("a")
            default:
                if ch.isLetter && ch.isASCII || ch.isNumber && ch.isASCII { out.append(ch) }
                else if ch == "\u{307}" { continue }
                else if ch.isLetter || ch.isNumber {
                    // Diğer aksanlı harfler sadeleşir ("crème" → "creme"); Latin dışı harfler korunur ki adlar aynı anahtara düşmesin (NU-50, PR-16)
                    let f = String(ch).folding(options: .diacriticInsensitive, locale: nil)
                    if f.unicodeScalars.allSatisfy({ $0.isASCII }) && !f.isEmpty { out.append(contentsOf: f) } else { out.append(ch) }
                } else { out.append(" ") }
            }
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}

public enum LocalFoods {
    public static let all: [FoodItem] = {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([FoodItem].self, from: data) else { return [] }
        return list.map { var f = $0; f.source = .builtin; return f }
    }()
}

public enum FoodSearch {
    /// Arama dizini (normalize ad + kelimeler); yerleşik liste için bir kez hesaplanır
    struct Doc { let item: FoodItem; let name: String; let nameWords: [String]; let words: [String] }
    static func doc(_ f: FoodItem) -> Doc {
        let name = TextNorm.norm(f.name)
        let nw = name.split(separator: " ").map(String.init)
        let tw = TextNorm.norm(f.tags).split(separator: " ").map(String.init)
        return Doc(item: f, name: name, nameWords: nw, words: nw + tw)
    }
    static let builtinIndex: [Doc] = LocalFoods.all.map(doc)

    /// Tek harf hata payı (yer değiştirme/eksik/fazla)
    static func near(_ a: Substring, _ b: Substring) -> Bool {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return false }
        var i = 0, j = 0, diff = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            diff += 1; if diff > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        return diff + (x.count - i) + (y.count - j) <= 1
    }
    /// Sorgu kelimesi bir kelimeyle eşleşiyor mu: 1 tam/ön ek, 0.6 yazım hatası, 0 yok
    static func wordScore(_ q: String, _ words: [String]) -> Double {
        var best = 0.0
        for w in words {
            if w == q { return 1.1 }
            if w.hasPrefix(q) { best = max(best, 1) }
            else if q.count >= 4, w.count >= q.count - 1 {
                // yazım hatası: kelimenin aynı uzunluktaki başıyla karşılaştır ("tavk" → "tavuk")
                if near(Substring(q), w.prefix(q.count)) || near(Substring(q), w.prefix(q.count + 1)) || near(Substring(q), w.prefix(max(1, q.count - 1))) { best = max(best, 0.6) }
            } else if q.count >= 3, w.contains(q) { best = max(best, 0.5) }
        }
        return best
    }

    /// Genel sorgularda en olası besin önce gelsin ("ekmek" → Beyaz ekmek, "Ekmek kadayıfı" değil — NU-02)
    static let preferred: [String: String] = [
        "ekmek": "Beyaz ekmek", "pilav": "Pirinç pilavı", "kofte": "Köfte (ızgara)", "peynir": "Beyaz peynir (tam yağlı)",
        "yogurt": "Yoğurt (tam yağlı)", "sut": "Süt (yarım yağlı)", "yumurta": "Haşlanmış yumurta", "tavuk": "Tavuk göğsü (ızgara)",
        "makarna": "Makarna (haşlanmış)", "corba": "Mercimek çorbası", "salata": "Çoban salata", "pirinc": "Pirinç (haşlanmış)",
        "kahve": "Türk kahvesi (sade)", "cay": "Çay (şekersiz)", "elma": "Elma", "doner": "Döner (et, porsiyon)",
        // Genel kelimeler tür ekli yemeklere gitmesin ("su" → Su böreği değil — NU-32)
        "su": "Su", "tuz": "Tuz", "seker": "Toz şeker", "kiyma": "Dana kıyma (%20 yağ)", "cikolata": "Sütlü çikolata",
    ]

    static func score(_ d: Doc, _ qq: String, _ qw: [String]) -> Double {
        guard !qq.isEmpty else { return 0 }
        if d.name == qq { return 200 }
        if let pref = preferred[qq], d.item.name == pref { return 190 }
        var total = 0.0, hits = 0
        for (k, w) in qw.enumerated() {
            let s = max(wordScore(w, d.nameWords) * 1.0, wordScore(w, d.words) * 0.8)
            if s > 0 { hits += 1; total += s * (k == 0 ? 1.3 : 1) }
        }
        // kelimelerin çoğu eşleşmeli
        guard hits > 0, Double(hits) >= Double(qw.count) * 0.67 else { return 0 }
        var sc = 40 + total / Double(qw.count) * 40
        if d.name.hasPrefix(qq) { sc += 40 }
        if let f = d.nameWords.first, f.hasPrefix(qw[0]) { sc += 15 }
        sc -= min(12, Double(d.name.count) / 6)          // kısa ve genel adlar önce
        if d.name.contains("(") == false && d.nameWords.count <= 2 { sc += 3 }
        return sc
    }

    static func score(_ f: FoodItem, _ q: String) -> Double {
        let qq = TextNorm.norm(q)
        return score(doc(f), qq, qq.split(separator: " ").map(String.init))
    }

    /// Besinlerim önce, sonra yerleşik liste (yazım hatası toleranslı)
    public static func local(_ q: String, mine: [FoodItem] = [], limit: Int = 30) -> [FoodItem] {
        let qq = TextNorm.norm(q)
        let qw = qq.split(separator: " ").map(String.init)
        guard !qw.isEmpty else { return [] }
        let docs = mine.map(doc) + builtinIndex
        return docs
            .map { ($0.item, score($0, qq, qw) + ($0.item.source == .mine ? 25 : 0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }
    /// Aynı adlı sonuçları tekilleştirir (ilk gelen kalır)
    public static func dedupe(_ items: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>(); return items.filter { seen.insert(TextNorm.norm($0.name)).inserted }
    }
}

// MARK: - "Yazarak gir" ayrıştırma ("2 yumurta, 1,5 dilim ekmek")

public struct ParsedLine: Equatable, Sendable {
    public var qty: Double
    public var unit: String?
    public var name: String
    public var raw: String
    public var frac: Double?
    /// Sayıyla verildi ("3 köfte"): birim yoksa porsiyon yerine adet kullanılır (NU-33)
    public var counted = false
}

public enum TextParser {
    static let wordNum: [String: Double] = ["yarim": 0.5, "bir": 1, "iki": 2, "uc": 3, "dort": 4, "bes": 5, "alti": 6, "yedi": 7, "sekiz": 8, "dokuz": 9, "on": 10, "ceyrek": 0.25]
    static let units: [(String, [String])] = [
        ("g", ["g", "gr", "gram"]), ("ml", ["ml"]), ("dilim", ["dilim"]), ("adet", ["adet", "tane"]), ("porsiyon", ["porsiyon", "pors"]),
        ("kutu", ["kutu"]), ("bardak", ["bardak"]), ("kase", ["kase"]), ("top", ["top"]), ("kadeh", ["kadeh"]), ("tek", ["tek"]),
        ("duble", ["duble"]), ("paket", ["paket"]), ("ölçek", ["olcek"]), ("şişe", ["sise"]), ("tabak", ["tabak"]), ("avuç", ["avuc"]),
        ("yemek kaşığı", ["yemek kasigi", "yk", "kasik"]), ("tatlı kaşığı", ["tatli kasigi", "tk"]), ("büyük", ["buyuk"]), ("kare", ["kare"]),
        ("su bardağı", ["su bardagi"]), ("çay bardağı", ["cay bardagi"]), ("çay kaşığı", ["cay kasigi", "ck"]), ("fincan", ["fincan"]),
        ("kg", ["kg", "kilo"]), ("lt", ["lt", "litre", "l"]),
    ]
    static let unitWords: Set<String> = ["g", "gr", "gram", "kg", "ml", "lt", "l", "adet", "tane", "dilim", "porsiyon", "kase", "kâse", "tabak", "bardak", "kaşık", "kasik", "yemek", "tatlı", "tatli", "çay", "cay", "avuç", "avuc", "paket", "kutu", "büyük", "buyuk", "küçük", "kucuk", "orta", "yarım", "yarim"]

    /// En çok bu kadar birim (ör. 100.000 g) — absürt girişler hesaplamayı taşırmasın (NU-31)
    public static let maxQty: Double = 100_000
    static let sizeWords = ["orta boy", "buyuk boy", "kucuk boy", "kucuk", "orta", "iri"]

    public static func parseLine(_ line: String) -> ParsedLine {
        let raw = line.trimmingCharacters(in: .whitespaces)
        var rest = raw
        var qty: Double?
        // Kesir karakterleri ve "1/2" (NU-40)
        let uni: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
        if let c = rest.first, let v = uni[c] { qty = v; rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
        else if let r = rest.range(of: #"^(\d+)\s*/\s*(\d+)\s*"#, options: .regularExpression) {
            let nums = rest[r].split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count == 2, nums[1] > 0 { qty = nums[0] / nums[1] }
            rest = String(rest[r.upperBound...])
        } else if let r = rest.range(of: #"^\d{1,3}(?:\.\d{3})+(?=\s|$)\s*"#, options: .regularExpression) {
            // binlik nokta: "1.000 ml"
            qty = Double(rest[r].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ""))
            rest = String(rest[r.upperBound...])
        } else if let r = rest.range(of: #"^\d+(?:[.,]\d+)?\s*"#, options: .regularExpression) {
            qty = Double(rest[r].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
            rest = String(rest[r.upperBound...])
        }
        var t = TextNorm.norm(rest)
        var counted = qty != nil
        if qty == nil, let w = t.split(separator: " ").first.map(String.init), let n = wordNum[w] {
            t = String(t.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
            qty = n
            // "yarım porsiyon X" → birim yine ayrıştırılır; birim yoksa kesir varsayılan porsiyona uygulanır (NU-03)
            if w == "yarim" || w == "ceyrek" {
                let p = parseUnit(t)
                return ParsedLine(qty: n, unit: p.unit, name: stripSize(p.rest), raw: raw, frac: n)
            }
            counted = true
        }
        // "bir buçuk", "1 buçuk"
        if t == "bucuk" || t.hasPrefix("bucuk ") { qty = (qty ?? 1) + 0.5; t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        var p = parseUnit(t)
        // Sondaki miktar: "pilav 200 g", "yumurta 2 adet" (NU-39)
        if qty == nil {
            let w = p.rest.split(separator: " ").map(String.init)
            if let i = w.lastIndex(where: { Double($0) != nil }), i > 0 {
                let tail = w[(i + 1)...].joined(separator: " ")
                let u = parseUnit(tail)
                // Sayıdan sonra birim olmalı: "omega 3" gibi adlar bozulmasın
                if u.rest.isEmpty, u.unit != nil {
                    qty = Double(w[i]); counted = true
                    p = (u.unit ?? p.unit, w[..<i].joined(separator: " "))
                }
            }
        }
        let q = min(max(qty ?? 1, 0), maxQty)
        return ParsedLine(qty: q.isFinite ? q : 1, unit: p.unit, name: stripSize(p.rest), raw: raw, frac: nil, counted: counted && p.unit == nil)
    }

    /// "küçük elma", "orta boy muz" → "elma", "muz"
    static func stripSize(_ s: String) -> String {
        for w in sizeWords where s.hasPrefix(w + " ") { return String(s.dropFirst(w.count + 1)) }
        return s
    }

    static func parseUnit(_ text: String) -> (unit: String?, rest: String) {
        var t = text
        for (u, alts) in units {
            for a in alts where t == a || t.hasPrefix(a + " ") {
                t = String(t.dropFirst(a.count)).trimmingCharacters(in: .whitespaces)
                return (u, t)
            }
        }
        return (nil, t)
    }

    /// Satırlara, virgüle (ondalık hariç), "ve"/"ile"ye ve "2 yumurta 1 dilim ekmek" gibi sayılara göre böler
    public static func split(_ text: String) -> [String] {
        let rough = text.replacingOccurrences(of: #"(?<!\d),|,(?!\d)"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[;+]|\s+ve\s+|\s+ile\s+"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return rough.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.flatMap(splitByNumbers)
    }

    /// "2 yumurta 1 dilim ekmek", "iki yumurta bir dilim ekmek" → ayrı satırlar; "1 porsiyon pilav 200 g" bölünmez (NU-49)
    static func splitByNumbers(_ piece: String) -> [String] {
        let words = piece.split(separator: " ").map(String.init)
        guard words.count > 2 else { return [piece] }
        func isQty(_ w: String) -> Bool {
            Double(w.replacingOccurrences(of: ",", with: ".")) != nil || wordNum[TextNorm.norm(w)] != nil || "½¼¾⅓⅔".contains(w)
        }
        func isUnit(_ w: String) -> Bool { unitWords.contains(w.lowercased()) || unitWords.contains(TextNorm.norm(w)) }
        func isName(_ w: String) -> Bool { !isQty(w) && !isUnit(w) && TextNorm.norm(w) != "bucuk" }
        var out: [String] = [], cur: [String] = []
        for (i, w) in words.enumerated() {
            if isQty(w), cur.contains(where: isName) {
                // Bu sayıdan sonra (bir sonraki sayıya kadar) bir besin adı varsa yeni satır başlar
                var j = i + 1, hasName = false
                while j < words.count, !isQty(words[j]) { if isName(words[j]) { hasName = true; break }; j += 1 }
                if hasName { out.append(cur.joined(separator: " ")); cur = [] }
            }
            cur.append(w)
        }
        out.append(cur.joined(separator: " "))
        return out.filter { !$0.isEmpty }
    }

    /// Kaşık ve bardak birimlerinin ml karşılığı: besinde o birim yoksa bilinen bir birimden oranlanır (NU-34)
    static let volumeMl: [String: Double] = ["cay kasigi": 2.5, "tatli kasigi": 5, "yemek kasigi": 15, "fincan": 60, "cay bardagi": 100, "su bardagi": 200, "bardak": 200]

    /// Porsiyon anahtarı büyük/küçük harf ve Türkçe karakterden bağımsız bulunur (NU-42)
    public static func portion(_ key: String, _ food: FoodItem) -> Double? {
        if let v = food.portions[key] { return v }
        let k = TextNorm.norm(key)
        return food.portions.first { TextNorm.norm($0.key) == k }?.value
    }

    /// Ayrıştırılan satırın gram karşılığı
    public static func grams(_ p: ParsedLine, food: FoodItem) -> Double {
        let g = rawGrams(p, food: food)
        return g.isFinite ? min(max(0, g), maxQty * 10) : 0
    }
    static func rawGrams(_ p: ParsedLine, food: FoodItem) -> Double {
        if p.unit == "g" || p.unit == "ml" { return p.qty }
        if p.unit == "kg" || p.unit == "lt" { return p.qty * 1000 }
        if let u = p.unit, let g = portion(u, food) { return p.qty * g }
        if let u = p.unit, let ml = volumeMl[TextNorm.norm(u)] {
            if let ref = food.portions.first(where: { volumeMl[TextNorm.norm($0.key)] != nil }), let refMl = volumeMl[TextNorm.norm(ref.key)] {
                return p.qty * ref.value * ml / refMl
            }
            return p.qty * ml
        }
        // Birim yoksa: sayıyla verildiyse önce adet, değilse önce porsiyon; sonra alfabetik ilk porsiyon
        let first = p.counted ? (portion("adet", food) ?? portion("porsiyon", food)) : (portion("porsiyon", food) ?? portion("adet", food))
        let base = first ?? food.portions.sorted { $0.key < $1.key }.first?.value ?? 100
        return p.qty * base
    }

    /// Miktar besinin kendi birimiyle mi hesaplandı (değilse arayüz "tahmini" uyarısı gösterebilir)
    public static func isExact(_ p: ParsedLine, food: FoodItem) -> Bool {
        if let u = p.unit { return ["g", "ml", "kg", "lt"].contains(u) || portion(u, food) != nil }
        return portion("adet", food) != nil || portion("porsiyon", food) != nil
    }
}
