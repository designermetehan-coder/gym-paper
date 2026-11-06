import Foundation

/// Aralıklı oruç: sabit günlük program (ör. 16:8 → her gün 20:00'de başlar, ertesi gün 12:00'de biter).
/// Her orucun anahtarı başladığı gündür; o güne ait istisnalar (atla / erken bitir) ayrıca tutulur.
public struct FastPlan: Codable, Hashable, Sendable {
    /// Orucun başladığı saat, gece yarısından dakika (20:00 → 1200)
    public var startMin: Int
    /// Oruç süresi (dakika); başlangıç ve bitiş saatinden gelir
    public var durMin: Int
    /// Başladığı güne göre: atlanan oruçlar
    public var skipped: Set<String>
    /// Başladığı güne göre: erken bitirilen oruçların bitiş zamanı
    public var endedAt: [String: Date]
    /// Başladığı güne göre: o güne özel oruç başlangıcı. Oruç erken bitirilince yeme aralığı o andan
    /// itibaren tam süre açılır ve sıradaki oruç buna göre öne çekilir (FS-01)
    public var startAt: [String: Date] = [:]

    public init(startMin: Int = 20 * 60, hours: Int = 16, skipped: Set<String> = [], endedAt: [String: Date] = [:]) {
        self.init(startMin: startMin, durMin: hours * 60, skipped: skipped, endedAt: endedAt)
    }
    public init(startMin: Int, durMin: Int, skipped: Set<String> = [], endedAt: [String: Date] = [:], startAt: [String: Date] = [:]) {
        self.startMin = max(0, min(24 * 60 - 1, startMin))
        self.durMin = max(30, min(23 * 60 + 30, durMin))
        self.skipped = skipped; self.endedAt = endedAt; self.startAt = startAt
    }
    /// Başlangıç ve bitiş saatinden (bitiş ertesi güne taşabilir)
    public init(startMin: Int, endMin: Int) {
        let d = ((endMin - startMin) % 1440 + 1440) % 1440
        self.init(startMin: startMin, durMin: d == 0 ? 16 * 60 : d)
    }

