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
private func mark(_ data: inout AppData, _ slot: Int, _ forDay: String, today: String) throws {
    try Actions.markDone(&data, goalID: ids[slot], forDay: day(forDay), today: day(today), calendar: utc)
}
private func undo(_ data: inout AppData, _ slot: Int, _ forDay: String, today: String) throws {
    try Actions.undo(&data, goalID: ids[slot], forDay: day(forDay), today: day(today), calendar: utc)
}

@Test func markDoneRecordsCompletionAndAdvancesList() throws {
    var d = Fixtures.make(firstUse: "2026-11-17", lists: [0: items(3)])
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d.goals[0].position == 1)
    #expect(d.days["2026-11-17"]?.completions[ids[0].uuidString] == Completion(itemIndex: 0, doneOn: "2026-11-17", listVersion: 0))
}

@Test func markDoneTwiceIsNoOp() throws {
    var d = Fixtures.make(firstUse: "2026-11-17", lists: [0: items(3)])
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    let after = d
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d == after)
}

@Test func undoRestoresPosition() throws {
    var d = Fixtures.make(firstUse: "2026-11-17", lists: [0: items(3)])
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    try undo(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d.goals[0].position == 0)
    #expect(d.days["2026-11-17"]?.completions[ids[0].uuidString] == nil)
}

@Test func catchUpOnlyForOwedGoalAndOnlyYesterday() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0]
    own.removeValue(forKey: "2026-11-14")  // an open day two days before today
    var d = Fixtures.make(own: own, firstUse: "2026-11-06")
    #expect(throws: ActionError.notAllowed) { try mark(&d, 1, "2026-11-14", today: "2026-11-17") }
    var noStreak = Fixtures.make(firstUse: "2026-11-16")
    #expect(throws: ActionError.notAllowed) { try mark(&noStreak, 1, "2026-11-16", today: "2026-11-17") }
    try mark(&d, 1, "2026-11-16", today: "2026-11-17")
    #expect(d.days["2026-11-16"]?.completions[ids[1].uuidString]?.doneOn == "2026-11-17")
}

@Test func unknownGoalThrows() {
    var d = Fixtures.make(firstUse: "2026-11-17")
    #expect(throws: ActionError.unknownGoal) {
        try Actions.markDone(&d, goalID: UUID(), forDay: day("2026-11-17"), today: day("2026-11-17"), calendar: utc)
    }
}

@Test func completedListGivesNilItemIndex() throws {
    var d = Fixtures.make(firstUse: "2026-11-16", lists: [0: items(1)])
    try mark(&d, 0, "2026-11-16", today: "2026-11-16")
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d.days["2026-11-17"]?.completions[ids[0].uuidString]?.itemIndex == nil)
    #expect(d.goals[0].position == 1)
}

@Test func pastDayCompletionCannotBeUndone() {
    var d = Fixtures.make(own: ["2026-11-16": [0]], firstUse: "2026-11-16")
    #expect(throws: ActionError.notAllowed) { try undo(&d, 0, "2026-11-16", today: "2026-11-17") }
}

@Test func firstMarkSetsFirstUseDay() throws {
    var d = AppData.pristine()
    d.goals[0].id = ids[0]
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d.firstUseDay == "2026-11-17")
}

@Test func repeatMarkOnRecoveredCatchUpGoalIsNoOp() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0]
    var d = Fixtures.make(own: own, firstUse: "2026-11-06", lists: [1: items(3)])
    try mark(&d, 1, "2026-11-16", today: "2026-11-17")
    let after = d
    try mark(&d, 1, "2026-11-16", today: "2026-11-17")
    #expect(d == after)
}

@Test func repeatMarkOnGoalDoneOwnYesterdayIsNoOp() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0]
    var d = Fixtures.make(own: own, firstUse: "2026-11-06")
    let before = d
    try mark(&d, 0, "2026-11-16", today: "2026-11-17")
    #expect(d == before)
}

@Test func markDoneWithOutOfRangePositionDoesNotCrash() throws {
    var d = Fixtures.make(firstUse: "2026-11-17", lists: [0: items(3), 1: items(3)])
    d.goals[0].position = 99
    d.goals[1].position = -4
    try mark(&d, 0, "2026-11-17", today: "2026-11-17")
    try mark(&d, 1, "2026-11-17", today: "2026-11-17")
    #expect(d.days["2026-11-17"]?.completions[ids[0].uuidString]?.itemIndex == nil)
    #expect(d.days["2026-11-17"]?.completions[ids[1].uuidString]?.itemIndex == 0)
    #expect(d.goals[1].position == 1)
}


// MARK: C27 item order and undo (review fix)

