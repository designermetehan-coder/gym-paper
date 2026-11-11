import Foundation

/// "YYYY-MM-DD" day keys (local time). Monday = 0.
public enum DayKey {
    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .autoupdatingCurrent   // the day boundary shifts correctly when travelling
        c.firstWeekday = 2
        return c
    }()

    public static func of(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static var today: String { of(.now) }

    public static func date(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
    /// Pazartesi = 0 … Pazar = 6
    public static func weekday(_ key: String) -> Int {
        guard let d = date(key) else { return 0 }
        return (calendar.component(.weekday, from: d) + 5) % 7
    }
    public static func shift(_ key: String, days: Int) -> String {
        guard let d = date(key), let n = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return of(n)
    }
    /// Day `dow` of `key`'s week (weeks start on Monday)
    public static func weekDate(_ key: String, dow: Int, weekOffset: Int = 0) -> String {
        shift(key, days: dow - weekday(key) + 7 * weekOffset)
    }
    /// Day and month names in the app language (week starts Monday): tr "Pzt"… "Pazartesi"…, en "Mon"… "Monday"…
    private static let symbols: (short: [String], long: [String], monthShort: [String], monthLong: [String]) = {
        var c = Calendar(identifier: .gregorian)
        c.locale = .current
        func mondayFirst(_ a: [String]) -> [String] { a.count == 7 ? Array(a[1...]) + [a[0]] : a }
        return (mondayFirst(c.shortStandaloneWeekdaySymbols), mondayFirst(c.standaloneWeekdaySymbols),
                c.shortStandaloneMonthSymbols, c.standaloneMonthSymbols)
    }()
    public static var dayShort: [String] { symbols.short }
    public static var dayLong: [String] { symbols.long }
    /// "Oca" / "Jan" (12 items)
    public static var monthShort: [String] { symbols.monthShort }
    /// "Ocak" / "January" (12 items)
    public static var monthLong: [String] { symbols.monthLong }
}
