import Foundation
@testable import TodoTargetCore

enum Fixtures {
    static let goalIDs: [UUID] = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
    ]

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func day(_ s: String) -> DayKey { DayKey(string: s)! }

    /// `own`: day -> slots done on that day. `recovered`: day -> slots whose
    /// completion for that day has `doneOn` equal to the next day.
    static func make(
        own: [String: Set<Int>] = [:],
        recovered: [String: Set<Int>] = [:],
        firstUse: String,
        lists: [Int: [ListItem]] = [:],
        calendar: Calendar = utc
    ) -> AppData {
        var data = AppData.pristine()
        for i in 0..<3 {
            data.goals[i].id = goalIDs[i]
            data.goals[i].items = lists[i] ?? []
        }
        data.firstUseDay = firstUse
        for (d, slots) in own {
            var rec = data.days[d] ?? DayRecord(completions: [:])
            for s in slots {
                rec.completions[goalIDs[s].uuidString] = Completion(itemIndex: nil, doneOn: d)
            }
            data.days[d] = rec
        }
        for (d, slots) in recovered {
            let next = Fixtures.day(d).adding(days: 1, calendar: calendar).string
            var rec = data.days[d] ?? DayRecord(completions: [:])
            for s in slots {
                rec.completions[goalIDs[s].uuidString] = Completion(itemIndex: nil, doneOn: next)
            }
            data.days[d] = rec
        }
        return data
    }
}
