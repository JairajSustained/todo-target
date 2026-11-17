import Testing
import Foundation
@testable import TodoTargetCore

private let used = Fixtures.make(own: ["2026-11-17": [0]], firstUse: "2026-11-17")
private func remote(of d: AppData, at t: TimeInterval = 1_800_000_000) -> BackupPayload {
    BackupPayload(data: d, savedAt: Date(timeIntervalSince1970: t))
}

@Test func pristineLocalWithNoBackupUploadsNothing() {
    #expect(BackupSync.plan(local: .pristine(), recoveredFromDamage: false, remote: nil, lastSyncedAt: nil) == .skip)
}

@Test func pristineLocalWithBackupOffersRestoreNeverUpload() {
    #expect(BackupSync.plan(local: .pristine(), recoveredFromDamage: false, remote: remote(of: used), lastSyncedAt: nil) == .offerRestore)
}

@Test func recoveredLocalWithBackupOffersRestoreEvenIfItHasNewData() {
    // data.json was damaged and moved aside; the user has since ticked a goal.
    #expect(BackupSync.plan(local: used, recoveredFromDamage: true, remote: remote(of: Fixtures.make(own: ["2026-11-10": [0, 1, 2]], firstUse: "2026-11-01")),
                            lastSyncedAt: nil) == .offerRestore)
}

@Test func recoveredLocalWithNoBackupMayUploadItsNewData() {
    #expect(BackupSync.plan(local: used, recoveredFromDamage: true, remote: nil, lastSyncedAt: nil) == .upload)
    #expect(BackupSync.plan(local: .pristine(), recoveredFromDamage: true, remote: nil, lastSyncedAt: nil) == .skip)
}

@Test func localDataWithNoBackupUploads() {
    #expect(BackupSync.plan(local: used, recoveredFromDamage: false, remote: nil, lastSyncedAt: nil) == .upload)
}

@Test func backupThatThisMacWroteLastUploads() {
    let r = remote(of: Fixtures.make(firstUse: "2026-11-01"), at: 1_800_000_000)
    #expect(BackupSync.plan(local: used, recoveredFromDamage: false, remote: r,
                            lastSyncedAt: Date(timeIntervalSince1970: 1_800_000_000.4)) == .upload)
}

@Test func backupWithSameContentUploads() {
    #expect(BackupSync.plan(local: used, recoveredFromDamage: false, remote: remote(of: used), lastSyncedAt: nil) == .upload)
}

@Test func differentBackupAndLocalDataAsksWhichWins() {
    let other = Fixtures.make(own: ["2026-11-10": [0, 1, 2]], firstUse: "2026-11-01")
    #expect(BackupSync.plan(local: used, recoveredFromDamage: false, remote: remote(of: other), lastSyncedAt: nil) == .askWhichWins)
    // A backup from another Mac than the one that last synced here is also a conflict.
    #expect(BackupSync.plan(local: used, recoveredFromDamage: false, remote: remote(of: other, at: 1_800_000_500),
                            lastSyncedAt: Date(timeIntervalSince1970: 1_800_000_000)) == .askWhichWins)
}
