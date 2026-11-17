import Testing
import Foundation
@testable import TodoTargetCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("todo-target-tests-\(UUID().uuidString)")
}
private let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
private func corruptFiles(in dir: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("data.json.corrupt-") }
}

@Test func missingFileGivesPristine() {
    let store = DataStore(directory: tempDir(), now: fixedNow)
    #expect(store.load().isPristine)
}

@Test func saveThenLoadRoundTrips() throws {
    let dir = tempDir()
    let store = DataStore(directory: dir, now: fixedNow)
    var d = AppData.pristine()
    d.goals[0].name = "DSA"
    d.firstUseDay = "2026-11-17"
    try store.save(d)
    #expect(DataStore(directory: dir, now: fixedNow).load() == d)
}

@Test func corruptFileIsQuarantinedNotDeleted() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bad = Data("{not json".utf8)
    try bad.write(to: dir.appendingPathComponent("data.json"))
    #expect(DataStore(directory: dir, now: fixedNow).load().isPristine)
    let moved = corruptFiles(in: dir)
    #expect(moved.count == 1)
    #expect(moved.first.flatMap { try? Data(contentsOf: $0) } == bad)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("data.json").path))
}

@Test func emptyFileIsQuarantined() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data().write(to: dir.appendingPathComponent("data.json"))
    #expect(DataStore(directory: dir, now: fixedNow).load().isPristine)
    #expect(corruptFiles(in: dir).count == 1)
}

@Test func newerSchemaIsQuarantined() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var d = AppData.pristine(); d.schemaVersion = 99
    let bytes = try JSONEncoder().encode(d)
    try bytes.write(to: dir.appendingPathComponent("data.json"))
    #expect(DataStore(directory: dir, now: fixedNow).load().isPristine)
    let moved = corruptFiles(in: dir)
    #expect(moved.count == 1)
    #expect(moved.first.flatMap { try? Data(contentsOf: $0) } == bytes)
}

@Test func saveCreatesDirectory() throws {
    let dir = tempDir().appendingPathComponent("nested")
    try DataStore(directory: dir, now: fixedNow).save(AppData.pristine())
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("data.json").path))
}

@Test func defaultDirectoryHonorsEnvVariable() {
    setenv("TODO_TARGET_DATA_DIR", "/tmp/tt-env-test", 1)
    defer { unsetenv("TODO_TARGET_DATA_DIR") }
    #expect(DataStore.defaultDirectory().path == "/tmp/tt-env-test")
}

@Test func loadReportNamesTheQuarantinedFile() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{not json".utf8).write(to: dir.appendingPathComponent("data.json"))
    let report = DataStore(directory: dir, now: fixedNow).loadReport()
    #expect(report.data.isPristine)
    #expect(report.quarantinedFile?.lastPathComponent == "data.json.corrupt-1700000000")
}

@Test func loadReportHasNoQuarantinedFileForGoodOrMissingData() throws {
    let dir = tempDir()
    #expect(DataStore(directory: dir, now: fixedNow).loadReport().quarantinedFile == nil)
    let store = DataStore(directory: dir, now: fixedNow)
    try store.save(AppData.pristine())
    #expect(store.loadReport().quarantinedFile == nil)
}

private func expectQuarantined(_ bad: AppData) throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bytes = try JSONEncoder().encode(bad)
    try bytes.write(to: dir.appendingPathComponent("data.json"))
    let report = DataStore(directory: dir, now: fixedNow).loadReport()
    #expect(report.data.isPristine)
    #expect(report.quarantinedFile != nil)
    #expect(report.quarantinedFile.flatMap { try? Data(contentsOf: $0) } == bytes)
}

@Test func structurallyInvalidDataIsQuarantined() throws {
    var twoGoals = AppData.pristine(); twoGoals.goals.removeLast()
    try expectQuarantined(twoGoals)
    var dupes = AppData.pristine(); dupes.goals[2].id = dupes.goals[0].id
    try expectQuarantined(dupes)
    var badPosition = AppData.pristine(); badPosition.goals[1].position = 7
    try expectQuarantined(badPosition)
    var negative = AppData.pristine(); negative.goals[1].position = -2
    try expectQuarantined(negative)
    var schema0 = AppData.pristine(); schema0.schemaVersion = 0
    try expectQuarantined(schema0)
}

@Test func damageIsReportedEvenWhenTheFileCannotBeMovedAside() throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let bad = Data("{not json".utf8)
    try bad.write(to: dir.appendingPathComponent("data.json"))
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)   // read-only folder
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    let report = DataStore(directory: dir, now: fixedNow).loadReport()
    #expect(report.data.isPristine)
    #expect(report.damageFound)                       // still reported
    #expect(report.quarantinedFile == nil)            // but the file could not be moved
    #expect((try? Data(contentsOf: dir.appendingPathComponent("data.json"))) == bad)   // and it is still there
}

@Test func damageFoundIsFalseForGoodMissingAndTrueForQuarantined() throws {
    let dir = tempDir()
    #expect(DataStore(directory: dir, now: fixedNow).loadReport().damageFound == false)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: dir.appendingPathComponent("data.json"))
    let r = DataStore(directory: dir, now: fixedNow).loadReport()
    #expect(r.damageFound); #expect(r.quarantinedFile != nil)
}
