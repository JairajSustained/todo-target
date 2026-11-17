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
