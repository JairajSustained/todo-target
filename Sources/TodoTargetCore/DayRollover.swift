import Foundation

public enum DayRollover {
    /// The next local midnight strictly after `after`. Uses the calendar, so DST days are right.
    public static func nextMidnight(after: Date, calendar: Calendar) -> Date {
        let next = calendar.nextDate(after: after,
                                     matching: DateComponents(hour: 0, minute: 0, second: 0),
                                     matchingPolicy: .nextTime)
        if let next { return next }
        let start = calendar.startOfDay(for: after)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? after.addingTimeInterval(86_400)
    }
}

/// Follows the clock and reports when the calendar day changes.
public final class DayTracker {
    private let clock: Clock
    private let calendar: Calendar
    public private(set) var today: DayKey

    public init(clock: Clock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
        self.today = DayKey(date: clock.now, calendar: calendar)
    }

    /// Returns true when the day changed since the last call.
    @discardableResult
    public func refresh() -> Bool {
        let now = DayKey(date: clock.now, calendar: calendar)
        guard now != today else { return false }
        today = now
        return true
    }
}
