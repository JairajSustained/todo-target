import Testing
import Foundation
@testable import TodoTargetCore

private let utc = Fixtures.utc
private let goalIDs = Fixtures.goalIDs
private func day(_ s: String) -> DayKey { Fixtures.day(s) }

/// Own {0,1,2} for each day from `a` to `b` inclusive.
private func full(_ a: String, _ b: String, calendar: Calendar = utc) -> [String: Set<Int>] {
    var out: [String: Set<Int>] = [:]
    var d = day(a)
    let end = day(b)
    while d <= end {
        out[d.string] = [0, 1, 2]
        d = d.adding(days: 1, calendar: calendar)
    }
    return out
}

private func eval(_ data: AppData, today: String, calendar: Calendar = utc) -> StreakState {
    StreakEngine.evaluate(data: data, today: day(today), calendar: calendar)
}

@Test func openTodayDoesNotBreakStreak() {
    let s = eval(Fixtures.make(own: full("2026-11-06", "2026-11-16"), firstUse: "2026-11-06"), today: "2026-11-17")
    #expect(s.current == 11); #expect(s.atRisk == nil); #expect(s.catchUp == nil)
}

@Test func fullTodayAddsOne() {
    let s = eval(Fixtures.make(own: full("2026-11-06", "2026-11-17"), firstUse: "2026-11-06"), today: "2026-11-17")
    #expect(s.current == 12)
}

@Test func missedDayOpensCatchUpWithAtRiskStreak() {
    var own = full("2026-11-06", "2026-11-15")
    own["2026-11-16"] = [0]
    let s = eval(Fixtures.make(own: own, firstUse: "2026-11-06"), today: "2026-11-17")
    #expect(s.current == 0); #expect(s.atRisk == 10)
    #expect(s.catchUp?.day == day("2026-11-16"))
    #expect(s.catchUp?.owedGoalIDs == [goalIDs[1], goalIDs[2]])
}

@Test func fullCatchUpPlusFullTodayGivesTwelve() {
    let data = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-17": [0, 1, 2]]) { a, _ in a },
                             recovered: ["2026-11-16": [0, 1, 2]], firstUse: "2026-11-06")
    let s = eval(data, today: "2026-11-17")
    #expect(s.current == 12); #expect(s.catchUp == nil)
    #expect(s.activeDays.contains(day("2026-11-16")))
}

@Test func recoveredButTodayIncompleteKeepsCatchUpOpen() {
    let data = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-16": [0], "2026-11-17": [0, 1]]) { a, _ in a },
                             recovered: ["2026-11-16": [1, 2]], firstUse: "2026-11-06")
    let s = eval(data, today: "2026-11-17")
    #expect(s.catchUp != nil); #expect(s.catchUp?.owedGoalIDs == []); #expect(s.atRisk == 10); #expect(s.current == 0)
}

@Test func noCatchUpWhenNoStreakToSave() {
    let s = eval(Fixtures.make(firstUse: "2026-11-16"), today: "2026-11-17")
    #expect(s.catchUp == nil)
}

@Test func twoMissedDaysBreakStreak() {
    let s = eval(Fixtures.make(own: full("2026-11-06", "2026-11-14"), firstUse: "2026-11-06"), today: "2026-11-17")
    #expect(s.current == 0); #expect(s.catchUp == nil); #expect(s.atRisk == nil)
}

@Test func bestTracksLongestRun() {
    let own = full("2026-11-08", "2026-11-12").merging(full("2026-11-14", "2026-11-16")) { a, _ in a }
    let s = eval(Fixtures.make(own: own, firstUse: "2026-11-08"), today: "2026-11-17")
    #expect(s.best == 5); #expect(s.current == 3)
}

@Test func streakSpansYearBoundary() {
    let s = eval(Fixtures.make(own: full("2025-12-29", "2026-01-02"), firstUse: "2025-12-29"), today: "2026-01-03")
    #expect(s.current == 5)
}

@Test func streakAcrossDSTChange() {
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = TimeZone(identifier: "America/New_York")!
    let data = Fixtures.make(own: full("2026-03-06", "2026-03-10", calendar: ny), firstUse: "2026-03-06", calendar: ny)
    let s = eval(data, today: "2026-03-10", calendar: ny)
    #expect(s.current == 5)
}

@Test func wrongGoalCountIsNeverEverythingDone() {
    var none = Fixtures.make(own: full("2026-11-06", "2026-11-16"), firstUse: "2026-11-06")
    none.goals = []
    #expect(eval(none, today: "2026-11-17").current == 0)
    var two = Fixtures.make(own: full("2026-11-06", "2026-11-16"), firstUse: "2026-11-06")
    two.goals.removeLast()
    let s = eval(two, today: "2026-11-17")
    #expect(s.current == 0); #expect(s.best == 0); #expect(s.activeDays.isEmpty)
}
