import Foundation

public struct Tab: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var layout: Layout
    /// The pane that had focus when the tab was saved (nil in pre-existing
    /// files → restoration focuses the first surface).
    public var focusedSurfaceID: UUID?

    public init(id: UUID = UUID(), title: String, layout: Layout, focusedSurfaceID: UUID? = nil) {
        self.id = id
        self.title = title
        self.layout = layout
        self.focusedSurfaceID = focusedSurfaceID
    }
}

public struct Session: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var tabs: [Tab]
    /// The tab that was active when the session was saved. Missing in
    /// pre-existing files → 0.
    public var activeTabIndex: Int

    public init(id: UUID = UUID(), title: String, tabs: [Tab] = [], activeTabIndex: Int = 0) {
        self.id = id
        self.title = title
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        tabs = try container.decode([Tab].self, forKey: .tabs)
        activeTabIndex = try container.decodeIfPresent(Int.self, forKey: .activeTabIndex) ?? 0
    }
}

public struct Project: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var rootPath: String
    public var isPinned: Bool
    public var sortOrder: Int
    public var preserveSessions: Bool
    public var sessions: [Session]

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        isPinned: Bool = false,
        sortOrder: Int = 0,
        preserveSessions: Bool = false,
        sessions: [Session] = []
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.preserveSessions = preserveSessions
        self.sessions = sessions
    }
}
