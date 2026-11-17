import Foundation

public enum BackupError: Error, Equatable, Sendable {
    case notSignedIn
    case badResponse(status: Int)
    case invalidCallback
    case signInFailed(String)
    case invalidConfiguration
    /// The payload failed validation. It is never uploaded.
    case invalidData
}

/// A small Supabase client over plain web requests. Endpoint shapes, checked against:
/// - Auth server OpenAPI: https://github.com/supabase/auth/blob/master/openapi.yaml
///   `/otp` body: email, create_user, data, code_challenge(_method), gotrue_meta_security.
///   `/token?grant_type=refresh_token` body: refresh_token only.
/// - supabase-js (https://github.com/supabase/supabase-js, packages/core/auth-js/src):
///   `lib/fetch.ts` sends the redirect as the `redirect_to` QUERY parameter (not in the body);
///   `GoTrueClient._refreshAccessToken` posts `{refresh_token}` to `/token?grant_type=refresh_token`;
///   `_getSessionFromURL` (default flowType `implicit`) reads access_token, refresh_token,
///   expires_in, expires_at, token_type from the URL, and error, error_code, error_description on failure.
/// - Redirect allow-list: https://supabase.com/docs/guides/auth/redirect-urls
/// - PostgREST upsert and select: https://docs.postgrest.org/en/stable/references/api/tables_views.html
///   (`POST` with `Prefer: resolution=merge-duplicates` and `?on_conflict=<unique column>`; `?select=`).
/// NOT confirmed from the pages read: the `/auth/v1` and `/rest/v1` gateway prefixes, and the
/// `apikey` header. They come from the plan and need the live check (Task 13 step 6).
public final class BackupClient: @unchecked Sendable {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession
    private let tokens: TokenStore
    private let now: @Sendable () -> Date

    public init(baseURL: URL, anonKey: String, session: URLSession, tokens: TokenStore,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.session = session
        self.tokens = tokens
        self.now = now
    }

    /// Names a project for session binding: lower-case scheme and host, port kept, no trailing slash.
    public static func projectID(for url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.scheme = c.scheme?.lowercased()
        c.host = c.host?.lowercased()
        c.query = nil
        c.fragment = nil
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.string ?? url.absoluteString
    }

    private var projectID: String { Self.projectID(for: baseURL) }

    /// True only for a session that was issued for this client's project URL.
    public var isSignedIn: Bool { tokens.read()?.projectURL == projectID }

    // MARK: Sign-in

    public func sendMagicLink(email: String, redirectTo: URL) async throws {
        var req = makeRequest(path: "auth/v1/otp", query: [URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString)])
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": true])
        _ = try await send(req)
    }

    /// Reads the tokens from the redirect URL. The implicit flow puts them in the fragment.
    public func completeSignIn(callback: URL) throws {
        var params: [String: String] = [:]
        func absorb(_ s: String?) {
            guard let s, !s.isEmpty else { return }
            func decode(_ x: Substring) -> String {
                x.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(x)
            }
            for pair in s.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let k = kv.first else { continue }
                params[decode(k)] = kv.count > 1 ? decode(kv[1]) : ""
            }
        }
        let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        absorb(comps?.percentEncodedQuery)
        absorb(comps?.percentEncodedFragment)

        if params["error"] != nil || params["error_description"] != nil || params["error_code"] != nil {
            throw BackupError.signInFailed(params["error_description"] ?? params["error"] ?? "Sign-in failed")
        }
        guard let access = params["access_token"], !access.isEmpty,
              let refresh = params["refresh_token"], !refresh.isEmpty else { throw BackupError.invalidCallback }
        try tokens.write(AuthSession(accessToken: access, refreshToken: refresh,
                                     expiresAt: expiry(expiresAt: params["expires_at"], expiresIn: params["expires_in"]),
                                     projectURL: projectID))
    }

    // MARK: Backup

    public func push(_ p: BackupPayload) async throws {
        guard p.isValid else { throw BackupError.invalidData }
        let access = try await validAccessToken()
        var row: [String: Any] = [
            "payload": try JSONSerialization.jsonObject(with: BackupCoding.encoder().encode(p)),
            "updated_at": ISO8601DateFormatter().string(from: now()),
        ]
        // The row owner is `auth.uid()` by default. Send it when the token shows it.
        if let uid = Self.userID(fromJWT: access) { row["user_id"] = uid }
        var req = makeRequest(path: "rest/v1/backups", query: [URLQueryItem(name: "on_conflict", value: "user_id")], bearer: access)
        req.httpMethod = "POST"
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: row)
        _ = try await send(req)
    }

    /// Returns nil when the user has no backup row.
    public func pull() async throws -> BackupPayload? {
        let access = try await validAccessToken()
        var req = makeRequest(path: "rest/v1/backups", query: [URLQueryItem(name: "select", value: "payload")], bearer: access)
        req.httpMethod = "GET"
        let data = try await send(req)
        struct Row: Decodable { var payload: BackupPayload }
        let rows = try BackupCoding.decoder().decode([Row].self, from: data)
        return rows.first?.payload
    }

    // MARK: Internals

    private func makeRequest(path: String, query: [URLQueryItem], bearer: String? = nil) -> URLRequest {
        var c = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        c.queryItems = query
        var req = URLRequest(url: c.url!)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw BackupError.badResponse(status: status) }
        return data
    }

    private func validAccessToken() async throws -> String {
        guard let s = tokens.read() else { throw BackupError.notSignedIn }
        // A session for another project URL is never used, and never refreshed there: delete it.
        guard s.projectURL == projectID else {
            tokens.clear()
            throw BackupError.notSignedIn
        }
        if s.expiresAt.timeIntervalSince(now()) > 30 { return s.accessToken }

        var req = makeRequest(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")])
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        let data: Data
        do { data = try await send(req) } catch BackupError.badResponse(let status) where (400...403).contains(status) {
            tokens.clear()   // The refresh token is no longer valid: signed out.
            throw BackupError.notSignedIn
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { throw BackupError.invalidCallback }
        let fresh = AuthSession(accessToken: access, refreshToken: refresh,
                                expiresAt: expiry(expiresAt: (obj["expires_at"] as? NSNumber)?.stringValue,
                                                  expiresIn: (obj["expires_in"] as? NSNumber)?.stringValue),
                                projectURL: projectID)
        try tokens.write(fresh)
        return access
    }

    private func expiry(expiresAt: String?, expiresIn: String?) -> Date {
        if let at = expiresAt.flatMap(Double.init) { return Date(timeIntervalSince1970: at) }
        return now().addingTimeInterval(expiresIn.flatMap(Double.init) ?? 3600)
    }

    /// The `sub` claim of a JWT, or nil when the token is not a JWT.
    static func userID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["sub"] as? String
    }
}
