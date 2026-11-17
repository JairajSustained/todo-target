import AppKit

/// Receives `todotarget://auth-callback#...` links (the sign-in redirect) as an Apple event.
final class URLSchemeHandler: NSObject {
    private let onURL: @MainActor (URL) -> Void

    init(onURL: @escaping @MainActor (URL) -> Void) {
        self.onURL = onURL
        super.init()
    }

    func register() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s), url.scheme == "todotarget" else { return }
        let callback = onURL
        MainActor.assumeIsolated { callback(url) }
    }
}
