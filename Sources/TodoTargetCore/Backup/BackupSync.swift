import Foundation

/// What to do before the first upload of a session. A backup must never be
/// overwritten by data that is empty or that was just recovered from damage.
public enum SyncPlan: Equatable, Sendable {
    /// Safe to upload.
    case upload
    /// Nothing worth uploading (local data is empty and no backup exists).
    case skip
    /// A backup exists and local data is empty or recovered: offer Restore. Do not upload.
    case offerRestore
    /// Both sides hold different data: the user must choose which one wins.
    case askWhichWins
}

public enum BackupSync {
    /// - Parameters:
    ///   - recoveredFromDamage: `data.json` was moved aside at start, so local data is not trusted.
    ///   - remote: the backup row, from a `pull()` made just before.
    ///   - lastSyncedAt: `savedAt` of the last backup this Mac wrote or restored.
    public static func plan(local: AppData, recoveredFromDamage: Bool,
                            remote: BackupPayload?, lastSyncedAt: Date?) -> SyncPlan {
        guard let remote else {
            return local.isPristine ? .skip : .upload
        }
        if local.isPristine || recoveredFromDamage { return .offerRestore }
        if let last = lastSyncedAt, abs(remote.savedAt.timeIntervalSince(last)) < 1 { return .upload }
        if sameContent(local, remote) { return .upload }
        return .askWhichWins
    }

    static func sameContent(_ local: AppData, _ remote: BackupPayload) -> Bool {
        local.goals == remote.goals && local.days == remote.days && local.firstUseDay == remote.firstUseDay
    }
}
