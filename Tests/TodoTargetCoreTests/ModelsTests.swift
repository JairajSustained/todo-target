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
