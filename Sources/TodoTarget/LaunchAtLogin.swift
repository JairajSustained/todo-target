import ServiceManagement

enum LaunchAtLogin {
    /// Registers or removes the app as a login item. Throws when the app is not
    /// a proper bundle (for example under `swift run`). Callers treat that as non-fatal.
    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// True when running from a `.app` bundle, the only case where login items work.
    static var isBundled: Bool { Bundle.main.bundlePath.hasSuffix(".app") }
}
