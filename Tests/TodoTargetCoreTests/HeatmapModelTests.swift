import Testing
import Foundation
@testable import TodoTargetCore

private let locale = Locale(identifier: "en_US_POSIX")
private func cal(firstWeekday: Int = 1) -> Calendar {
    var c = Fixtures.utc
    c.firstWeekday = firstWeekday
    return c
}
private func day(_ s: String) -> DayKey { Fixtures.day(s) }
private func full(_ a: String, _ b: String) -> [String: Set<Int>] {
    var out: [String: Set<Int>] = [:]
    var d = day(a)
    while d <= day(b) { out[d.string] = [0, 1, 2]; d = d.adding(days: 1, calendar: Fixtures.utc) }
    return out
}
private let today = "2026-11-17"
private func build(_ data: AppData, period: HeatmapPeriod = .current, calendar: Calendar = cal()) -> HeatmapModel {
    HeatmapModel.build(data: data, today: day(today), period: period, calendar: calendar, locale: locale)
}
private func cells(_ m: HeatmapModel) -> [HeatmapCell] { m.columns.flatMap { $0 }.compactMap { $0 } }
private func cell(_ m: HeatmapModel, _ d: String) -> HeatmapCell? { cells(m).first { $0.day == day(d) } }
private let sample = Fixtures.make(own: full("2026-11-06", "2026-11-16"), firstUse: "2026-11-06")

@Test func currentPeriodHasSevenRowsAndAboutFiftyThreeColumns() {
    let m = build(sample)
    #expect(m.columns.allSatisfy { $0.count == 7 }); #expect((52...54).contains(m.columns.count))
}

@Test func todayIsInLastColumnAndOutlined() {
    let c = build(sample).columns.last!.compactMap { $0 }.first { $0.isToday }
    #expect(c?.day == day(today))
}

@Test func daysBeforeFirstUseAreGreyAndFutureEmpty() {
    let m = build(sample)
    #expect(cell(m, "2026-11-05")?.kind == .beforeStart)
    #expect(cell(m, "2026-11-06")?.kind == .day(level: 3))
    #expect(cell(m, "2026-11-18")?.kind == .future)
    #expect(cell(m, "2026-11-17")?.kind == .day(level: 0))
}

@Test func levelEqualsCompletionCount() {
    let m = build(Fixtures.make(own: ["2026-11-12": [0, 1]], firstUse: "2026-11-01"))
    #expect(cell(m, "2026-11-12")?.kind == .day(level: 2))
}

@Test func tooltipFormat() {
    // Spec and plan say "Mon 10 Nov 2026", but 10 Nov 2026 is a Tuesday.
    #expect(cell(build(sample), "2026-11-10")?.tooltip == "Tue 10 Nov 2026: 3 of 3")
}

@Test func savedDayIsMarkedAndTooltipSaysSo() {
    let data = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-17": [0, 1, 2]]) { a, _ in a },
                             recovered: ["2026-11-16": [0, 1, 2]], firstUse: "2026-11-06")
    let m = build(data)
    #expect(cell(m, "2026-11-16")?.savedByCatchUp == true)
    #expect(cell(m, "2026-11-16")?.tooltip == "Mon 16 Nov 2026: 3 of 3 (saved by catch-up)")
    #expect(cell(m, "2026-11-15")?.savedByCatchUp == false)
}

@Test func monthLabelsStartAtMonthBoundaries() {
    let m = build(sample)
    #expect(m.monthLabels.count >= 12)
    for l in m.monthLabels {
        let first = m.columns[l.column].compactMap { $0 }.first { $0.day.day == 1 }
        #expect(first != nil)
    }
    #expect(m.monthLabels.contains { $0.name == "Nov" })
    #expect(m.monthLabels.contains { $0.name == "Jan" })
}

@Test func yearPeriodCoversJanToDec() {
    let m = build(Fixtures.make(own: full("2025-03-01", "2025-03-05"), firstUse: "2025-03-01"), period: .year(2025))
    let real = cells(m)
    #expect(real.first?.day == day("2025-01-01")); #expect(real.last?.day == day("2025-12-31"))
    #expect(real.count == 365)
    #expect(m.columns.allSatisfy { $0.count == 7 })
}

@Test func firstWeekdayMondayShiftsRows() {
    let c = cal(firstWeekday: 2)
    let m = build(sample, calendar: c)
    for col in m.columns {
        if let top = col[0] { #expect(c.component(.weekday, from: top.day.date(calendar: c)) == 2) }
    }
}

@Test func statsMatchEngine() {
    let data = Fixtures.make(own: full("2026-10-01", "2026-10-20").merging(full("2026-11-01", "2026-11-16")) { a, _ in a },
                             firstUse: "2026-10-01")
    let s = StreakEngine.evaluate(data: data, today: day(today), calendar: Fixtures.utc)
    let m = build(data)
    #expect(m.activeDays == s.activeDays.count); #expect(m.activeDays == 36)
    #expect(m.maxStreak == s.best); #expect(m.maxStreak == 20)
}

@Test func availableYearsListsYearsWithDataNewestFirst() {
    let data = Fixtures.make(own: ["2025-12-31": [0], "2026-01-01": [0]], firstUse: "2025-12-31")
    #expect(build(data).availableYears == [2026, 2025])
}

@Test func lateCompletionColoursTheMissedDayOnlyWhenTheDayIsSaved() {
    // 16 Nov: goal 1 on time, goal 2 late. Today is not full, so the day is not saved yet.
    let open = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-16": [0], "2026-11-17": [0, 1]]) { a, _ in a },
                             recovered: ["2026-11-16": [1]], firstUse: "2026-11-06")
    let m = build(open)
    #expect(cell(m, "2026-11-16")?.kind == .day(level: 1))
    #expect(cell(m, "2026-11-16")?.tooltip == "Mon 16 Nov 2026: 1 of 3")
    #expect(cell(m, "2026-11-16")?.savedByCatchUp == false)

    // Every missed goal is late-done but today is still open: counted needs a full today, so still not saved.
    let allLateTodayOpen = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-16": [0]]) { a, _ in a },
                                         recovered: ["2026-11-16": [1, 2]], firstUse: "2026-11-06")
    #expect(cell(build(allLateTodayOpen), "2026-11-16")?.kind == .day(level: 1))

    // Today becomes full: the day is saved, so the late work counts and the square turns green.
    let saved = Fixtures.make(own: full("2026-11-06", "2026-11-15").merging(["2026-11-16": [0], "2026-11-17": [0, 1, 2]]) { a, _ in a },
                              recovered: ["2026-11-16": [1, 2]], firstUse: "2026-11-06")
    #expect(cell(build(saved), "2026-11-16")?.kind == .day(level: 3))
    #expect(cell(build(saved), "2026-11-16")?.savedByCatchUp == true)
}

@Test func lateCompletionsOnAnOldBrokenDayDoNotColourIt() {
    // 10 Nov: goal 1 on time, goals 2 and 3 done late on 11 Nov, but 11 Nov was not full: the day was never saved.
    let data = Fixtures.make(own: ["2026-11-10": [0], "2026-11-11": [0]], recovered: ["2026-11-10": [1, 2]], firstUse: "2026-11-01")
    #expect(cell(build(data), "2026-11-10")?.kind == .day(level: 1))
}
