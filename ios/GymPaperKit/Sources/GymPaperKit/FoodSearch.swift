import Foundation

// Food data has 3 layers: (1) built-in Turkish food list + My foods, (2) Open Food Facts (barcode/online),
// (3) FatSecret (via the GYM Paper server; on once a key is set).

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
        switch source { case .builtin: "GYM Paper"; case .mine: "Besinlerim"; case .off: "Open Food Facts"; case .fatsecret: "FatSecret"; case .recipe: "Tarif" }
    }
}

public enum TextNorm {
    /// Simplifies Turkish letters, lowercases and strips punctuation ("Çiğ Köfte" → "cig kofte")
    private static let tr = Locale(identifier: "tr_TR")   // no new Locale per call
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
                    // other accented letters are simplified ("crème" → "creme"); non-Latin letters are kept so names don't collide
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
    /// Search index (normalized name + words); computed once for the built-in list
    struct Doc { let item: FoodItem; let name: String; let nameWords: [String]; let words: [String] }
    static func doc(_ f: FoodItem) -> Doc {
        let name = TextNorm.norm(f.name)
        let nw = name.split(separator: " ").map(String.init)
        let tw = TextNorm.norm(f.tags).split(separator: " ").map(String.init)
        return Doc(item: f, name: name, nameWords: nw, words: nw + tw)
    }
    static let builtinIndex: [Doc] = LocalFoods.all.map(doc)

    /// One-letter tolerance (swap/missing/extra)
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
    /// Strips Turkish possessive/accusative suffixes and re-hardens a softened final consonant ("yogurdu" → "yogurt", "kebabi" → "kebap")
    static func stem(_ q: String) -> String? {
        guard q.count >= 5, let last = q.last, "aeiou".contains(last) else { return nil }
        var b = String(q.dropLast())
        // buffer letters: "kahvesi" → "kahve", "suyu" → "su"
        if let c = b.last, "sy".contains(c), "aeiou".contains(b.dropLast().last ?? "x") { b = String(b.dropLast()); return b.count >= 2 ? b : nil }
        guard let c = b.last else { return nil }
        let hard: [Character: Character] = ["d": "t", "b": "p", "g": "k", "c": "c"]
        if let h = hard[c] { b = String(b.dropLast()) + String(h) }
        return b.count >= 3 ? b : nil
    }

    /// Whether a query word matches a word: 1 full/prefix, 0.6 typo, 0 none
    static func wordScore(_ q: String, _ words: [String]) -> Double {
        let base = wordScoreRaw(q, words)
        guard base < 1, let st = stem(q) else { return base }
        return max(base, wordScoreRaw(st, words) * 0.95)
    }
    static func wordScoreRaw(_ q: String, _ words: [String]) -> Double {
        var best = 0.0
        for w in words {
            if w == q { return 1.1 }
            if w.hasPrefix(q) { best = max(best, 1) }
            else if q.count >= 4, w.count >= q.count - 1 {
                // typo: compare with the word's prefix of the same length ("tavk" → "tavuk")
                if near(Substring(q), w.prefix(q.count)) || near(Substring(q), w.prefix(q.count + 1)) || near(Substring(q), w.prefix(max(1, q.count - 1))) { best = max(best, 0.6) }
            } else if q.count >= 3, w.contains(q) { best = max(best, 0.5) }
        }
        return best
    }

    /// For generic queries the most likely food comes first ("ekmek" → white bread, not "ekmek kadayıfı")
    static let preferred: [String: String] = [
        "ekmek": "Beyaz ekmek", "pilav": "Pirinç pilavı", "kofte": "Köfte (ızgara)", "peynir": "Beyaz peynir (tam yağlı)",
        "yogurt": "Yoğurt (tam yağlı)", "sut": "Süt (yarım yağlı)", "yumurta": "Haşlanmış yumurta", "tavuk": "Tavuk göğsü (ızgara)",
        "makarna": "Makarna (haşlanmış)", "corba": "Mercimek çorbası", "salata": "Çoban salata", "pirinc": "Pirinç (haşlanmış)",
        "kahve": "Türk kahvesi (sade)", "cay": "Çay (şekersiz)", "elma": "Elma", "doner": "Döner (et, porsiyon)",
        // generic words don't go to dishes with a type suffix ("su" → not "su böreği")
        "su": "Su", "tuz": "Tuz", "seker": "Toz şeker", "kiyma": "Dana kıyma (%20 yağ)", "cikolata": "Sütlü çikolata",
    ]

