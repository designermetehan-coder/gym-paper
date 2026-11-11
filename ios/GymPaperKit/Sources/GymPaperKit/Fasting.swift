import Foundation

/// Intermittent fasting: fixed daily schedule (e.g. 16:8 → starts 20:00 every day, ends 12:00 the next day).
/// Each fast is keyed by the day it starts; that day's exceptions (skip / end early) are kept separately.
public struct FastPlan: Codable, Hashable, Sendable {
    /// Fast start time, minutes after midnight (20:00 → 1200)
    public var startMin: Int
    /// Fast length (minutes); derived from start and end time
    public var durMin: Int
    /// By start day: skipped fasts
    public var skipped: Set<String>
    /// By start day: end time of fasts ended early
    public var endedAt: [String: Date]
    /// By start day: that day's own fast start. When a fast ends early the eating window opens in full from
    /// that moment and the next fast moves earlier accordingly
    public var startAt: [String: Date] = [:]

    public init(startMin: Int = 20 * 60, hours: Int = 16, skipped: Set<String> = [], endedAt: [String: Date] = [:]) {
        self.init(startMin: startMin, durMin: hours * 60, skipped: skipped, endedAt: endedAt)
    }
    public init(startMin: Int, durMin: Int, skipped: Set<String> = [], endedAt: [String: Date] = [:], startAt: [String: Date] = [:]) {
        self.startMin = max(0, min(24 * 60 - 1, startMin))
        self.durMin = max(30, min(23 * 60 + 30, durMin))
        self.skipped = skipped; self.endedAt = endedAt; self.startAt = startAt
    }
    /// From start and end time (the end may fall on the next day)
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

    /// Ends the fast at `t`: the eating window starts now and stays open for its full length;
    /// the next fast (next day's key) moves earlier for that day only
    public mutating func endEarly(_ key: String, at t: Date = .now, calendar: Calendar = DayKey.calendar) {
        guard let s = start(of: key, calendar: calendar), t > s,
              t < s.addingTimeInterval(TimeInterval(durMin) * 60) else { return }
        endedAt[key] = t
        let next = DayKey.shift(key, days: 1)
        let planned = start(of: next, calendar: calendar)
        let shifted = t.addingTimeInterval(TimeInterval(eatingMin) * 60)
        if planned.map({ shifted < $0 }) ?? true { startAt[next] = shifted }
    }

    /// End time (minutes after midnight)
    public var endMin: Int { (startMin + durMin) % 1440 }
    /// Whole hours (for labels)
    public var hours: Int { durMin / 60 }
    /// "16:8" on whole hours; "15.5 h" otherwise
    public var label: String {
        durMin % 60 == 0 ? "\(durMin / 60):\(24 - durMin / 60)" : String(format: "%.1f sa", Double(durMin) / 60).replacingOccurrences(of: ".", with: ",")
    }

    /// Presets: fasting hours : eating window
    public static let presets: [(label: String, hours: Int)] = [("14:10", 14), ("16:8", 16), ("18:6", 18), ("20:4", 20)]

    public enum Phase: Equatable, Sendable {
        /// Fasting: start, planned end, key (start day)
        case fasting(start: Date, end: Date, key: String)
        /// Eating window: when it opened, start of the next fast; `fastKey` is the day of the fast that ended (if any)
        case eating(since: Date, nextFast: Date, fastKey: String?)
    }

    /// Start of the fast that begins that day
    public func start(of key: String, calendar: Calendar = DayKey.calendar) -> Date? {
        if let o = startAt[key] { return o }   // that day's own
        guard let d = DayKey.date(key) else { return nil }
        let day = calendar.startOfDay(for: d)
        // build with hour/minute so DST changes don't shift it by an hour
        if startMin >= 0, startMin < 24 * 60,
           let t = calendar.date(bySettingHour: startMin / 60, minute: startMin % 60, second: 0, of: day) { return t }
        return calendar.date(byAdding: .minute, value: startMin, to: day)
    }

    /// Actual end of the fast that began that day (the moment it was ended early); nil if skipped
    public func end(of key: String, calendar: Calendar = DayKey.calendar) -> Date? {
        guard !skipped.contains(key), let s = start(of: key, calendar: calendar) else { return nil }
        let planned = s.addingTimeInterval(TimeInterval(durMin) * 60)
        if let e = endedAt[key], e > s, e < planned { return e }
        return planned
    }

    /// State at `t`
    public func phase(at t: Date, calendar: Calendar = DayKey.calendar) -> Phase {
        let today = DayKey.of(t)
        // a fast that started today or yesterday may still be running
        for key in [today, DayKey.shift(today, days: -1)] {
            guard let s = start(of: key, calendar: calendar), s <= t, let e = end(of: key, calendar: calendar) else { continue }
            if t < e { return .fasting(start: s, end: e, key: key) }
        }
        // eating window: from the last finished fast to the next one
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

    /// Completion ratio of finished, non-skipped fasts (0…1); early ends count proportionally
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

/// Fasting stages: approximate body stage by time since the fast began.
/// For information only; thresholds vary by person and make no medical claim.
public enum FastStage: Int, CaseIterable, Sendable, Hashable {
    case digest, sugar, fatBurn, ketosis

    /// Approximate hour the stage begins (from the start of the fast)
    public var startHour: Double { [0, 4, 12, 16][rawValue] }
    public var startSeconds: TimeInterval { startHour * 3600 }
    /// UI key (localized in the app)
    public var title: String { ["Sindirim", "Şeker düşüyor", "Yağ yakımı", "Ketozis"][rawValue] }
    public var next: FastStage? { FastStage(rawValue: rawValue + 1) }

    /// Stage by elapsed time
    public static func at(elapsed: TimeInterval) -> FastStage {
        allCases.last { $0.startSeconds <= max(0, elapsed) } ?? .digest
    }

    /// Stages reached in a fast of this length (a stage starting exactly at the end doesn't count)
    public static func reachable(duration: TimeInterval) -> [FastStage] {
        allCases.filter { $0.startSeconds < duration }
    }

    /// Track segments: stage, start and end ratio (0…1)
    public static func segments(duration: TimeInterval) -> [(stage: FastStage, from: Double, to: Double)] {
        let d = max(1, duration)
        let st = reachable(duration: d)
        return st.enumerated().map { i, s in
            let end = i + 1 < st.count ? st[i + 1].startSeconds : d
            return (s, s.startSeconds / d, min(1, end / d))
        }
    }
}
