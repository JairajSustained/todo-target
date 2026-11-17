import Foundation

public struct CatchUp: Equatable, Sendable {
    /// Yesterday.
    public var day: DayKey
    /// Goals with no completion on that day, in priority order.
    public var owedGoalIDs: [UUID]

    public init(day: DayKey, owedGoalIDs: [UUID]) {
        self.day = day
        self.owedGoalIDs = owedGoalIDs
    }
}

public struct StreakState: Equatable, Sendable {
    public var current: Int
    public var atRisk: Int?
    public var best: Int
    public var activeDays: Set<DayKey>
    public var catchUp: CatchUp?
}

public enum StreakEngine {
    /// Number of goals with a completion on `d` whose `doneOn == d`.
    static func ownCount(_ data: AppData, _ d: DayKey) -> Int {
        guard let rec = data.days[d.string] else { return 0 }
        return data.goals.filter { rec.completions[$0.id.uuidString]?.doneOn == d.string }.count
    }

    /// Number of goals with any completion on `d`.
    static func completionCount(_ data: AppData, _ d: DayKey) -> Int {
        guard let rec = data.days[d.string] else { return 0 }
        return data.goals.filter { rec.completions[$0.id.uuidString] != nil }.count
    }

    public static func evaluate(data: AppData, today: DayKey, calendar: Calendar) -> StreakState {
        let yesterday = today.adding(days: -1, calendar: calendar)
        let goalCount = data.goals.count

        func full(_ d: DayKey) -> Bool { ownCount(data, d) == goalCount }
        func recoveredFull(_ d: DayKey) -> Bool {
            !full(d) && completionCount(data, d) == goalCount
        }

        // Scan from firstUseDay to today.
        var scan: [DayKey] = []
        if let first = data.firstUseDay.flatMap({ DayKey(string: $0) }), first <= today {
            var d = first
            while d <= today {
                scan.append(d)
                d = d.adding(days: 1, calendar: calendar)
            }
        }
        let scanned = Set(scan)

        var counted = Set<DayKey>()
        for d in scan {
            if full(d) {
                counted.insert(d)
            } else if recoveredFull(d) {
                let next = d.adding(days: 1, calendar: calendar)
                if next <= today && full(next) { counted.insert(d) }
            }
        }

        func run(endingAt end: DayKey) -> Int {
            var n = 0
            var d = end
            while counted.contains(d) {
                n += 1
                d = d.adding(days: -1, calendar: calendar)
            }
            return n
        }

        let current: Int
        if counted.contains(today) {
            current = run(endingAt: today)
        } else {
            current = run(endingAt: yesterday)
        }

        // Longest counted run.
        var best = 0
        var running = 0
        for d in scan {
            if counted.contains(d) { running += 1; best = max(best, running) } else { running = 0 }
        }
        best = max(best, current)

        var catchUp: CatchUp?
        var atRisk: Int?
        let beforeYesterday = yesterday.adding(days: -1, calendar: calendar)
        if scanned.contains(yesterday), !counted.contains(yesterday), counted.contains(beforeYesterday) {
            let rec = data.days[yesterday.string]
            let owed = data.goals.filter { rec?.completions[$0.id.uuidString] == nil }.map(\.id)
            catchUp = CatchUp(day: yesterday, owedGoalIDs: owed)
            atRisk = run(endingAt: beforeYesterday)
        }

        return StreakState(current: current, atRisk: atRisk, best: best, activeDays: counted, catchUp: catchUp)
    }
}