    /// Synonyms and English equivalents: the query is searched with these too, scored slightly lower
    static let synonyms: [String: [String]] = [
        "labne": ["krem peynir", "suzme peynir"], "suzme peynir": ["labne", "surulebilir peynir"], "krem peynir": ["labne"],
        "quark": ["lor", "skyr"], "lor": ["cokelek", "quark"], "cokelek": ["lor"], "skyr": ["suzme yogurt", "quark"],
        "yunan yogurdu": ["suzme yogurt"], "greek yogurt": ["suzme yogurt"], "whey": ["protein tozu"], "protein tozu": ["whey"],
        "protein": ["whey", "protein bar"], "bar": ["protein bar", "yulaf bar"], "burger": ["hamburger"], "hamburger": ["burger"],
        "cips": ["cipsi"], "kizartma": ["patates kizartmasi"], "nugget": ["citir tavuk"], "kanat": ["tavuk kanat"],
        "kahvalti": ["serpme kahvalti"], "smoothie": ["milkshake"], "milkshake": ["smoothie"], "kraker": ["galeta"],
        "chicken": ["tavuk"], "egg": ["yumurta"], "eggs": ["yumurta"], "cheese": ["peynir"], "rice": ["pirinc", "pilav"],
        "oat": ["yulaf"], "oats": ["yulaf"], "milk": ["sut"], "bread": ["ekmek"], "pasta": ["makarna"], "coffee": ["kahve"],
        "tea": ["cay"], "beer": ["bira"], "wine": ["sarap"], "water": ["su"], "beef": ["dana"], "lamb": ["kuzu"], "fish": ["balik"],
        "salmon": ["somon"], "tuna": ["ton baligi"], "shrimp": ["karides"], "potato": ["patates"], "banana": ["muz"], "apple": ["elma"],
        "yogurt": ["yogurt"], "honey": ["bal"], "butter": ["tereyagi"], "olive": ["zeytin"], "nuts": ["kuruyemis"], "almond": ["badem"],
        "walnut": ["ceviz"], "hazelnut": ["findik"], "peanut butter": ["fistik ezmesi"], "chocolate": ["cikolata"], "cake": ["kek", "pasta"],
        "cookie": ["kurabiye"], "ice cream": ["dondurma"], "soup": ["corba"], "salad": ["salata"], "sandwich": ["sandvic"], "toast": ["tost"],
        "dondurma": ["gelato"], "gelato": ["dondurma"], "kola": ["kola zero"], "soda": ["maden suyu"], "maden suyu": ["soda"],
        "tatlandirici": ["stevia"], "stevia": ["tatlandirici"], "sucuk": ["sucuk"], "salam": ["jambon"], "jambon": ["salam"],
    ]
    static func alternatives(_ qq: String) -> [String] {
        var out: [String] = synonyms[qq] ?? []
        let w = qq.split(separator: " ").map(String.init)
        if w.count > 1 {
            for (i, x) in w.enumerated() {
                for alt in synonyms[x] ?? [] where alt != x { var y = w; y[i] = alt; out.append(y.joined(separator: " ")) }
            }
        }
        return Array(Set(out.filter { $0 != qq }))
    }

    static func score(_ d: Doc, _ qq: String, _ qw: [String]) -> Double {
        guard !qq.isEmpty else { return 0 }
        if d.name == qq { return 200 }
        if let pref = preferred[qq], d.item.name == pref { return 190 }
        var total = 0.0, hits = 0
        for (k, w) in qw.enumerated() {
            let s = max(wordScore(w, d.nameWords) * 1.0, wordScore(w, d.words) * 0.8)
            if s > 0 { hits += 1; total += s * (k == 0 ? 1.3 : 1) }
        }
        // most words must match
        guard hits > 0, Double(hits) >= Double(qw.count) * 0.67 else { return 0 }
        var sc = 40 + total / Double(qw.count) * 40
        if d.name.hasPrefix(qq) { sc += 40 }
        if let f = d.nameWords.first, f.hasPrefix(qw[0]) { sc += 15 }
        sc -= min(12, Double(d.name.count) / 6)          // short and generic names first
        if d.name.contains("(") == false && d.nameWords.count <= 2 { sc += 3 }
        return sc
    }

    static func score(_ f: FoodItem, _ q: String) -> Double {
        let qq = TextNorm.norm(q)
        return score(doc(f), qq, qq.split(separator: " ").map(String.init))
    }

    /// My foods first, then the built-in list (tolerant to typos, suffixes and synonyms).
    /// Without any result the closest foods are returned ("süzme lor" → lor, süzme peynir…).
    public static func local(_ q: String, mine: [FoodItem] = [], limit: Int = 30) -> [FoodItem] {
        let qq = TextNorm.norm(q)
        let qw = qq.split(separator: " ").map(String.init)
        guard !qw.isEmpty else { return [] }
        let docs = mine.map(doc) + builtinIndex
        let alts = alternatives(qq).map { ($0, $0.split(separator: " ").map(String.init)) }
        let bonus: (Doc) -> Double = { $0.item.source == .mine ? 25 : 0 }
        var hits = docs.map { d -> (FoodItem, Double) in
            var s = score(d, qq, qw)
            for (a, aw) in alts { s = max(s, score(d, a, aw) * 0.92) }
            return (d.item, s > 0 ? s + bonus(d) : 0)
        }.filter { $0.1 > 0 }
        if hits.isEmpty && qw.count > 1 {
            // close result: at least one word matches; the longest word weighs most
            hits = docs.compactMap { d in
                let s = qw.reduce(0.0) { $0 + max(wordScore($1, d.nameWords), wordScore($1, d.words) * 0.8) * Double($1.count) }
                return s > 0 ? (d.item, s - Double(d.name.count) / 20 + bonus(d)) : nil
            }
        }
        return hits.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
    /// De-duplicates results with the same name (the first one stays)
    public static func dedupe(_ items: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>(); return items.filter { seen.insert(TextNorm.norm($0.name)).inserted }
    }
}

// MARK: - "Type it in" parsing ("2 eggs, 1.5 slices of bread")

public struct ParsedLine: Equatable, Sendable {
    public var qty: Double
    public var unit: String?
    public var name: String
    public var raw: String
    public var frac: Double?
    /// Given with a count ("3 meatballs"): without a unit, pieces are used instead of servings
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

