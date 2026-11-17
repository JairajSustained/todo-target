import Foundation

/// A calendar day, identified by year, month and day. Never uses 86400-second maths.
public struct DayKey: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    /// Parses "yyyy-MM-dd". Returns nil for malformed or impossible dates.
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first),
              range.contains(d) else { return nil }
        self.year = y
        self.month = m
        self.day = d
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func date(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, calendar: Calendar) -> DayKey {
        let start = date(calendar: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return DayKey(date: moved, calendar: calendar)
    }

    public static func < (a: DayKey, b: DayKey) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}
