import Testing
import Foundation
@testable import TodoTargetCore

private let utc = Fixtures.utc
private let ny: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, calendar: Calendar = utc) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Test func nextMidnightIsStartOfNextDay() {
    #expect(DayRollover.nextMidnight(after: date(2026, 11, 17, 23, 59), calendar: utc) == date(2026, 11, 18))
}

@Test func nextMidnightAcrossDSTIsNextLocalMidnight() {
    let next = DayRollover.nextMidnight(after: date(2026, 3, 8, 12, calendar: ny), calendar: ny)
    #expect(next == date(2026, 3, 9, calendar: ny))
}

@Test func nextMidnightAtExactMidnightIsNextDay() {
    #expect(DayRollover.nextMidnight(after: date(2026, 11, 18), calendar: utc) == date(2026, 11, 19))
}

@Test func trackerFollowsClockPastMidnight() {
    let clock = MutableClock(now: date(2026, 11, 17, 23, 50))
    let tracker = DayTracker(clock: clock, calendar: utc)
    #expect(tracker.today.string == "2026-11-17")
    clock.now = clock.now.addingTimeInterval(20 * 60)
    #expect(tracker.refresh() == true)
    #expect(tracker.today.string == "2026-11-18")
}

@Test func trackerRefreshWithoutDayChangeReturnsFalse() {
    let clock = MutableClock(now: date(2026, 11, 17, 10))
    let tracker = DayTracker(clock: clock, calendar: utc)
    clock.now = clock.now.addingTimeInterval(60)
    #expect(tracker.refresh() == false)
    #expect(tracker.today.string == "2026-11-17")
}

@Test func streakChangesWhenDayRollsOver() {
    var own: [String: Set<Int>] = [:]
    var d = Fixtures.day("2026-11-06")
    while d <= Fixtures.day("2026-11-16") { own[d.string] = [0, 1, 2]; d = d.adding(days: 1, calendar: utc) }
    let data = Fixtures.make(own: own, firstUse: "2026-11-06")
    let clock = MutableClock(now: date(2026, 11, 17, 23, 50))
    let tracker = DayTracker(clock: clock, calendar: utc)
    #expect(StreakEngine.evaluate(data: data, today: tracker.today, calendar: utc).current == 11)
    clock.now = date(2026, 11, 18, 0, 5)
    tracker.refresh()
    let s = StreakEngine.evaluate(data: data, today: tracker.today, calendar: utc)
    #expect(s.current == 0); #expect(s.catchUp?.day == Fixtures.day("2026-11-17"))
}

@Test func trackerSurvivesMultiDaySleep() {
    let clock = MutableClock(now: date(2026, 11, 17, 22))
    let tracker = DayTracker(clock: clock, calendar: utc)
    clock.now = date(2026, 11, 20, 8)
    #expect(tracker.refresh() == true)
    #expect(tracker.today.string == "2026-11-20")
}

@Test func systemClockHonorsTodayOverrideAtNoon() {
    setenv("TODO_TARGET_TODAY", "2026-05-04", 1)
    defer { unsetenv("TODO_TARGET_TODAY") }
    let now = SystemClock().now
    #expect(Calendar.current.component(.hour, from: now) == 12)
    #expect(DayKey(date: now, calendar: .current).string == "2026-05-04")
}
