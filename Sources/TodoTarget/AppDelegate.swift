import AppKit
import SwiftUI
import TodoTargetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    private var midnightTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: DataStore(directory: DataStore.defaultDirectory()),
                         clock: SystemClock(), calendar: .current)
        popover.behavior = .transient
        statusController = StatusItemController(model: model) { [weak self] button in
            self?.togglePanel(relativeTo: button)
        }
        wireDayRefresh()
        applyLaunchAtLogin()
        if model.data.isPristine { openSettings() }
    }

    /// Opens (or raises) the Settings window.
    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "todo-target Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Applies the saved "Start at login" choice. Skipped outside a `.app` bundle.
    private func applyLaunchAtLogin() {
        guard LaunchAtLogin.isBundled else { return }
        try? LaunchAtLogin.set(model.data.settings.launchAtLogin)
    }

    private func togglePanel(relativeTo button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        if popover.contentViewController == nil {
            // "Import list…" opens Settings, where each goal has its own import button.
            // Backup arrives in a later task; its line stays disabled.
            var actions = PanelActions()
            actions.openSettings = { [weak self] in self?.openSettings() }
            actions.importList = { [weak self] in self?.openSettings() }
            let host = NSHostingController(rootView: PanelView(model: model, actions: actions))
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
