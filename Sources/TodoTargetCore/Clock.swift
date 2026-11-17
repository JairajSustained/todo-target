import Foundation

public protocol Clock {
    var now: Date { get }
}

/// The real clock. Env `TODO_TARGET_TODAY=YYYY-MM-DD` fixes the date at noon local time (manual testing only).
public struct SystemClock: Clock {
    public init() {}

    public var now: Date {
        if let s = ProcessInfo.processInfo.environment["TODO_TARGET_TODAY"], let key = DayKey(string: s) {
            let cal = Calendar.current
            if let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: key.date(calendar: cal)) {
                return noon
            }
        }
        return Date()
    }
}

public final class MutableClock: Clock {
    public var now: Date
    public init(now: Date) { self.now = now }
}
