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
    private(set) var backup: BackupCoordinator!
    private var urlHandler: URLSchemeHandler?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The sign-in link returns here as a todotarget:// Apple event.
        urlHandler = URLSchemeHandler { [weak self] url in self?.backup?.handleCallback(url) }
        urlHandler?.register()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: DataStore(directory: DataStore.defaultDirectory()),
                         clock: SystemClock(), calendar: .current)
        backup = BackupCoordinator(model: model)
        model.onChange = { [weak self] in self?.backup.scheduleBackup() }
        popover.behavior = .transient
        statusController = StatusItemController(model: model) { [weak self] button in
            self?.togglePanel(relativeTo: button)
        }
        wireDayRefresh()
        applyLaunchAtLogin()
        if model.data.isPristine { openSettings() }
        if let file = model.recoveredFile { showDamageAlert(fileName: file) }
    }

    /// Tells the user that `data.json` was damaged and moved aside, and names the file.
    private func showDamageAlert(fileName: String) {
        let folder = model.recoveredFileURL?.deletingLastPathComponent().path ?? DataStore.defaultDirectory().path
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Your data file was damaged"
        a.informativeText = "todo-target moved it aside as \(fileName) in \(folder) and started with empty data. "
            + "Nothing was deleted. If you use backup, todo-target will not replace your backup without asking."
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Opens (or raises) the Settings window.
    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, backup: backup))
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
            var actions = PanelActions()
            actions.openSettings = { [weak self] in self?.openSettings() }
            actions.importList = { [weak self] in self?.openSettings() }
            actions.backupNow = { [weak self] in Task { await self?.backup.backupNow() } }
            let host = NSHostingController(rootView: PanelView(model: model, backup: backup, actions: actions))
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
