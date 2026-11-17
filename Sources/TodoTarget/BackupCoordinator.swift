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
    /// True once the first-sync check (pull, compare) passed in this session.
    private var synced = false

    private static let lastSyncedKey = "lastBackupSavedAt"
    /// `savedAt` of the last backup this Mac wrote or restored.
    private var lastSyncedAt: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncedKey) }
    }

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
            await self?.backupNow(interactive: false)
        }
    }

    /// `interactive` is false for the timer after a change: it never asks a question.
    func backupNow(interactive: Bool = true) async {
        debounce?.cancel()
        guard let c = client() else { status = "Backup is not set up"; return }
        guard c.isSignedIn else { signedIn = false; status = "Signed out"; return }
        do {
            if !synced {
                // First upload of this session: pull first. Never overwrite a backup unasked.
                let remote = try await c.pull()
                let plan = BackupSync.plan(local: model.data, recoveredFromDamage: model.recoveredFromDamage,
                                           remote: remote, lastSyncedAt: lastSyncedAt)
                switch plan {
                case .skip:
                    status = "Nothing to back up yet"
                    return
                case .upload:
                    synced = true
                case .offerRestore, .askWhichWins:
                    guard let remote else { return }
                    guard interactive else {
                        status = "Backup paused: open Settings and click Backup now to compare with your backup"
                        return
                    }
                    switch askWhichWins(plan: plan) {
                    case .useBackup:
                        applyRestore(remote)
                        return
                    case .useThisMac:
                        synced = true
                        model.clearRecoveryFlag()
                    case .notNow:
                        status = "Backup paused: nothing was changed"
                        return
                    }
                }
            }
            if model.data.isPristine { status = "Nothing to back up yet"; return }
            let p = BackupPayload(data: model.data, savedAt: Date())
            try await c.push(p)
            lastSyncedAt = p.savedAt
            status = "Last backup: " + p.savedAt.formatted(date: .abbreviated, time: .shortened)
        } catch BackupError.notSignedIn {
            signedIn = false; status = "Signed out"
        } catch {
            status = "Backup failed: \(Self.describe(error))"
        }
    }

    private enum Choice { case useBackup, useThisMac, notNow }

    private func askWhichWins(plan: SyncPlan) -> Choice {
        let a = NSAlert()
        a.alertStyle = .warning
        a.addButton(withTitle: "Not now")
        if plan == .offerRestore {
            a.messageText = "A backup exists for this account"
            a.informativeText = model.recoveredFromDamage
                ? "The data file on this Mac was damaged and moved aside, so this Mac may be missing data. Restore the backup, or keep what is on this Mac and replace the backup."
                : "This Mac has no goals or history yet. Restore the backup to this Mac."
            a.addButton(withTitle: "Restore the backup")
            if !model.data.isPristine { a.addButton(withTitle: "Keep this Mac's data and replace the backup") }
        } else {
            a.messageText = "The backup and this Mac differ"
            a.informativeText = "Choose which one to keep. The other one is replaced."
            a.addButton(withTitle: "Use the backup")
            a.addButton(withTitle: "Use this Mac's data")
        }
        NSApp.activate(ignoringOtherApps: true)
        let titles = a.buttons.map(\.title)
        let r = a.runModal()
        let idx = r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard titles.indices.contains(idx) else { return .notNow }
        switch titles[idx] {
        case "Restore the backup", "Use the backup": return .useBackup
        case "Keep this Mac's data and replace the backup", "Use this Mac's data": return .useThisMac
        default: return .notNow
        }
    }

    private func applyRestore(_ payload: BackupPayload) {
        guard payload.isValid else {
            status = "The backup is damaged. Nothing was changed."
            return
        }
        model.replaceData(payload.appData(keeping: model.data.settings))
        model.clearRecoveryFlag()
        lastSyncedAt = payload.savedAt
        synced = true
        status = "Restored the backup"
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
            guard payload.isValid else { status = "The backup is damaged. Nothing was changed."; return }
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
            applyRestore(payload)
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
