import Foundation

/// Reads and writes `data.json`. `load()` never throws and never deletes a bad file.
public final class DataStore {
    private let directory: URL
    private let now: () -> Date

    private var fileURL: URL { directory.appendingPathComponent("data.json") }

    public init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    public static func defaultDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["TODO_TARGET_DATA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("todo-target", isDirectory: true)
    }

    private struct VersionProbe: Decodable { var schemaVersion: Int }

    /// The loaded data, and the file that was moved aside when the old one was damaged.
    public struct LoadResult {
        public var data: AppData
        /// Non-nil when `data.json` was unreadable or invalid and was moved aside.
        public var quarantinedFile: URL?
        /// True whenever `data.json` existed but was unreadable or invalid, even if it could not be moved aside.
        public var damageFound: Bool
    }

    public func load() -> AppData { loadReport().data }

    public func loadReport() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(data: .pristine(), quarantinedFile: nil, damageFound: false)
        }
        guard let bytes = try? Data(contentsOf: fileURL),
              let probe = try? JSONDecoder().decode(VersionProbe.self, from: bytes),
              probe.schemaVersion == AppData.currentSchemaVersion,
              let data = try? JSONDecoder().decode(AppData.self, from: bytes),
              data.isValid else {
            return LoadResult(data: .pristine(), quarantinedFile: quarantine(), damageFound: true)
        }
        return LoadResult(data: data, quarantinedFile: nil, damageFound: false)
    }

    public func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `.atomic` writes a temp file and renames it over the target.
        try encoder.encode(data).write(to: fileURL, options: .atomic)
    }

    /// Moves the bad file to `data.json.corrupt-<unix time>`. Never overwrites an earlier one.
    private func quarantine() -> URL? {
        let stamp = Int(now().timeIntervalSince1970)
        var target = directory.appendingPathComponent("data.json.corrupt-\(stamp)")
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("data.json.corrupt-\(stamp)-\(n)")
            n += 1
        }
        do { try FileManager.default.moveItem(at: fileURL, to: target) } catch { return nil }
        return target
    }
}
