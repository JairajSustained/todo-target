import Foundation

/// Tracks whether the user asked for a sign-in link. A `todotarget://auth-callback` link
/// is accepted only while a request is pending, and for a limited time. Any other link
/// that reaches the app through the URL scheme is ignored.
public struct PendingSignIn: Sendable {
    public static let timeout: TimeInterval = 15 * 60

    private var expiresAt: Date?

    public init() {}

    /// Call when the email link was sent.
    public mutating func begin(now: Date) { expiresAt = now.addingTimeInterval(Self.timeout) }

    /// Call after a callback was used, or when the project changes.
    public mutating func cancel() { expiresAt = nil }

    public func isActive(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now <= expiresAt
    }

    public func accepts(_ url: URL, now: Date) -> Bool {
        guard isActive(now: now),
              url.scheme?.lowercased() == "todotarget",
              url.host?.lowercased() == "auth-callback" else { return false }
        return true
    }
}
