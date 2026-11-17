import AppKit
import Combine
import TodoTargetCore

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let showPanel: (NSStatusBarButton) -> Void
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, showPanel: @escaping (NSStatusBarButton) -> Void) {
        self.model = model
        self.showPanel = showPanel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Redraw after the model has changed (objectWillChange fires before).
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
        refreshIcon()
    }

    func refreshIcon() {
        let p = model.progress
        let level = Planner.iconLevel(done: p.done, total: p.total)
        let catchUp = model.streak.catchUp != nil
        guard let button = statusItem.button else { return }
        button.image = IconRenderer.image(level: level, doneCount: p.done, catchUp: catchUp)
        button.toolTip = "todo-target: \(p.done) of \(p.total) done"
        button.setAccessibilityLabel("todo-target, \(p.done) of \(p.total) done" + (catchUp ? ", catch-up open" : ""))
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isRight {
            showPanel(sender)
            return
        }
        if let url = model.nextTask?.item?.url, let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        } else {
            showPanel(sender)
        }
    }
}
