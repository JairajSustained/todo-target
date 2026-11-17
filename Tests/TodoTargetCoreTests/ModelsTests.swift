import Testing
import Foundation
@testable import TodoTargetCore

@Test func dayKeyRoundTrip() { #expect(DayKey(string: "2026-11-17")?.string == "2026-11-17") }
@Test func dayKeyRejectsBadStrings() { #expect(DayKey(string: "2026-13-01") == nil); #expect(DayKey(string: "x") == nil) }
@Test func addingDaysCrossesMonthAndYear() {
    #expect(Fixtures.day("2025-12-31").adding(days: 1, calendar: Fixtures.utc).string == "2026-01-01")
    #expect(Fixtures.day("2026-03-01").adding(days: -1, calendar: Fixtures.utc).string == "2026-02-28")
}
@Test func appDataJSONRoundTrip() throws {
    let d = AppData.pristine()
    #expect(try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d)) == d)
}
@Test func pristineHasThreeGoals() { #expect(AppData.pristine().goals.count == 3); #expect(AppData.pristine().isPristine) }
@Test func renamedGoalOrImportedListIsNotPristine() {
    var d = AppData.pristine(); d.goals[0].name = "DSA"; #expect(!d.isPristine)
}

@Test func validDataPassesValidation() {
    #expect(AppData.pristine().isValid)
    var d = AppData.pristine(); d.goals[0].items = [ListItem(group: "g", title: "t")]; d.goals[0].position = 1
    #expect(d.isValid)  // position == items.count is allowed (list complete)
}

@Test func invalidDataFailsValidation() {
    var wrongCount = AppData.pristine(); wrongCount.goals.removeLast()
    #expect(!wrongCount.isValid)
    var tooMany = AppData.pristine(); tooMany.goals.append(Goal(name: "x"))
    #expect(!tooMany.isValid)
    var dupes = AppData.pristine(); dupes.goals[1].id = dupes.goals[0].id
    #expect(!dupes.isValid)
    var high = AppData.pristine(); high.goals[0].position = 1
    #expect(!high.isValid)  // no items, so only 0 is valid
    var negative = AppData.pristine(); negative.goals[0].position = -1
    #expect(!negative.isValid)
    var schema0 = AppData.pristine(); schema0.schemaVersion = 0
    #expect(!schema0.isValid)
    var schema2 = AppData.pristine(); schema2.schemaVersion = 2
    #expect(!schema2.isValid)
}
