import Testing
import Foundation
@testable import TodoTargetCore

// MARK: Test doubles

/// A URLProtocol that answers from a per-host handler, so tests can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Captured { var request: URLRequest; var body: Data }
    typealias Handler = @Sendable (Captured) -> (Int, Data)

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var log: [String: [Captured]] = [:]
    private static let lock = NSLock()

    static func register(host: String, handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers[host] = handler
        log[host] = []
    }
    static func captured(host: String) -> [Captured] {
        lock.lock(); defer { lock.unlock() }
        return log[host] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        }
        let cap = Captured(request: request, body: body)
        Self.lock.lock()
        Self.log[host, default: []].append(cap)
        let handler = Self.handlers[host]
        Self.lock.unlock()
        let (status, data) = handler?(cap) ?? (500, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?
    init(_ s: AuthSession? = nil) { session = s }
    func read() -> AuthSession? { lock.lock(); defer { lock.unlock() }; return session }
    func write(_ s: AuthSession) throws { lock.lock(); session = s; lock.unlock() }
    func clear() { lock.lock(); session = nil; lock.unlock() }
}

private struct Rig {
    let host = "t\(UUID().uuidString.prefix(8).lowercased()).test"
    let tokens: MemoryTokenStore
    let client: BackupClient

    /// `issuedFor` is the project URL the stored session belongs to. It defaults to this rig's URL.
    init(session: AuthSession?, issuedFor: String? = nil, handler: @escaping StubProtocol.Handler) {
        let host = self.host
        var stored = session
        stored?.projectURL = issuedFor ?? "https://\(host)"
        tokens = MemoryTokenStore(stored)
        StubProtocol.register(host: host, handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = BackupClient(baseURL: URL(string: "https://\(host)")!, anonKey: "anon-key",
                              session: URLSession(configuration: config), tokens: tokens)
    }
    var requests: [StubProtocol.Captured] { StubProtocol.captured(host: host) }
}

private func validSession() -> AuthSession {
    AuthSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(3600), projectURL: "")
}
private func payload() -> BackupPayload {
    BackupPayload(data: Fixtures.make(own: ["2026-11-17": [0]], firstUse: "2026-11-17"),
                  savedAt: Date(timeIntervalSince1970: 1_800_000_000))
}
private func query(_ r: URLRequest) -> [String: String] {
    let items = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
}
private func json(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }

// MARK: Tests

@Test func pushSendsUpsertWithAuthHeaders() async throws {
    let rig = Rig(session: validSession()) { _ in (201, Data()) }
    try await rig.client.push(payload())
    #expect(rig.requests.count == 1)
    let r = rig.requests[0]
    #expect(r.request.httpMethod == "POST")
    #expect(r.request.url?.path == "/rest/v1/backups")
    #expect(query(r.request)["on_conflict"] == "user_id")
    #expect(r.request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(r.request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
    #expect(r.request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=merge-duplicates") == true)
    let inner = json(r.body)["payload"] as? [String: Any]
    #expect((inner?["goals"] as? [Any])?.count == 3)
}

@Test func pushWithoutSessionThrowsNotSignedIn() async {
    let rig = Rig(session: nil) { _ in (201, Data()) }
    #expect(rig.client.isSignedIn == false)
    await #expect(throws: BackupError.notSignedIn) { try await rig.client.push(payload()) }
    #expect(rig.requests.isEmpty)
}

@Test func expiredTokenIsRefreshedBeforePush() async throws {
    let expired = AuthSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(-60), projectURL: "")
    let rig = Rig(session: expired) { cap in
        if cap.request.url?.path == "/auth/v1/token" {
            let body = #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600,"token_type":"bearer"}"#
            return (200, Data(body.utf8))
        }
        return (201, Data())
    }
    try await rig.client.push(payload())
    #expect(rig.requests.map { $0.request.url?.path } == ["/auth/v1/token", "/rest/v1/backups"])
    let refresh = rig.requests[0]
    #expect(query(refresh.request)["grant_type"] == "refresh_token")
    #expect(json(refresh.body)["refresh_token"] as? String == "refresh-1")
    #expect(refresh.request.value(forHTTPHeaderField: "apikey") == "anon-key")
    #expect(rig.requests[1].request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
    #expect(rig.tokens.read()?.accessToken == "access-2")
    #expect(rig.tokens.read()?.refreshToken == "refresh-2")
}

