import Foundation

public struct OwedTask: Equatable, Sendable {
    public var goalID: UUID
    public var slot: Int
    public var forDay: DayKey
    public var isCatchUp: Bool
    public var item: ListItem?
}

public enum Planner {
    /// Catch-up tasks first (priority order), then today's open goals (priority order).
    public static func owedTasks(data: AppData, today: DayKey, calendar: Calendar) -> [OwedTask] {
        let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
        var tasks: [OwedTask] = []
        var taken: [UUID: Int] = [:]

        func add(_ i: Int, forDay: DayKey, isCatchUp: Bool) {
            let g = data.goals[i]
            let k = taken[g.id, default: 0]
            taken[g.id] = k + 1
            let idx = min(max(g.position, 0), g.items.count) + k
            let item = idx < g.items.count ? g.items[idx] : nil
            tasks.append(OwedTask(goalID: g.id, slot: i, forDay: forDay, isCatchUp: isCatchUp, item: item))
        }

        if let cu = state.catchUp {
            for i in data.goals.indices where cu.owedGoalIDs.contains(data.goals[i].id) {
                add(i, forDay: cu.day, isCatchUp: true)
            }
        }
        let rec = data.days[today.string]
        for i in data.goals.indices {
            let c = rec?.completions[data.goals[i].id.uuidString]
            if c?.doneOn != today.string { add(i, forDay: today, isCatchUp: false) }
        }
        return tasks
    }

    public static func nextTask(data: AppData, today: DayKey, calendar: Calendar) -> OwedTask? {
        owedTasks(data: data, today: today, calendar: calendar).first
    }

    public static func progress(data: AppData, today: DayKey, calendar: Calendar) -> (done: Int, total: Int) {
        let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
        let ownToday = StreakEngine.ownCount(data, today)
        guard let cu = state.catchUp else { return (ownToday, data.goals.count) }
        let ownY = StreakEngine.ownCount(data, cu.day)
        let recovered = StreakEngine.completionCount(data, cu.day) - ownY
        return (ownToday + recovered, data.goals.count + (data.goals.count - ownY))
    }

    public static func iconLevel(done: Int, total: Int) -> Int {
        if done <= 0 { return 0 }
        if done >= total { return 3 }
        return done * 2 < total ? 1 : 2
    }
}