    /// At most this many units (e.g. 100,000 g) so absurd input doesn't overflow the math
    public static let maxQty: Double = 100_000
    static let sizeWords = ["orta boy", "buyuk boy", "kucuk boy", "kucuk", "orta", "iri"]

    public static func parseLine(_ line: String) -> ParsedLine {
        let raw = line.trimmingCharacters(in: .whitespaces)
        var rest = raw
        var qty: Double?
        // fraction characters and "1/2"
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
            // "yarım porsiyon X" → the unit is still parsed; without a unit the fraction applies to the default serving
            if w == "yarim" || w == "ceyrek" {
                let p = parseUnit(t)
                return ParsedLine(qty: n, unit: p.unit, name: stripSize(p.rest), raw: raw, frac: n)
            }
            counted = true
        }
        // "bir buçuk", "1 buçuk" (one and a half)
        if t == "bucuk" || t.hasPrefix("bucuk ") { qty = (qty ?? 1) + 0.5; t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        var p = parseUnit(t)
        // trailing amount: "pilav 200 g", "yumurta 2 adet"
        if qty == nil {
            let w = p.rest.split(separator: " ").map(String.init)
            if let i = w.lastIndex(where: { Double($0) != nil }), i > 0 {
                let tail = w[(i + 1)...].joined(separator: " ")
                let u = parseUnit(tail)
                // a unit must follow the number so names like "omega 3" aren't broken
                if u.rest.isEmpty, u.unit != nil {
                    qty = Double(w[i]); counted = true
                    p = (u.unit ?? p.unit, w[..<i].joined(separator: " "))
                }
            }
        }
        let q = min(max(qty ?? 1, 0), maxQty)
        return ParsedLine(qty: q.isFinite ? q : 1, unit: p.unit, name: stripSize(p.rest), raw: raw, frac: nil, counted: counted && p.unit == nil)
    }

    /// "küçük elma", "orta boy muz" → "elma", "muz" (size words dropped)
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

    /// Splits on lines, commas (except decimals), "ve"/"ile" and numbers as in "2 yumurta 1 dilim ekmek"
    public static func split(_ text: String) -> [String] {
        let rough = text.replacingOccurrences(of: #"(?<!\d),|,(?!\d)"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[;+]|\s+ve\s+|\s+ile\s+"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        return rough.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.flatMap(splitByNumbers)
    }

    /// "2 yumurta 1 dilim ekmek", "iki yumurta bir dilim ekmek" → separate lines; "1 porsiyon pilav 200 g" isn't split
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
                // a new line starts when a food name follows this number (up to the next number)
                var j = i + 1, hasName = false
                while j < words.count, !isQty(words[j]) { if isName(words[j]) { hasName = true; break }; j += 1 }
                if hasName { out.append(cur.joined(separator: " ")); cur = [] }
            }
            cur.append(w)
        }
        out.append(cur.joined(separator: " "))
        return out.filter { !$0.isEmpty }
    }

    /// ml for spoon and cup units: if the food lacks that unit, it's scaled from a known one
    static let volumeMl: [String: Double] = ["cay kasigi": 2.5, "tatli kasigi": 5, "yemek kasigi": 15, "fincan": 60, "cay bardagi": 100, "su bardagi": 200, "bardak": 200]

    /// Serving keys are matched regardless of case and Turkish characters
    public static func portion(_ key: String, _ food: FoodItem) -> Double? {
        if let v = food.portions[key] { return v }
        let k = TextNorm.norm(key)
        return food.portions.first { TextNorm.norm($0.key) == k }?.value
    }

    /// Grams for a parsed line
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
        // without a unit: pieces first if a count was given, servings otherwise; then the first serving alphabetically
        let first = p.counted ? (portion("adet", food) ?? portion("porsiyon", food)) : (portion("porsiyon", food) ?? portion("adet", food))
        let base = first ?? food.portions.sorted { $0.key < $1.key }.first?.value ?? 100
        return p.qty * base
    }

    /// Whether the amount used the food's own unit (otherwise the UI can show an "estimated" note)
    public static func isExact(_ p: ParsedLine, food: FoodItem) -> Bool {
        if let u = p.unit { return ["g", "ml", "kg", "lt"].contains(u) || portion(u, food) != nil }
        return portion("adet", food) != nil || portion("porsiyon", food) != nil
    }
}
