import Foundation

public enum HeatmapPeriod: Equatable, Sendable {
    case current
    case year(Int)
}

public struct HeatmapCell: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case beforeStart, future, day(level: Int)
    }
    public var day: DayKey
    public var kind: Kind
    public var isToday: Bool
    public var savedByCatchUp: Bool
    public var tooltip: String
}

public struct HeatmapModel: Equatable, Sendable {
    /// Weeks, oldest first. Each has 7 rows. `nil` is padding outside the period.
    public var columns: [[HeatmapCell?]]
    public var monthLabels: [(column: Int, name: String)]
    public var activeDays: Int
    public var maxStreak: Int
    public var availableYears: [Int]

    public static func == (a: HeatmapModel, b: HeatmapModel) -> Bool {
        a.columns == b.columns && a.activeDays == b.activeDays && a.maxStreak == b.maxStreak
            && a.availableYears == b.availableYears
            && a.monthLabels.map(\.column) == b.monthLabels.map(\.column)
            && a.monthLabels.map(\.name) == b.monthLabels.map(\.name)
    }

    public static func build(data: AppData, today: DayKey, period: HeatmapPeriod,
                             calendar: Calendar, locale: Locale) -> HeatmapModel {
        let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
        // With no marks yet, the app starts today.
        let firstUse = data.firstUseDay.flatMap { DayKey(string: $0) } ?? today

        // Period bounds (inclusive).
        let from: DayKey
        let to: DayKey
        switch period {
        case .current:
            from = today.adding(days: -364, calendar: calendar)
            to = today
        case .year(let y):
            from = DayKey(string: String(format: "%04d-01-01", y)) ?? today
            to = DayKey(string: String(format: "%04d-12-31", y)) ?? today
        }

        func row(_ d: DayKey) -> Int {
            let wd = calendar.component(.weekday, from: d.date(calendar: calendar))
            return (wd - calendar.firstWeekday + 7) % 7
        }
        let gridStart = from.adding(days: -row(from), calendar: calendar)
        let gridEnd = to.adding(days: 6 - row(to), calendar: calendar)

        // The current view shows whole weeks: days after today are `.future` cells, not padding.
        let isCurrent = period == .current
        let firstShown = isCurrent ? gridStart : from
        let lastShown = isCurrent ? gridEnd : to

        let tipFormatter = DateFormatter()
        tipFormatter.locale = locale
        tipFormatter.calendar = calendar
        tipFormatter.timeZone = calendar.timeZone
        tipFormatter.dateFormat = "EEE d MMM yyyy"
        let monthFormatter = DateFormatter()
        monthFormatter.locale = locale
        monthFormatter.calendar = calendar
        monthFormatter.timeZone = calendar.timeZone
        monthFormatter.dateFormat = "MMM"

        let goalCount = data.goals.count

        func makeCell(_ d: DayKey) -> HeatmapCell {
            let dateText = tipFormatter.string(from: d.date(calendar: calendar))
            let kind: HeatmapCell.Kind
            var level = 0
            if d > today {
                kind = .future
            } else if d < firstUse {
                kind = .beforeStart
            } else {
                level = StreakEngine.completionCount(data, d)
                kind = .day(level: level)
            }
            let hasRecovered = data.days[d.string]?.completions.values.contains { $0.doneOn != d.string } ?? false
            let saved = state.activeDays.contains(d) && hasRecovered
            var tip = dateText
            if case .day = kind {
                tip += ": \(level) of \(goalCount)"
                if saved { tip += " (saved by catch-up)" }
            }
            return HeatmapCell(day: d, kind: kind, isToday: d == today, savedByCatchUp: saved, tooltip: tip)
        }

        var columns: [[HeatmapCell?]] = []
        var labels: [(column: Int, name: String)] = []
        var active = 0
        var start = gridStart
        while start <= gridEnd {
            var col: [HeatmapCell?] = []
            for r in 0..<7 {
                let d = start.adding(days: r, calendar: calendar)
                if d < firstShown || d > lastShown {
                    col.append(nil)
                    continue
                }
                let c = makeCell(d)
                if state.activeDays.contains(d) { active += 1 }
                if d.day == 1 {
                    labels.append((column: columns.count, name: monthFormatter.string(from: d.date(calendar: calendar))))
                }
                col.append(c)
            }
            columns.append(col)
            start = start.adding(days: 7, calendar: calendar)
        }

        let years = Set(data.days.filter { !$0.value.completions.isEmpty }.keys.compactMap { DayKey(string: $0)?.year })
        return HeatmapModel(columns: columns, monthLabels: labels, activeDays: active,
                            maxStreak: state.best, availableYears: years.sorted(by: >))
    }
}
