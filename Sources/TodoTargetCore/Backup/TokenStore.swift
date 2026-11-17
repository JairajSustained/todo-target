import Foundation
import Security

public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public protocol TokenStore: Sendable {
    func read() -> AuthSession?
    func write(_ s: AuthSession) throws
    func clear()
}

/// Keeps the session in the macOS Keychain. Tokens never go to `data.json`.
/// An ad-hoc signature changes with each build, so the Keychain may refuse to read an
/// item made by an older build. `read()` returns nil on any error: the app then shows
/// "Signed out". It never prompts in a loop and never crashes.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "supabase-session"

    public init(service: String = "dev.todotarget.app") { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> AuthSession? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never show an authorization prompt. (Deprecated key, but it is the one that
        // the file-based keychain honours for items made by an older build.)
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? BackupCoding.decoder().decode(AuthSession.self, from: data)
    }

    public func write(_ s: AuthSession) throws {
        let data = try BackupCoding.encoder().encode(s)
        SecItemDelete(baseQuery as CFDictionary)
        var q = baseQuery
        q[kSecValueData as String] = data
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func clear() { SecItemDelete(baseQuery as CFDictionary) }
}
