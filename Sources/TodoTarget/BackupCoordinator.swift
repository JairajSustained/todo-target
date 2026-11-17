import AppKit
import TodoTargetCore

/// Owns the optional Supabase backup. Quiet by design: no alerts, no notifications.
/// With no Supabase settings it makes no network calls.
@MainActor
final class BackupCoordinator: ObservableObject {
    static let redirectURL = URL(string: "todotarget://auth-callback")!

    @Published private(set) var status: String = ""
    @Published private(set) var signedIn = false

    private let model: AppModel
    private let tokens: TokenStore
    private let urlSession: URLSession
    private var debounce: Task<Void, Never>?

    init(model: AppModel, tokens: TokenStore = KeychainTokenStore(), urlSession: URLSession = .shared) {
        self.model = model
        self.tokens = tokens
        self.urlSession = urlSession
        refreshState()
    }

    private func client() -> BackupClient? {
        let s = model.data.settings
        guard let raw = s.supabaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              let key = s.supabaseAnonKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else { return nil }
        return BackupClient(baseURL: url, anonKey: key, session: urlSession, tokens: tokens)
    }

    var isConfigured: Bool { client() != nil }

    func refreshState() {
        guard let c = client() else { signedIn = false; status = ""; return }
        signedIn = c.isSignedIn
        if !signedIn { status = "Signed out" }
        else if status.isEmpty || status == "Signed out" { status = "Signed in" }
    }

    /// Called after every change. Pushes 5 seconds after the last one.
    func scheduleBackup() {
        debounce?.cancel()
        guard let c = client(), c.isSignedIn else { return }
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.backupNow()
        }
    }

    func backupNow() async {
        debounce?.cancel()
        guard let c = client() else { status = "Backup is not set up"; return }
        guard c.isSignedIn else { signedIn = false; status = "Signed out"; return }
        do {
            let p = BackupPayload(data: model.data, savedAt: Date())
            try await c.push(p)
            status = "Last backup: " + p.savedAt.formatted(date: .abbreviated, time: .shortened)
        } catch BackupError.notSignedIn {
            signedIn = false; status = "Signed out"
        } catch {
            status = "Backup failed: \(Self.describe(error))"
        }
    }

    func sendSignInLink(email: String) async {
        guard let c = client() else { status = "Enter the Supabase URL and anon key first"; return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Enter your email first"; return }
        do {
            try await c.sendMagicLink(email: trimmed, redirectTo: Self.redirectURL)
            status = "Sign-in link sent. Open it on this Mac."
        } catch {
            status = "Could not send the link: \(Self.describe(error))"
        }
    }

    /// The redirect from the email link arrives here.
    func handleCallback(_ url: URL) {
        guard let c = client() else { status = "Enter the Supabase URL and anon key first"; return }
        do {
            try c.completeSignIn(callback: url)
            signedIn = true
            status = "Signed in"
            Task { await backupNow() }
        } catch BackupError.signInFailed(let why) {
            status = "Sign-in failed: \(why)"
        } catch {
            status = "Sign-in failed: the link was not valid"
        }
    }

    /// Restore (C20, Review Focus 5): local data is replaced only after a confirmation,
    /// unless it holds nothing the user did.
    func restore() async {
        guard let c = client() else { status = "Backup is not set up"; return }
        do {
            guard let payload = try await c.pull() else { status = "No backup found"; return }
            if BackupRestore.decision(local: model.data) == .needsConfirmation {
                let a = NSAlert()
                a.messageText = "Replace the data on this Mac?"
                a.informativeText = "This Mac already has goals or history. Restoring replaces them with the backup."
                a.addButton(withTitle: "Cancel")
                a.addButton(withTitle: "Replace")
                a.alertStyle = .warning
                NSApp.activate(ignoringOtherApps: true)
                guard a.runModal() == .alertSecondButtonReturn else { status = "Restore cancelled"; return }
            }
            model.replaceData(payload.appData(keeping: model.data.settings))
            status = "Restored the backup"
        } catch BackupError.notSignedIn {
            signedIn = false; status = "Signed out"
        } catch {
            status = "Restore failed: \(Self.describe(error))"
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case BackupError.badResponse(let s): return "server answered \(s)"
        case BackupError.notSignedIn: return "signed out"
        default: return error.localizedDescription
        }
    }
}
