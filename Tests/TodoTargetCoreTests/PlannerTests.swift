import Testing
import Foundation
@testable import TodoTargetCore

private let utc = Fixtures.utc
private let ids = Fixtures.goalIDs
private func day(_ s: String) -> DayKey { Fixtures.day(s) }
private func items(_ n: Int) -> [ListItem] {
    (0..<n).map { ListItem(group: "G", title: "Item \($0)", url: URL(string: "https://example.com/\($0)")) }
}
private func full(_ a: String, _ b: String) -> [String: Set<Int>] {
    var out: [String: Set<Int>] = [:]
    var d = day(a)
    while d <= day(b) { out[d.string] = [0, 1, 2]; d = d.adding(days: 1, calendar: utc) }
    return out
}
private let today = "2026-11-17"
/// Streak alive through 11-15; yesterday (11-16) has only slot 0 done.
private func catchUpOwn(extra: [String: Set<Int>] = [:]) -> [String: Set<Int>] {
    var o = full("2026-11-06", "2026-11-15")
    o["2026-11-16"] = [0]
    return o.merging(extra) { _, b in b }
}
private func owed(_ d: AppData) -> [OwedTask] { Planner.owedTasks(data: d, today: day(today), calendar: utc) }

@Test func catchUpTasksComeFirst() {
    let t = owed(Fixtures.make(own: catchUpOwn(), firstUse: "2026-11-06"))
    #expect(t.map(\.isCatchUp) == [true, true, false, false, false])
    #expect(t.map(\.slot) == [1, 2, 0, 1, 2])
    #expect(t[0].forDay == day("2026-11-16")); #expect(t[2].forDay == day(today))
}

@Test func nextTaskSkipsDoneGoals() {
    let d = Fixtures.make(own: full("2026-11-06", "2026-11-16").merging([today: [0]]) { a, _ in a }, firstUse: "2026-11-06")
    #expect(Planner.nextTask(data: d, today: day(today), calendar: utc)?.slot == 1)
}

@Test func nextTaskNilWhenAllDone() {
    let d = Fixtures.make(own: full("2026-11-06", today), firstUse: "2026-11-06")
    #expect(Planner.nextTask(data: d, today: day(today), calendar: utc) == nil)
}

@Test func taskItemComesFromListPosition() {
    var d = Fixtures.make(firstUse: today, lists: [0: items(3)])
    d.goals[0].position = 1
    #expect(Planner.nextTask(data: d, today: day(today), calendar: utc)?.item?.title == items(3)[1].title)
}

@Test func goalOwedOnTwoDaysShowsConsecutiveItems() {
    let d = Fixtures.make(own: catchUpOwn(), firstUse: "2026-11-06", lists: [1: items(3)])
    let t = owed(d)
    #expect(t[0].slot == 1); #expect(t[0].isCatchUp); #expect(t[0].item == items(3)[0])
    #expect(t[3].slot == 1); #expect(!t[3].isCatchUp); #expect(t[3].item == items(3)[1])
}

@Test func itemIsNilWhenListIsExhausted() {
    var d = Fixtures.make(firstUse: today, lists: [0: items(2)])
    d.goals[0].position = 2
    #expect(Planner.nextTask(data: d, today: day(today), calendar: utc)?.item == nil)
}

@Test func progressInCatchUp() {
    let d = Fixtures.make(own: catchUpOwn(extra: [today: [0]]), recovered: ["2026-11-16": [1]], firstUse: "2026-11-06")
    let p = Planner.progress(data: d, today: day(today), calendar: utc)
    #expect(p.done == 2); #expect(p.total == 5)
}

@Test func progressNormalDay() {
    let d = Fixtures.make(own: [today: [0, 1]], firstUse: today)
    let p = Planner.progress(data: d, today: day(today), calendar: utc)
    #expect(p.done == 2); #expect(p.total == 3)
}

@Test func iconLevelTable() {
    for (d, t, l) in [(0,3,0),(1,3,1),(2,3,2),(3,3,3),(1,5,1),(2,5,1),(3,5,2),(4,5,2),(5,5,3)] {
        #expect(Planner.iconLevel(done: d, total: t) == l)
    }
}