@Test func rejectedRefreshClearsSessionAndThrowsNotSignedIn() async {
    let expired = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(-60), projectURL: "")
    let rig = Rig(session: expired) { _ in (400, Data(#"{"error":"invalid_grant"}"#.utf8)) }
    await #expect(throws: BackupError.notSignedIn) { try await rig.client.push(payload()) }
    #expect(rig.tokens.read() == nil)
}

@Test func serverErrorOnPushIsReported() async {
    let rig = Rig(session: validSession()) { _ in (500, Data()) }
    await #expect(throws: BackupError.badResponse(status: 500)) { try await rig.client.push(payload()) }
}

@Test func pullReturnsNilWhenNoRow() async throws {
    let rig = Rig(session: validSession()) { _ in (200, Data("[]".utf8)) }
    #expect(try await rig.client.pull() == nil)
    let r = rig.requests[0]
    #expect(r.request.httpMethod == "GET")
    #expect(r.request.url?.path == "/rest/v1/backups")
    #expect(query(r.request)["select"] == "payload")
    #expect(r.request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
}

@Test func pullDecodesPayload() async throws {
    let p = payload()
    let row = try JSONSerialization.data(withJSONObject: [["payload": try JSONSerialization.jsonObject(with: BackupCoding.encoder().encode(p))]])
    let rig = Rig(session: validSession()) { _ in (200, row) }
    #expect(try await rig.client.pull() == p)
}

@Test func magicLinkRequestBody() async throws {
    let rig = Rig(session: nil) { _ in (200, Data("{}".utf8)) }
    try await rig.client.sendMagicLink(email: "me@example.com", redirectTo: URL(string: "todotarget://auth-callback")!)
    let r = rig.requests[0]
    #expect(r.request.httpMethod == "POST")
    #expect(r.request.url?.path == "/auth/v1/otp")
    // Docs (supabase-js fetch.ts): the redirect goes in the `redirect_to` query parameter.
    #expect(query(r.request)["redirect_to"] == "todotarget://auth-callback")
    #expect(json(r.body)["email"] as? String == "me@example.com")
    #expect(r.request.value(forHTTPHeaderField: "apikey") == "anon-key")
}

@Test func completeSignInStoresSession() throws {
    let rig = Rig(session: nil) { _ in (200, Data()) }
    let cb = URL(string: "todotarget://auth-callback#access_token=a1&refresh_token=r1&expires_in=3600&token_type=bearer")!
    try rig.client.completeSignIn(callback: cb)
    let s = rig.tokens.read()
    #expect(s?.accessToken == "a1"); #expect(s?.refreshToken == "r1")
    #expect(abs((s?.expiresAt.timeIntervalSinceNow ?? 0) - 3600) < 5)
    #expect(rig.client.isSignedIn)
}

@Test func completeSignInReportsErrorsAndBadCallbacks() {
    let rig = Rig(session: nil) { _ in (200, Data()) }
    let err = URL(string: "todotarget://auth-callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")!
    #expect(throws: BackupError.signInFailed("Email link is invalid or has expired")) { try rig.client.completeSignIn(callback: err) }
    #expect(throws: BackupError.invalidCallback) { try rig.client.completeSignIn(callback: URL(string: "todotarget://auth-callback")!) }
    #expect(rig.tokens.read() == nil)
}

@Test func payloadNeverContainsSettingsOrKeys() throws {
    var d = Fixtures.make(firstUse: "2026-11-17")
    d.settings.supabaseAnonKey = "secret-key"; d.settings.supabaseURL = "https://x.supabase.co"
    let text = String(decoding: try BackupCoding.encoder().encode(BackupPayload(data: d, savedAt: Date())), as: UTF8.self)
    #expect(!text.contains("supabaseAnonKey")); #expect(!text.contains("secret-key"))
    #expect(!text.contains("settings")); #expect(!text.contains("supabase.co"))
}

@Test func restoreSilentOnlyWhenLocalIsPristine() {
    #expect(BackupRestore.decision(local: .pristine()) == .replaceSilently)
}

@Test func restoreNeedsConfirmationWhenLocalHasData() {
    #expect(BackupRestore.decision(local: Fixtures.make(own: ["2026-11-17": [0]], firstUse: "2026-11-17")) == .needsConfirmation)
    var renamed = AppData.pristine(); renamed.goals[1].name = "DSA"
    #expect(BackupRestore.decision(local: renamed) == .needsConfirmation)
}

@Test func payloadRestoresIntoAppData() {
    let local = Fixtures.make(own: ["2026-11-17": [0]], firstUse: "2026-11-17")
    var settings = Settings(); settings.supabaseURL = "https://keep.me"
    let restored = BackupPayload(data: local, savedAt: Date()).appData(keeping: settings)
    #expect(restored.goals == local.goals); #expect(restored.days == local.days)
    #expect(restored.firstUseDay == local.firstUseDay); #expect(restored.settings.supabaseURL == "https://keep.me")
}

@Test func userIDComesFromJWTSubject() {
    let body = Data(#"{"sub":"user-123"}"#.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    #expect(BackupClient.userID(fromJWT: "h.\(body).s") == "user-123")
    #expect(BackupClient.userID(fromJWT: "access-1") == nil)
}

@Test func backupPayloadValidation() {
    #expect(payload().isValid)
    var p = payload(); p.goals.removeLast()
    #expect(!p.isValid)
    var dupes = payload(); dupes.goals[1].id = dupes.goals[0].id
    #expect(!dupes.isValid)
    var pos = payload(); pos.goals[0].position = 3
    #expect(!pos.isValid)
}

// MARK: Session is bound to its project URL

@Test func sessionIssuedForAnotherURLIsNeverSent() async {
    let rig = Rig(session: validSession(), issuedFor: "https://other.example") { _ in (201, Data()) }
    #expect(rig.client.isSignedIn == false)
    await #expect(throws: BackupError.notSignedIn) { try await rig.client.push(payload()) }
    await #expect(throws: BackupError.notSignedIn) { _ = try await rig.client.pull() }
    #expect(rig.requests.isEmpty)           // no token and no request left for the wrong host
    #expect(rig.tokens.read() == nil)       // the foreign session is deleted
}

@Test func expiredSessionForAnotherURLIsNotRefreshedThere() async {
    let expired = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(-60), projectURL: "")
    let rig = Rig(session: expired, issuedFor: "https://other.example") { _ in (200, Data()) }
    await #expect(throws: BackupError.notSignedIn) { try await rig.client.push(payload()) }
    #expect(rig.requests.isEmpty)           // the refresh token is not sent to this host either
}

@Test func completeSignInRecordsTheProjectURL() throws {
    let rig = Rig(session: nil) { _ in (200, Data()) }
    try rig.client.completeSignIn(callback: URL(string: "todotarget://auth-callback#access_token=a&refresh_token=r&expires_in=3600")!)
    #expect(rig.tokens.read()?.projectURL == "https://\(rig.host)")
}

@Test func refreshKeepsTheProjectURL() async throws {
    let expired = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(-60), projectURL: "")
    let rig = Rig(session: expired) { cap in
        cap.request.url?.path == "/auth/v1/token"
            ? (200, Data(#"{"access_token":"a2","refresh_token":"r2","expires_in":3600}"#.utf8)) : (201, Data())
    }
    try await rig.client.push(payload())
    #expect(rig.tokens.read()?.projectURL == "https://\(rig.host)")
}

@Test func projectIDIgnoresCaseAndTrailingSlash() {
    #expect(BackupClient.projectID(for: URL(string: "https://ABC.supabase.co/")!) == "https://abc.supabase.co")
    #expect(BackupClient.projectID(for: URL(string: "https://abc.supabase.co")!) == "https://abc.supabase.co")
    #expect(BackupClient.projectID(for: URL(string: "https://abc.supabase.co:8443/x/")!) == "https://abc.supabase.co:8443/x")
    #expect(BackupClient.projectID(for: URL(string: "https://abc.supabase.co")!) != BackupClient.projectID(for: URL(string: "https://xyz.supabase.co")!))
}

@Test func invalidPayloadIsNeverPushed() async {
    let rig = Rig(session: validSession()) { _ in (201, Data()) }
    var bad = payload(); bad.goals[0].position = 9      // no items, so only 0 is valid
    await #expect(throws: BackupError.invalidData) { try await rig.client.push(bad) }
    #expect(rig.requests.isEmpty)
}
