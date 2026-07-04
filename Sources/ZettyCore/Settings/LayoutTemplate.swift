import Foundation

/// A saved tab/split arrangement: each pane carries a working directory
/// relative to the project root (`"."` = the root; out-of-root cwds stay
/// absolute) and an optional startup command. One template per project (in
/// `.zetty/project.json`) or one global default — not a named catalog; see
/// `docs/plans/2026-07-04-layout-templates-design.md`.
public struct LayoutTemplate: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var tabs: [TemplateTab]

    public init(schemaVersion: Int = 1, tabs: [TemplateTab]) {
        self.schemaVersion = schemaVersion
        self.tabs = tabs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tabs = try c.decodeIfPresent([TemplateTab].self, forKey: .tabs) ?? []
    }
}

public struct TemplateTab: Codable, Sendable, Equatable {
    public var root: TemplateNode

    public init(root: TemplateNode) {
        self.root = root
    }
}

/// A pane or a split — mirrors `SurfaceNode`, but panes carry root-relative
/// cwds + commands instead of live `Surface`s. Coded with an explicit `type`
/// discriminator ("pane"/"split") so hand-authored JSON stays readable.
public indirect enum TemplateNode: Codable, Sendable, Equatable {
    case pane(workingDir: String, command: String?)
    case split(direction: SplitDirection, ratio: Double, first: TemplateNode, second: TemplateNode)

    private enum CodingKeys: String, CodingKey {
        case type, workingDir, command, direction, ratio, first, second
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "pane":
            self = .pane(
                workingDir: try c.decodeIfPresent(String.self, forKey: .workingDir) ?? ".",
                command: try c.decodeIfPresent(String.self, forKey: .command))
        case "split":
            self = .split(
                direction: try c.decode(SplitDirection.self, forKey: .direction),
                ratio: try c.decodeIfPresent(Double.self, forKey: .ratio) ?? 0.5,
                first: try c.decode(TemplateNode.self, forKey: .first),
                second: try c.decode(TemplateNode.self, forKey: .second))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown node type \"\(other)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let workingDir, let command):
            try c.encode("pane", forKey: .type)
            try c.encode(workingDir, forKey: .workingDir)
            try c.encodeIfPresent(command, forKey: .command)
        case .split(let direction, let ratio, let first, let second):
            try c.encode("split", forKey: .type)
            try c.encode(direction, forKey: .direction)
            try c.encode(ratio, forKey: .ratio)
            try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
        }
    }
}

// MARK: - Capture / apply

extension LayoutTemplate {

    /// Snapshots a live arrangement: cwds inside `rootPath` become relative
    /// (`"."` for the root itself); cwds outside stay absolute. Panes'
    /// recorded commands carry forward (best-effort — panes the user opened
    /// by hand have none).
    public static func capture(from tabList: TabList, rootPath: String) -> LayoutTemplate {
        LayoutTemplate(tabs: tabList.trees.map { tree in
            TemplateTab(root: templateNode(from: tree.layout.root, rootPath: rootPath))
        })
    }

    private static func templateNode(from node: SurfaceNode, rootPath: String) -> TemplateNode {
        switch node {
        case .leaf(let surface):
            return .pane(
                workingDir: relativePath(surface.workingDir, rootPath: rootPath),
                command: surface.command)
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction: direction, ratio: ratio,
                first: templateNode(from: first, rootPath: rootPath),
                second: templateNode(from: second, rootPath: rootPath))
        }
    }

    private static func relativePath(_ path: String, rootPath: String) -> String {
        if path == rootPath { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }   // out-of-root → absolute
        return String(path.dropFirst(prefix.count))
    }

    /// Builds a fresh `TabList` for `rootPath`: relative cwds resolve against
    /// the root (a missing directory falls back to the root — a stale
    /// template must not fail the whole open); every pane gets a NEW surface
    /// id. Returns the startup commands keyed by those ids for post-spawn
    /// injection, or nil when the template has no tabs.
    public func tabList(rootPath: String) -> (tabList: TabList, commands: [UUID: String])? {
        guard !tabs.isEmpty else { return nil }
        var commands: [UUID: String] = [:]
        let trees = tabs.map { tab -> PaneTree in
            let root = surfaceNode(from: tab.root, rootPath: rootPath, commands: &commands)
            let focus = root.surfaces.first?.id ?? UUID()
            return PaneTree(layout: Layout(root: root), focusedSurfaceID: focus)
        }
        guard let list = TabList(restoring: trees, activeIndex: 0, defaultWorkingDir: rootPath) else {
            return nil
        }
        return (list, commands)
    }

    private func surfaceNode(
        from node: TemplateNode, rootPath: String, commands: inout [UUID: String]
    ) -> SurfaceNode {
        switch node {
        case .pane(let workingDir, let command):
            let resolved = Self.absolutePath(workingDir, rootPath: rootPath)
            let surface = Surface(workingDir: resolved, command: command)
            if let command { commands[surface.id] = command }
            return .leaf(surface)
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction: direction, ratio: ratio,
                first: surfaceNode(from: first, rootPath: rootPath, commands: &commands),
                second: surfaceNode(from: second, rootPath: rootPath, commands: &commands))
        }
    }

    private static func absolutePath(_ workingDir: String, rootPath: String) -> String {
        let candidate: String
        if workingDir == "." || workingDir.isEmpty {
            candidate = rootPath
        } else if workingDir.hasPrefix("/") {
            candidate = workingDir
        } else {
            candidate = (rootPath as NSString).appendingPathComponent(workingDir)
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory)
        return (exists && isDirectory.boolValue) ? candidate : rootPath
    }
}
