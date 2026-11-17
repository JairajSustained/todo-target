import AppKit
import SwiftUI
import TodoTargetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private var midnightTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: DataStore(directory: DataStore.defaultDirectory()),
                         clock: SystemClock(), calendar: .current)
        popover.behavior = .transient
        statusController = StatusItemController(model: model) { [weak self] button in
            self?.togglePanel(relativeTo: button)
        }
        wireDayRefresh()
    }

    private func togglePanel(relativeTo button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        if popover.contentViewController == nil {
            // Settings, import and backup arrive in later tasks; their lines do nothing yet.
            let host = NSHostingController(rootView: PanelView(model: model, actions: PanelActions()))
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Day refresh: midnight timer, wake, day-changed.

    private func wireDayRefresh() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dayMayHaveChanged() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dayMayHaveChanged() }
        }
        scheduleMidnightTimer()
    }

    private func dayMayHaveChanged() {
        model.refreshToday()
        scheduleMidnightTimer()
    }

    private func scheduleMidnightTimer() {
        midnightTimer?.invalidate()
        let fire = DayRollover.nextMidnight(after: Date(), calendar: .current)
        let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dayMayHaveChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }
}