/// 15 Nov full; 16 Nov: goals 1 and 2 done (slots 0, 1); goal 3 (slot 2) has a list t0...t4 at position 0; today 17 Nov.
private func reviewerScenario() -> AppData {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0, 1]
    return Fixtures.make(own: own, firstUse: "2026-11-06", lists: [2: items(5)])
}
private func rows(_ d: AppData, slot: Int) -> [OwedTask] {
    Planner.owedTasks(data: d, today: day("2026-11-17"), calendar: utc).filter { $0.slot == slot }
}
private func itemTitles(_ d: AppData, slot: Int) -> [String?] { rows(d, slot: slot).map { $0.item?.title } }
private func completion(_ d: AppData, slot: Int, onDay: String) -> Completion? {
    d.days[onDay]?.completions[ids[slot].uuidString]
}

@Test func tickingTodaysRowFirstRecordsTheItemItShowed() throws {
    var d = reviewerScenario()
    #expect(itemTitles(d, slot: 2) == ["Item 0", "Item 1"])           // yesterday's row, then today's row
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-17")?.itemIndex == 1)
    #expect(d.goals[2].position == 2)
    #expect(itemTitles(d, slot: 2) == ["Item 0"])                      // yesterday's row still shows t0
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-16")?.itemIndex == 0)
    #expect(d.goals[2].position == 2)
}

@Test func tickingYesterdaysRowFirstKeepsTodaysItem() throws {
    var d = reviewerScenario()
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-16")?.itemIndex == 0)
    #expect(itemTitles(d, slot: 2) == ["Item 1"])                      // today's row is the same item as before
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-17")?.itemIndex == 1)
    #expect(d.goals[2].position == 2)
}

@Test func listEndingBetweenTheTwoRowsStaysConsistent() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0, 1]
    var d = Fixtures.make(own: own, firstUse: "2026-11-06", lists: [2: items(2)])
    d.goals[2].position = 1                                            // yesterday's row: item 1, today's row: none
    #expect(itemTitles(d, slot: 2) == ["Item 1", nil])
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-17")?.itemIndex == nil)
    #expect(d.goals[2].position == 1)
    #expect(itemTitles(d, slot: 2) == ["Item 1"])
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")
    #expect(completion(d, slot: 2, onDay: "2026-11-16")?.itemIndex == 1)
    #expect(d.goals[2].position == 2)
}

@Test func undoOfTodaysRowAboveAnOpenCatchUpRowFreesBothItems() throws {
    var d = reviewerScenario()
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    try undo(&d, 2, "2026-11-17", today: "2026-11-17")
    #expect(d.goals[2].position == 0)
    #expect(itemTitles(d, slot: 2) == ["Item 0", "Item 1"])
}

@Test func undoWorksInEitherOrderAfterBothRowsAreDone() throws {
    var d = reviewerScenario()
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")
    var a = d
    try undo(&a, 2, "2026-11-16", today: "2026-11-17")                 // undo the lower item
    #expect(a.goals[2].position == 2)
    #expect(itemTitles(a, slot: 2) == ["Item 0"])                      // yesterday's row shows t0 again
    var b = d
    try undo(&b, 2, "2026-11-17", today: "2026-11-17")                 // undo the higher item
    #expect(b.goals[2].position == 1)
    #expect(itemTitles(b, slot: 2) == ["Item 1"])                      // today's row shows t1 again
}

@Test func canUndoGivesAReasonWhenRefused() throws {
    var d = reviewerScenario()
    #expect(Actions.canUndo(d, goalID: ids[2], forDay: day("2026-11-17"), today: day("2026-11-17"), calendar: utc)
            == .refused("Nothing to undo."))
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    #expect(Actions.canUndo(d, goalID: ids[2], forDay: day("2026-11-17"), today: day("2026-11-17"), calendar: utc) == .allowed)
    // A mark from an earlier day (slot 0 was done on 16 Nov, as its own day).
    #expect(Actions.canUndo(d, goalID: ids[0], forDay: day("2026-11-16"), today: day("2026-11-17"), calendar: utc)
            == .refused("Only marks made today can be undone."))
    // The list was imported again after the mark: position no longer covers the mark.
    d.goals[2].replaceList(items(5), keepPosition: false)
    #expect(Actions.canUndo(d, goalID: ids[2], forDay: day("2026-11-17"), today: day("2026-11-17"), calendar: utc)
            == .refused("The list was imported again after this mark."))
    #expect(throws: ActionError.notAllowed) { try undo(&d, 2, "2026-11-17", today: "2026-11-17") }
}


// MARK: Undo and list re-import (second review)

private func reimport(_ d: inout AppData, slot: Int, count: Int, keep: Bool) {
    d.goals[slot].replaceList(items(count), keepPosition: keep)
}
private let today17 = day("2026-11-17"), yesterday16 = day("2026-11-16")

