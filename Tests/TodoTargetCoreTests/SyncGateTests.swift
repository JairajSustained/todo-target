import Testing
@testable import TodoTargetCore

@Test func newSessionMustPullAndCompareBeforeUpload() {
    #expect(SyncGate().mayUploadWithoutComparing == false)
}

@Test func afterTheComparisonPassedUploadsMayContinue() {
    var g = SyncGate()
    g.comparisonPassed()
    #expect(g.mayUploadWithoutComparing)
}

@Test func aSecondSignInResetsTheGate() {
    var g = SyncGate()
    g.comparisonPassed()
    g.signedIn()                       // sign in again, maybe as another account or on a changed backup
    #expect(g.mayUploadWithoutComparing == false)
}

@Test func signedOutDuringPushResetsTheGate() {
    var g = SyncGate()
    g.comparisonPassed()
    g.signedOut()                      // a push failed with notSignedIn
    #expect(g.mayUploadWithoutComparing == false)
}

@Test func connectionChangeResetsTheGate() {
    var g = SyncGate()
    g.comparisonPassed()
    g.reset()
    #expect(g.mayUploadWithoutComparing == false)
}
