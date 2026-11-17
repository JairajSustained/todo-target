import Foundation

public enum ActionError: Error, Equatable, Sendable {
    case notAllowed
    case unknownGoal
}

public enum Actions {
    /// Marks a goal done for `forDay`. Allowed for today, or for yesterday when
    /// catch-up is open and the goal is owed. A repeat mark changes nothing (C5).
    public static func markDone(_ data: inout AppData, goalID: UUID, forDay: DayKey,
                                today: DayKey, calendar: Calendar) throws {
        guard let gi = data.goals.firstIndex(where: { $0.id == goalID }) else { throw ActionError.unknownGoal }

        // C5: a repeat mark is a silent no-op. This check runs before the permission check.
        let key = goalID.uuidString
        if data.days[forDay.string]?.completions[key] != nil { return }

        var allowed = forDay == today
        if !allowed, forDay == today.adding(days: -1, calendar: calendar) {
            let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
            if let cu = state.catchUp, cu.day == forDay, cu.owedGoalIDs.contains(goalID) { allowed = true }
        }
        guard allowed else { throw ActionError.notAllowed }

        let goal = data.goals[gi]
        let index: Int? = goal.position < goal.items.count ? goal.position : nil
        var record = data.days[forDay.string] ?? DayRecord()
        record.completions[key] = Completion(itemIndex: index, doneOn: today.string)
        data.days[forDay.string] = record
        if index != nil { data.goals[gi].position += 1 }
        if data.firstUseDay == nil { data.firstUseDay = today.string }
    }

    /// Removes a completion made today, if it is the latest one of its goal.
    public static func undo(_ data: inout AppData, goalID: UUID, forDay: DayKey,
                            today: DayKey, calendar: Calendar) throws {
        guard let gi = data.goals.firstIndex(where: { $0.id == goalID }) else { throw ActionError.unknownGoal }
        let key = goalID.uuidString
        guard var record = data.days[forDay.string], let c = record.completions[key],
              c.doneOn == today.string else { throw ActionError.notAllowed }
        if let idx = c.itemIndex, idx != data.goals[gi].position - 1 { throw ActionError.notAllowed }

        record.completions[key] = nil
        data.days[forDay.string] = record.completions.isEmpty ? nil : record
        if let idx = c.itemIndex { data.goals[gi].position = idx }
    }
}
