import Testing
import Foundation
@testable import TodoTargetCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let good = URL(string: "todotarget://auth-callback#access_token=a&refresh_token=r&expires_in=3600")!

@Test func callbackIsIgnoredWhenNoSignInIsPending() {
    #expect(PendingSignIn().accepts(good, now: t0) == false)
}

@Test func callbackIsAcceptedWhileAnEmailLinkRequestIsPending() {
    var p = PendingSignIn()
    p.begin(now: t0)
    #expect(p.accepts(good, now: t0.addingTimeInterval(60)))
    #expect(p.accepts(good, now: t0.addingTimeInterval(14 * 60 + 59)))
}

@Test func pendingRequestTimesOutAfterFifteenMinutes() {
    var p = PendingSignIn()
    p.begin(now: t0)
    #expect(p.accepts(good, now: t0.addingTimeInterval(15 * 60 + 1)) == false)
    #expect(p.isActive(now: t0.addingTimeInterval(15 * 60 + 1)) == false)
}

@Test func cancelEndsThePendingRequest() {
    var p = PendingSignIn()
    p.begin(now: t0)
    p.cancel()
    #expect(p.accepts(good, now: t0) == false)
}

@Test func otherSchemesAndHostsAreIgnoredEvenWhilePending() {
    var p = PendingSignIn()
    p.begin(now: t0)
    for bad in ["https://auth-callback#access_token=a", "todotarget://evil#access_token=a", "todotarget://#access_token=a",
                "otherapp://auth-callback#access_token=a"] {
        #expect(p.accepts(URL(string: bad)!, now: t0) == false)
    }
    #expect(p.accepts(URL(string: "todotarget://AUTH-CALLBACK#access_token=a")!, now: t0))
}

@Test func beginAgainRestartsTheTimeout() {
    var p = PendingSignIn()
    p.begin(now: t0)
    p.begin(now: t0.addingTimeInterval(10 * 60))
    #expect(p.accepts(good, now: t0.addingTimeInterval(20 * 60)))
}
