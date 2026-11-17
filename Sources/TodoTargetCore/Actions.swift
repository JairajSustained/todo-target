import Foundation

public enum ActionError: Error, Equatable, Sendable {
    case notAllowed
    case unknownGoal
}

/// The answer of `Actions.canUndo`. A refusal carries a short reason for the UI.
public enum UndoCheck: Equatable, Sendable {
    case allowed
    case refused(String)
}

public enum Actions {
    /// The list item a row shows, and so the item a tick on that row records (C27).
    ///
    /// - A goal also owed from yesterday has two rows. Yesterday's row comes first.
    ///   Today's row shows the item after it: `position + 1`.
    /// - If today's row is ticked first, it records `position + 1` and moves `position` past it.
    ///   Yesterday's row then still shows the item below it: today's `itemIndex - 1`.
    /// - A row past the end of the list has no item.
    static func rowItemIndex(_ data: AppData, goalIndex gi: Int, forDay: DayKey, today: DayKey,
                             state: StreakState) -> Int? {
        let goal = data.goals[gi]
        let count = goal.items.count
        let pos = min(max(goal.position, 0), count)
        let owedFromYesterday = state.catchUp?.owedGoalIDs.contains(goal.id) ?? false

        let idx: Int
        if forDay == today {
            idx = owedFromYesterday ? pos + 1 : pos
        } else if let t = data.days[today.string]?.completions[goal.id.uuidString],
                  t.doneOn == today.string, let ti = t.itemIndex, ti >= 1 {
            idx = ti - 1          // today's row was ticked first: yesterday's item is the one below it
        } else {
            idx = pos
        }
        return idx < count ? idx : nil
    }

    /// Marks a goal done for `forDay`. Allowed for today, or for yesterday when
    /// catch-up is open and the goal is owed. A repeat mark changes nothing (C5).
    public static func markDone(_ data: inout AppData, goalID: UUID, forDay: DayKey,
                                today: DayKey, calendar: Calendar) throws {
        guard let gi = data.goals.firstIndex(where: { $0.id == goalID }) else { throw ActionError.unknownGoal }

        // C5: a repeat mark is a silent no-op. This check runs before the permission check.
        let key = goalID.uuidString
        if data.days[forDay.string]?.completions[key] != nil { return }

        let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
        var allowed = forDay == today
        if !allowed, forDay == today.adding(days: -1, calendar: calendar) {
            if let cu = state.catchUp, cu.day == forDay, cu.owedGoalIDs.contains(goalID) { allowed = true }
        }
        guard allowed else { throw ActionError.notAllowed }

        // Record the item this row showed. Keep the position inside its list, even if the stored value is not.
        let index = rowItemIndex(data, goalIndex: gi, forDay: forDay, today: today, state: state)
        let count = data.goals[gi].items.count
        let pos = min(max(data.goals[gi].position, 0), count)
        data.goals[gi].position = pos
        var record = data.days[forDay.string] ?? DayRecord()
        record.completions[key] = Completion(itemIndex: index, doneOn: today.string)
        data.days[forDay.string] = record
        if let index { data.goals[gi].position = max(pos, index + 1) }
        if data.firstUseDay == nil { data.firstUseDay = today.string }
    }

    /// Says whether `undo` would work, and if not, why in a few words.
    public static func canUndo(_ data: AppData, goalID: UUID, forDay: DayKey,
                               today: DayKey, calendar: Calendar) -> UndoCheck {
        guard let goal = data.goals.first(where: { $0.id == goalID }) else { return .refused("Unknown goal.") }
        guard let c = data.days[forDay.string]?.completions[goalID.uuidString] else {
            return .refused("Nothing to undo.")
        }
        guard c.doneOn == today.string else { return .refused("Only marks made today can be undone.") }
        if let i = c.itemIndex, i > goal.position - 1 {
            return .refused("The list was imported again after this mark.")
        }
        return .allowed
    }

    /// Removes a completion made today and puts the list position back (see `rowItemIndex`).
    public static func undo(_ data: inout AppData, goalID: UUID, forDay: DayKey,
                            today: DayKey, calendar: Calendar) throws {
        guard let gi = data.goals.firstIndex(where: { $0.id == goalID }) else { throw ActionError.unknownGoal }
        guard canUndo(data, goalID: goalID, forDay: forDay, today: today, calendar: calendar) == .allowed,
              var record = data.days[forDay.string], let c = record.completions[goalID.uuidString]
        else { throw ActionError.notAllowed }

        let key = goalID.uuidString
        if let i = c.itemIndex {
            let state = StreakEngine.evaluate(data: data, today: today, calendar: calendar)
            let owedFromYesterday = state.catchUp?.owedGoalIDs.contains(goalID) ?? false
            // The goal's other mark made today (today's row and yesterday's row can both exist).
            let yesterday = today.adding(days: -1, calendar: calendar)
            let otherIndex = [today, yesterday].filter { $0 != forDay }.compactMap { day -> Int? in
                guard let o = data.days[day.string]?.completions[key], o.doneOn == today.string else { return nil }
                return o.itemIndex
            }.first
            if let o = otherIndex {
                data.goals[gi].position = o + 1
            } else if forDay == today && owedFromYesterday {
                data.goals[gi].position = max(i - 1, 0)   // today's row sat one above yesterday's open row
            } else {
                data.goals[gi].position = i
            }
        }
        record.completions[key] = nil
        data.days[forDay.string] = record.completions.isEmpty ? nil : record
    }
}
