import Foundation

/// Maps between the live `TabList`/`PaneTree` model and the persisted `Workspace`.
///
/// All tabs are wrapped in a single default `Project`/`Session` for now;
/// richer project modeling is deferred to a later slice.
public enum SessionSnapshot {

    // MARK: - Constants

    private static let defaultProjectName = "default"
    private static let defaultProjectRootPath = NSHomeDirectory()
    private static let defaultSessionTitle  = "default"

    // MARK: - TabList → Workspace

    /// Converts a `TabList` into a `Workspace` ready for persistence.
    ///
    /// Each tab's `PaneTree.layout` becomes a `Tab(title:layout:)`.
    /// All tabs are grouped under one default `Project` → `Session`.
    public static func workspace(from tabList: TabList) -> Workspace {
        let tabs = tabList.trees.enumerated().map { index, tree in
            Tab(title: "Tab \(index + 1)", layout: tree.layout)
        }
        let session = Session(title: defaultSessionTitle, tabs: tabs)
        let project = Project(
            name: defaultProjectName,
            rootPath: defaultProjectRootPath,
            preserveSessions: true,
            sessions: [session]
        )
        return Workspace(projects: [project])
    }

    // MARK: - Workspace → [PaneTree]

    /// Converts a persisted `Workspace` back into an array of `PaneTree`s.
    ///
    /// Each `Tab.layout` in the first project's first session becomes a
    /// `PaneTree(layout:focusedSurfaceID:)` with focus set to the first surface.
    ///
    /// Returns `[]` when the workspace has no projects, sessions, or tabs
    /// (the caller falls back to a fresh single-tab layout).
    public static func paneTrees(from workspace: Workspace) -> [PaneTree] {
        guard
            let project = workspace.projects.first,
            let session = project.sessions.first,
            !session.tabs.isEmpty
        else { return [] }

        return session.tabs.map { tab in
            let firstID = tab.layout.surfaces.first?.id
            return PaneTree(layout: tab.layout, focusedSurfaceID: firstID)
        }
    }
}
