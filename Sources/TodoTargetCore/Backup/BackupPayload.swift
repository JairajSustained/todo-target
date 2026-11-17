import Foundation

/// What is backed up (C20): goal names and order, lists, list positions, day records.
/// No settings and no keys.
public struct BackupPayload: Codable, Equatable, Sendable {
    public var goals: [Goal]
    public var days: [String: DayRecord]
    public var firstUseDay: String?
    public var savedAt: Date

    public init(goals: [Goal], days: [String: DayRecord], firstUseDay: String?, savedAt: Date) {
        self.goals = goals
        self.days = days
        self.firstUseDay = firstUseDay
        self.savedAt = savedAt
    }

    public init(data: AppData, savedAt: Date) {
        self.init(goals: data.goals, days: data.days, firstUseDay: data.firstUseDay, savedAt: savedAt)
    }

    /// False for a backup the app must not restore.
    public var isValid: Bool { AppData.goalsAreValid(goals) }

    /// Builds local data from a backup. Local settings stay as they are.
    public func appData(keeping settings: Settings) -> AppData {
        AppData(goals: goals, days: days, firstUseDay: firstUseDay, settings: settings)
    }
}

public enum RestoreDecision: Equatable, Sendable {
    case replaceSilently
    case needsConfirmation
}

public enum BackupRestore {
    /// Local data is never replaced without a question, unless it holds nothing the user did.
    public static func decision(local: AppData) -> RestoreDecision {
        local.isPristine ? .replaceSilently : .needsConfirmation
    }
}

enum BackupCoding {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
