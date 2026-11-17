import SwiftUI
import AppKit
import TodoTargetCore

/// What the panel footer menu can trigger. Wired in `AppDelegate`.
struct PanelActions {
    var openSettings: () -> Void = {}
    var importList: () -> Void = {}
    var backupNow: (() -> Void)? = nil   // nil disables the menu line
    var quit: () -> Void = { MainActor.assumeIsolated { NSApp.terminate(nil) } }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var backup: BackupCoordinator
    let actions: PanelActions

    private var streak: StreakState { model.streak }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HeatmapView(heatmap: HeatmapModel.build(data: model.data, today: model.today,
                                                    period: model.heatmapPeriod,
                                                    calendar: model.calendar, locale: .current))
            Divider()
            goalsList
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 600)
    }

    // MARK: Header

    private var header: some View {
        let hm = HeatmapModel.build(data: model.data, today: model.today, period: model.heatmapPeriod,
                                    calendar: model.calendar, locale: .current)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let risk = streak.atRisk {
                    Text("Streak at risk: \(risk) \(risk == 1 ? "day" : "days")")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    Text("Finish yesterday's work today to keep it.").font(.callout)
                } else {
                    Text("Current streak: \(streak.current) \(streak.current == 1 ? "day" : "days")")
                        .font(.title3.bold())
                }
                Text("Active days: \(hm.activeDays)   Max streak: \(hm.maxStreak)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            periodPicker(years: hm.availableYears)
        }
    }

    private func periodPicker(years: [Int]) -> some View {
        let binding = Binding<Int>(
            get: { if case .year(let y) = model.heatmapPeriod { return y } else { return 0 } },
            set: { model.heatmapPeriod = $0 == 0 ? .current : .year($0) })
        return Picker("Period", selection: binding) {
            Text("Current").tag(0)
            ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
        }
        .labelsHidden()
        .frame(width: 110)
    }

    // MARK: Goals

    private var yesterdayRows: [RowModel] {
        guard let cu = streak.catchUp else { return [] }
        let tasks = model.owedTasks
        var rows: [RowModel] = []
        for (slot, goal) in model.data.goals.enumerated() {
            if cu.owedGoalIDs.contains(goal.id) {
                if let t = tasks.first(where: { $0.isCatchUp && $0.goalID == goal.id }) {
                    rows.append(RowModel(slot: slot, goal: goal, forDay: cu.day, task: t, completion: nil))
                }
            } else if let c = model.data.days[cu.day.string]?.completions[goal.id.uuidString],
                      c.doneOn == model.today.string {
                rows.append(RowModel(slot: slot, goal: goal, forDay: cu.day, task: nil, completion: c))
            }
        }
        return rows
    }

    private var todayRows: [RowModel] {
        let tasks = model.owedTasks
        return model.data.goals.enumerated().map { slot, goal in
            if let c = model.data.days[model.today.string]?.completions[goal.id.uuidString],
               c.doneOn == model.today.string {
                return RowModel(slot: slot, goal: goal, forDay: model.today, task: nil, completion: c)
            }
            let t = tasks.first(where: { !$0.isCatchUp && $0.goalID == goal.id })
            return RowModel(slot: slot, goal: goal, forDay: model.today, task: t, completion: nil)
        }
    }

    private var goalsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            let yRows = yesterdayRows
            if !yRows.isEmpty {
                Text("Yesterday").font(.headline)
                ForEach(yRows, id: \.goal.id) { row in goalRow(row) }
                Text("Today").font(.headline).padding(.top, 4)
            } else {
                Text("Today").font(.headline)
            }
            ForEach(todayRows, id: \.goal.id) { row in goalRow(row) }
        }
    }

    private func goalRow(_ row: RowModel) -> some View {
        HStack(spacing: 10) {
            Text("\(row.slot + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.goal.name).font(.body.weight(.medium))
                if let line = row.detail { Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if row.completion != nil {
                Button("Undo") { model.undo(goalID: row.goal.id, forDay: row.forDay) }
                    .buttonStyle(.link)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.large)
            } else {
                Button {
                    model.markDone(goalID: row.goal.id, forDay: row.forDay)
                } label: { Image(systemName: "circle").imageScale(.large) }
                .buttonStyle(.borderless)
                .help("Mark \(row.goal.name) done")
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let err = model.saveError {
                Text(err).font(.caption).foregroundStyle(.secondary)
            } else if !backup.status.isEmpty {
                Text(backup.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Menu") {
                if let t = model.nextTask {
                    Button("Mark \(model.data.goals[t.slot].name) done") {
                        model.markDone(goalID: t.goalID, forDay: t.forDay)
                    }
                } else {
                    Button("All goals done") {}.disabled(true)
                }
                Divider()
                Button("Settings…") { actions.openSettings() }
                Button("Import list…") { actions.importList() }
                Button("Backup now") { actions.backupNow?() }.disabled(actions.backupNow == nil)
                Divider()
                Button("Quit") { actions.quit() }
            }
            .fixedSize()
        }
    }
}

private struct RowModel {
    var slot: Int
    var goal: Goal
    var forDay: DayKey
    /// The open task for this row (item comes from here, never from `goal.position`).
    var task: OwedTask?
    /// The completion for a done row.
    var completion: Completion?

    var detail: String? {
        if let c = completion {
            if let i = c.itemIndex, goal.items.indices.contains(i) {
                let it = goal.items[i]
                return it.group.isEmpty ? it.title : "\(it.group) · \(it.title)"
            }
            return nil
        }
        if let it = task?.item { return it.group.isEmpty ? it.title : "\(it.group) · \(it.title)" }
        return goal.items.isEmpty ? nil : "List complete"
    }
}
