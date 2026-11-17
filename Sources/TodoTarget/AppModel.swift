import Foundation
import Combine
import TodoTargetCore

/// The one source of truth for the UI. Every mutation saves, then calls `onChange`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data: AppData
    @Published private(set) var today: DayKey
    @Published var heatmapPeriod: HeatmapPeriod = .current
    /// Set when the last save failed. Shown quietly; never an alert.
    @Published private(set) var saveError: String?
    /// Name of the file `data.json` was moved to when it was damaged at start.
    /// While set, local data is not trusted: it must never replace a backup unasked.
    @Published private(set) var recoveredFile: String?
    /// Full path of the moved-aside file (for the one-time alert).
    let recoveredFileURL: URL?

    var onChange: (() -> Void)?

    let calendar: Calendar
    private let store: DataStore
    private let tracker: DayTracker

    init(store: DataStore, clock: Clock, calendar: Calendar) {
        self.store = store
        self.calendar = calendar
        self.tracker = DayTracker(clock: clock, calendar: calendar)
        let report = store.loadReport()
        self.data = report.data
        self.recoveredFileURL = report.quarantinedFile
        self.recoveredFile = report.quarantinedFile?.lastPathComponent
        self.today = tracker.today
    }

    var recoveredFromDamage: Bool { recoveredFile != nil }

    /// The user chose what to do about the damaged file (restore, or keep this Mac's data).
    func clearRecoveryFlag() { recoveredFile = nil }

    var streak: StreakState { StreakEngine.evaluate(data: data, today: today, calendar: calendar) }

    var nextTask: OwedTask? { Planner.nextTask(data: data, today: today, calendar: calendar) }

    var owedTasks: [OwedTask] { Planner.owedTasks(data: data, today: today, calendar: calendar) }

    var progress: (done: Int, total: Int) { Planner.progress(data: data, today: today, calendar: calendar) }

    /// Call on midnight timer, wake, and day-changed events.
    func refreshToday() {
        if tracker.refresh() { today = tracker.today }
    }

    func markDone(goalID: UUID, forDay: DayKey) {
        var copy = data
        do { try Actions.markDone(&copy, goalID: goalID, forDay: forDay, today: today, calendar: calendar) } catch { return }
        commit(copy)
    }

    func undo(goalID: UUID, forDay: DayKey) {
        var copy = data
        do { try Actions.undo(&copy, goalID: goalID, forDay: forDay, today: today, calendar: calendar) } catch { return }
        commit(copy)
    }

    func importList(goalID: UUID, csv: String, keepPosition: Bool) throws {
        let items = try CSVImporter.parse(csv)
        guard let i = data.goals.firstIndex(where: { $0.id == goalID }) else { return }
        var copy = data
        copy.goals[i].replaceList(items, keepPosition: keepPosition)
        commit(copy)
    }

    /// `names[i]` is the new name of the goal `order[i]`. `order` is the new priority order.
    /// An empty name keeps the old one. Ignored unless `order` is a permutation of the goal IDs.
    func updateGoals(names: [String], order: [UUID]) {
        guard names.count == order.count, Set(order) == Set(data.goals.map(\.id)), order.count == data.goals.count else { return }
        var copy = data
        var reordered: [Goal] = []
        for (n, id) in zip(names, order) {
            guard var g = copy.goals.first(where: { $0.id == id }) else { return }
            let trimmed = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { g.name = trimmed }
            reordered.append(g)
        }
        copy.goals = reordered
        commit(copy)
    }

    func updateSettings(_ change: (inout Settings) -> Void) {
        var copy = data
        change(&copy.settings)
        commit(copy)
    }

    func replaceData(_ new: AppData) { commit(new) }

    private func commit(_ new: AppData) {
        guard new != data else { return }
        data = new
        do { try store.save(new); saveError = nil } catch { saveError = "Could not save: \(error.localizedDescription)" }
        onChange?()
    }
}