    enum CodingKeys: String, CodingKey { case startMin, durMin, hours, skipped, endedAt, startAt }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let st = (try? c.decode(Int.self, forKey: .startMin)) ?? 20 * 60
        let dm = (try? c.decode(Int.self, forKey: .durMin)) ?? ((try? c.decode(Int.self, forKey: .hours)).map { $0 * 60 } ?? 16 * 60)
        self.init(startMin: st, durMin: dm,
                  skipped: (try? c.decode(Set<String>.self, forKey: .skipped)) ?? [],
                  endedAt: (try? c.decode([String: Date].self, forKey: .endedAt)) ?? [:],
                  startAt: (try? c.decode([String: Date].self, forKey: .startAt)) ?? [:])
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(startMin, forKey: .startMin); try c.encode(durMin, forKey: .durMin)
        try c.encode(skipped, forKey: .skipped); try c.encode(endedAt, forKey: .endedAt)
        if !startAt.isEmpty { try c.encode(startAt, forKey: .startAt) }
    }

    /// Orucu `t` anında bitirir: yeme aralığı şimdi başlar ve tam süresince açık kalır;
    /// sıradaki oruç (ertesi günün anahtarı) yalnız o gün için öne çekilir (FS-01)
    public mutating func endEarly(_ key: String, at t: Date = .now, calendar: Calendar = DayKey.calendar) {
        guard let s = start(of: key, calendar: calendar), t > s,
              t < s.addingTimeInterval(TimeInterval(durMin) * 60) else { return }
        endedAt[key] = t
        let next = DayKey.shift(key, days: 1)
        let planned = start(of: next, calendar: calendar)
        let shifted = t.addingTimeInterval(TimeInterval(eatingMin) * 60)
        if planned.map({ shifted < $0 }) ?? true { startAt[next] = shifted }
    }

    /// Bitiş saati (gece yarısından dakika)
    public var endMin: Int { (startMin + durMin) % 1440 }
    /// Tam saat (etiketler için)
    public var hours: Int { durMin / 60 }
    /// "16:8" — tam saatlerde; değilse "15,5 sa"
    public var label: String {
        durMin % 60 == 0 ? "\(durMin / 60):\(24 - durMin / 60)" : String(format: "%.1f sa", Double(durMin) / 60).replacingOccurrences(of: ".", with: ",")
    }

    /// Hazır protokoller: oruç saati : yeme penceresi
    public static let presets: [(label: String, hours: Int)] = [("14:10", 14), ("16:8", 16), ("18:6", 18), ("20:4", 20)]

    public enum Phase: Equatable, Sendable {
        /// Oruçta: başlangıç, planlanan bitiş, anahtar (başladığı gün)
        case fasting(start: Date, end: Date, key: String)
        /// Yeme penceresi: açıldığı an, sıradaki orucun başlangıcı; `fastKey` biten orucun günü (varsa)
        case eating(since: Date, nextFast: Date, fastKey: String?)
    }

    /// O gün başlayan orucun başlangıcı
    public func start(of key: String, calendar: Calendar = DayKey.calendar) -> Date? {
        if let o = startAt[key] { return o }   // o güne özel (FS-01)
        guard let d = DayKey.date(key) else { return nil }
        let day = calendar.startOfDay(for: d)
        // saat/dakika ile kur: yaz/kış saati geçişinde 1 saat kaymasın (CR-38)
        if startMin >= 0, startMin < 24 * 60,
           let t = calendar.date(bySettingHour: startMin / 60, minute: startMin % 60, second: 0, of: day) { return t }
        return calendar.date(byAdding: .minute, value: startMin, to: day)
    }

    /// O gün başlayan orucun gerçek bitişi (erken bitirildiyse o an); atlandıysa nil
    public func end(of key: String, calendar: Calendar = DayKey.calendar) -> Date? {
        guard !skipped.contains(key), let s = start(of: key, calendar: calendar) else { return nil }
        let planned = s.addingTimeInterval(TimeInterval(durMin) * 60)
        if let e = endedAt[key], e > s, e < planned { return e }
        return planned
    }

    /// `t` anındaki durum
    public func phase(at t: Date, calendar: Calendar = DayKey.calendar) -> Phase {
        let today = DayKey.of(t)
        // Bugün ya da dün başlayan oruç hâlâ sürüyor olabilir
        for key in [today, DayKey.shift(today, days: -1)] {
            guard let s = start(of: key, calendar: calendar), s <= t, let e = end(of: key, calendar: calendar) else { continue }
            if t < e { return .fasting(start: s, end: e, key: key) }
        }
        // Yeme penceresi: son biten oruçtan sıradaki başlayacak oruca kadar
        var since: Date = calendar.startOfDay(for: t)
        var fastKey: String?
        for key in [today, DayKey.shift(today, days: -1), DayKey.shift(today, days: -2)] {
            if let e = end(of: key, calendar: calendar), e <= t { since = e; fastKey = key; break }
        }
        var next = start(of: today, calendar: calendar) ?? t
        var k = today
        var guardN = 0
        while (next <= t || skipped.contains(k)) && guardN < 8 {
            k = DayKey.shift(k, days: 1); next = start(of: k, calendar: calendar) ?? next; guardN += 1
        }
        return .eating(since: since, nextFast: next, fastKey: fastKey)
    }

    /// Bitmiş ve atlanmamış oruçlarda tamamlanma oranı (0…1); erken bitirilenler oransal
    public func completion(of key: String, now: Date = .now, calendar: Calendar = DayKey.calendar) -> Double? {
        guard !skipped.contains(key), let s = start(of: key, calendar: calendar), let e = end(of: key, calendar: calendar), e <= now else { return nil }
        return min(1, e.timeIntervalSince(s) / (TimeInterval(durMin) * 60))
    }

    public var eatingHours: Int { 24 - hours }
    public var eatingMin: Int { 1440 - durMin }

    public static func hm(_ min: Int) -> String { String(format: "%02d:%02d", (min / 60) % 24, min % 60) }
    public var startText: String { Self.hm(startMin) }
    public var endText: String { Self.hm(endMin) }
}

/// Oruç evreleri (RA-07): oruç başından geçen süreye göre yaklaşık vücut evresi.
/// Bilgi amaçlıdır; eşikler kişiden kişiye değişir, tıbbi iddia taşımaz.
public enum FastStage: Int, CaseIterable, Sendable, Hashable {
    case digest, sugar, fatBurn, ketosis

    /// Evrenin yaklaşık başladığı saat (oruç başından)
    public var startHour: Double { [0, 4, 12, 16][rawValue] }
    public var startSeconds: TimeInterval { startHour * 3600 }
    /// Arayüz anahtarı (uygulamada yerelleştirilir)
    public var title: String { ["Sindirim", "Şeker düşüyor", "Yağ yakımı", "Ketozis"][rawValue] }
    public var next: FastStage? { FastStage(rawValue: rawValue + 1) }

    /// Geçen süreye göre evre
    public static func at(elapsed: TimeInterval) -> FastStage {
        allCases.last { $0.startSeconds <= max(0, elapsed) } ?? .digest
    }

    /// Bu süredeki bir oruçta ulaşılan evreler (bitişte başlayan evre sayılmaz)
    public static func reachable(duration: TimeInterval) -> [FastStage] {
        allCases.filter { $0.startSeconds < duration }
    }

    /// İzdeki dilimler: evre, başlangıç ve bitiş oranı (0…1)
    public static func segments(duration: TimeInterval) -> [(stage: FastStage, from: Double, to: Double)] {
        let d = max(1, duration)
        let st = reachable(duration: d)
        return st.enumerated().map { i, s in
            let end = i + 1 < st.count ? st[i + 1].startSeconds : d
            return (s, s.startSeconds / d, min(1, end / d))
        }
    }
}