/// Reviewer input A: slot 2 has 2 items at position 1; yesterday's row is owed.
@Test func reimportBetweenTheTwoMarksThenUndoTodayCannotBreakPosition() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0, 1]
    var d = Fixtures.make(own: own, firstUse: "2026-11-06", lists: [2: items(2)])
    d.goals[2].position = 1
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")                 // yesterday's row: item 1, position 2
    reimport(&d, slot: 2, count: 1, keep: false)                       // new list, position 0
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")                 // today's row: item 0 of the new list
    #expect(d.isValid)
    // The partner mark (yesterday's) belongs to the old list, so undo must be refused.
    let check = Actions.canUndo(d, goalID: ids[2], forDay: today17, today: today17, calendar: utc)
    #expect(check == .refused("The list was imported again after this mark."))
    #expect(throws: ActionError.notAllowed) { try undo(&d, 2, "2026-11-17", today: "2026-11-17") }
    #expect(d.isValid)
}

/// Reviewer input B: position 4 in 10 items; both rows ticked; shorter list imported with keepPosition.
@Test func shorterReimportKeepingPositionThenUndoYesterdayStaysValid() throws {
    var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = [0, 1]
    var d = Fixtures.make(own: own, firstUse: "2026-11-06", lists: [2: items(10)])
    d.goals[2].position = 4
    try mark(&d, 2, "2026-11-16", today: "2026-11-17")
    try mark(&d, 2, "2026-11-17", today: "2026-11-17")
    reimport(&d, slot: 2, count: 5, keep: true)
    #expect(d.isValid)
    #expect(Actions.canUndo(d, goalID: ids[2], forDay: yesterday16, today: today17, calendar: utc)
            == .refused("The list was imported again after this mark."))
    #expect(throws: ActionError.notAllowed) { try undo(&d, 2, "2026-11-16", today: "2026-11-17") }
    #expect(d.isValid)
}

@Test func undoAlwaysLeavesPositionInsideTheList() throws {
    // Even if a mark and the position disagree, undo must clamp.
    var d = Fixtures.make(own: ["2026-11-17": [0]], firstUse: "2026-11-17", lists: [0: items(3)])
    d.days["2026-11-17"]?.completions[ids[0].uuidString] = Completion(itemIndex: 2, doneOn: "2026-11-17", listVersion: 0)
    d.goals[0].position = 3
    try undo(&d, 0, "2026-11-17", today: "2026-11-17")
    #expect(d.goals[0].position == 2)
    #expect(d.isValid)
}

/// Brute force: list sizes 0...6, every start position, every owed state, one re-import at any point.
@Test func bruteForceMarkUndoAndOneReimportKeepDataValid() {
    var visited = 0
    for n in 0...6 { for p in 0...n { for yesterday in [Set<Int>([0, 1]), [0, 1, 2]] as [Set<Int>] {
        var own = full("2026-11-06", "2026-11-15"); own["2026-11-16"] = yesterday
        var d0 = Fixtures.make(own: own, firstUse: "2026-11-06", lists: [2: items(n)])
        d0.goals[2].position = p
        var queue: [(AppData, Bool)] = [(d0, false)]
        var seen = Set<String>()
        func keyOf(_ d: AppData, _ imp: Bool) -> String {
            let e = JSONEncoder(); e.outputFormatting = .sortedKeys
            return String(decoding: (try? e.encode(d)) ?? Data(), as: UTF8.self) + "\(imp)"
        }
        var head = 0
        while head < queue.count {
            let (d, imported) = queue[head]; head += 1
            visited += 1
            #expect(d.isValid, "invalid after ops: n=\(n) p=\(p) y=\(yesterday.sorted()) pos=\(d.goals[2].position)/\(d.goals[2].items.count)")
            var next: [(AppData, Bool)] = []
            for y in [true, false] {
                var a = d; if (try? Actions.markDone(&a, goalID: ids[2], forDay: y ? yesterday16 : today17, today: today17, calendar: utc)) != nil { next.append((a, imported)) }
                var b = d; if (try? Actions.undo(&b, goalID: ids[2], forDay: y ? yesterday16 : today17, today: today17, calendar: utc)) != nil { next.append((b, imported)) }
            }
            if !imported {
                for m in Set([max(0, n - 2), max(0, n - 1), n, n + 1]) { for keep in [true, false] {
                    var c = d; reimport(&c, slot: 2, count: m, keep: keep); next.append((c, true))
                } }
            }
            for (c, imp) in next where seen.insert(keyOf(c, imp)).inserted { queue.append((c, imp)) }
        }
    } } }
    #expect(visited > 500)
}
