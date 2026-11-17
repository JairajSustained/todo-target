import Foundation

public struct ListItem: Codable, Equatable, Sendable {
    public var group: String
    public var title: String
    public var url: URL?

    public init(group: String, title: String, url: URL? = nil) {
        self.group = group
        self.title = title
        self.url = url
    }
}

public struct Goal: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [ListItem]
    public var position: Int

    public init(id: UUID = UUID(), name: String, items: [ListItem] = [], position: Int = 0) {
        self.id = id
        self.name = name
        self.items = items
        self.position = position
    }
}

public struct Completion: Codable, Equatable, Sendable {
    public var itemIndex: Int?
    /// A `DayKey.string`.
    public var doneOn: String

    public init(itemIndex: Int?, doneOn: String) {
        self.itemIndex = itemIndex
        self.doneOn = doneOn
    }
}

public struct DayRecord: Codable, Equatable, Sendable {
    /// Key is `goal.id.uuidString`.
    public var completions: [String: Completion]

    public init(completions: [String: Completion] = [:]) {
        self.completions = completions
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool = true
    public var supabaseURL: String?
    public var supabaseAnonKey: String?

    public init(launchAtLogin: Bool = true, supabaseURL: String? = nil, supabaseAnonKey: String? = nil) {
        self.launchAtLogin = launchAtLogin
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
    }
}

public struct AppData: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var goals: [Goal]
    public var days: [String: DayRecord]
    public var firstUseDay: String?
    public var settings: Settings

    public init(schemaVersion: Int = 1, goals: [Goal], days: [String: DayRecord] = [:],
                firstUseDay: String? = nil, settings: Settings = Settings()) {
        self.schemaVersion = schemaVersion
        self.goals = goals
        self.days = days
        self.firstUseDay = firstUseDay
        self.settings = settings
    }

    public static func pristine() -> AppData {
        AppData(goals: (1...3).map { Goal(name: "Goal \($0)") })
    }

    /// True only when nothing the user did is stored.
    public var isPristine: Bool {
        guard days.isEmpty, firstUseDay == nil else { return false }
        for (i, g) in goals.enumerated() {
            if g.name != "Goal \(i + 1)" || !g.items.isEmpty { return false }
        }
        return true
    }
}
