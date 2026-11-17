import Foundation

/// Remembers whether the first-sync comparison (pull, then `BackupSync.plan`) has passed
/// for the current sign-in. Any new sign-in, sign-out, or project change must compare again,
/// so an upload never skips the check.
public struct SyncGate: Sendable {
    public private(set) var mayUploadWithoutComparing = false

    public init() {}

    public mutating func comparisonPassed() { mayUploadWithoutComparing = true }
    /// A sign-in finished (maybe a different account, maybe a backup changed since).
    public mutating func signedIn() { mayUploadWithoutComparing = false }
    /// A request found the session gone or refused.
    public mutating func signedOut() { mayUploadWithoutComparing = false }
    /// The project URL changed.
    public mutating func reset() { mayUploadWithoutComparing = false }
}
