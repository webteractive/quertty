# Per-Project Settings v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Projects can carry their own name, color, icon, and tri-state overrides of the global preserve-sessions and notification settings, edited from a sidebar context-menu sheet (design doc v1 scope).

**Architecture:** A pure `ProjectSettings` model + `ProjectSettingsStore` (private JSON in Application Support, keyed by canonical rootPath, mirroring `WorkspaceStore`) + a pure resolver applying the precedence chain. The app layer threads resolved values into the existing seams: `applySessionPreservation`'s command provider (per-pane lookup via a new `WorkspaceModel.project(containing:)`), the needs-attention fire site (which already has the project in scope), and `SidebarProject`/`ProjectCellView` for identity. UI is a `Rename…` NSAlert sheet plus a `ProjectSettingsSheetController` following `SettingsWindowController`'s programmatic-AppKit + ZTheme idiom.

**Tech Stack:** Swift 6, swift-testing (`@Test`/`#expect`), AppKit (programmatic), Tuist.

**Spec:** `docs/plans/2026-07-04-per-project-settings-design.md` (v1 rollout items 1–4 only; theme override, layout templates, `.zetty/project.json`, and env vars are v2/v3).

## Global Constraints

- `ZettyCore` stays pure — no AppKit imports. No debug `NSLog`/`print` committed.
- **Commits require Glen's explicit OK — ask once before the first commit.** No `Co-Authored-By`, no session links, never push, no tag/release.
- New app-layer files require `mise exec -- tuist generate --no-open` (run `mise exec -- tuist clean` first if generate fails with the bogus "Manifest not found" error).
- Fast pure-core test loop: `swift test`. App build: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`.
- DESIGN.md rules: never hardcode a color outside `Theme.swift` tokens; project color must not repurpose the accent or the semantic status colors (green/yellow/red/purple); chrome fonts via `ZTheme.monoFont` for terminal-adjacent UI, system font for controls.
- Precedence (design): project private override → global config → built-in default. (The repo file layer is v2.)
- Notifications tri-state semantics: `nil` = follow the global `notify-sound`/`notify-badge`/`notify-system`; `false` = suppress all three for the project; `true` = force all three. The in-app bell/inbox and the yellow status dot are NEVER gated.

---

### Task 1: `ProjectSettings` model + `ProjectSettingsStore`

**Files:**
- Create: `Sources/ZettyCore/Settings/ProjectSettings.swift`
- Create: `Sources/ZettyCore/Settings/ProjectSettingsStore.swift`
- Test: `Tests/ZettyCoreTests/ProjectSettingsTests.swift`

**Interfaces:**
- Produces:
  - `ProjectSettings` (Codable/Sendable/Equatable): `name: String?`, `color: String?` (curated palette id), `icon: String?` (SF Symbol name), `preserveSessionsOverride: Bool?`, `notificationsOverride: Bool?`, memberwise `init` with all-nil defaults, `var isEmpty: Bool`.
  - `ProjectSettingsFile` (Codable/Sendable/Equatable): `schemaVersion: Int` (1), `settings: [String: ProjectSettings]`; `func settings(for rootPath: String) -> ProjectSettings?`; `mutating func set(_:for:)` (drops empty entries); `var anyPreserveOverrideOn: Bool`.
  - `ProjectSettingsStore`: `init(directory: URL)` (file `project-settings.json`), `static func canonicalKey(_ rootPath: String) -> String`, `func load() -> ProjectSettingsFile` (missing OR corrupt → empty; settings are non-critical, a bad file must never brick launch — deliberate deviation from `WorkspaceStore`'s throwing load), `func save(_:) throws` (prettyPrinted+sortedKeys, atomic).

- [ ] **Step 1: Write the failing tests**

Create `Tests/ZettyCoreTests/ProjectSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import ZettyCore

@Test func projectSettingsRoundTripsThroughJSON() throws {
    let settings = ProjectSettings(
        name: "API", color: "teal", icon: "server.rack",
        preserveSessionsOverride: true, notificationsOverride: false)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ProjectSettings.self, from: data)
    #expect(decoded == settings)
}

@Test func projectSettingsDecodesForwardCompatibly() throws {
    // Fields added later (or written by a newer version) must not break decode.
    let json = #"{"name":"API","futureField":42}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ProjectSettings.self, from: json)
    #expect(decoded.name == "API")
    #expect(decoded.preserveSessionsOverride == nil)
}

@Test func projectSettingsIsEmptyWhenAllNil() {
    #expect(ProjectSettings().isEmpty)
    #expect(!ProjectSettings(name: "x").isEmpty)
    #expect(!ProjectSettings(notificationsOverride: false).isEmpty)
}

@Test func canonicalKeyNormalizesPaths() {
    let home = NSHomeDirectory()
    #expect(ProjectSettingsStore.canonicalKey("~/AI/zetty") == "\(home)/AI/zetty")
    #expect(ProjectSettingsStore.canonicalKey("/tmp/x/") == "/private/tmp/x")
    #expect(ProjectSettingsStore.canonicalKey("/a/b/../c") == "/a/c")
}

@Test func settingsFileLookupUsesCanonicalKeys() {
    var file = ProjectSettingsFile()
    file.set(ProjectSettings(name: "Zetty"), for: "\(NSHomeDirectory())/AI/zetty/")
    #expect(file.settings(for: "~/AI/zetty")?.name == "Zetty")
}

@Test func settingsFileDropsEmptyEntries() {
    var file = ProjectSettingsFile()
    file.set(ProjectSettings(name: "X"), for: "/a")
    file.set(ProjectSettings(), for: "/a")   // cleared → entry removed
    #expect(file.settings(for: "/a") == nil)
    #expect(file.settings.isEmpty)
}

@Test func anyPreserveOverrideOnDetectsOnlyTrue() {
    var file = ProjectSettingsFile()
    #expect(!file.anyPreserveOverrideOn)
    file.set(ProjectSettings(preserveSessionsOverride: false), for: "/a")
    #expect(!file.anyPreserveOverrideOn)
    file.set(ProjectSettings(preserveSessionsOverride: true), for: "/b")
    #expect(file.anyPreserveOverrideOn)
}

@Test func storeRoundTripsAndToleratesMissingOrCorruptFile() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-ps-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ProjectSettingsStore(directory: dir)

    #expect(store.load() == ProjectSettingsFile())          // missing → empty

    var file = ProjectSettingsFile()
    file.set(ProjectSettings(name: "API", color: "sky"), for: "/work/api")
    try store.save(file)
    #expect(store.load() == file)                           // round-trip

    try "not json".write(to: dir.appendingPathComponent("project-settings.json"),
                         atomically: true, encoding: .utf8)
    #expect(store.load() == ProjectSettingsFile())          // corrupt → empty, no throw
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProjectSettings`
Expected: FAIL — compile error, `ProjectSettings` type not found.

- [ ] **Step 3: Implement the model**

Create `Sources/ZettyCore/Settings/ProjectSettings.swift`:

```swift
import Foundation

/// Per-project overrides of global defaults plus project-only identity.
/// Every field is optional; `nil` = "follow global" (for overrides) or
/// "feature off" (for project-only fields). Decoding is tolerant so fields
/// added later never break older files.
public struct ProjectSettings: Codable, Sendable, Equatable {
    /// Display-name override; nil/empty → the folder name.
    public var name: String?
    /// Curated palette id (see the app layer's project palette); nil → no color.
    public var color: String?
    /// SF Symbol name for the row glyph; nil → the default diamond.
    public var icon: String?
    /// Tri-state override of the global `preserve-sessions` (nil = follow).
    public var preserveSessionsOverride: Bool?
    /// Tri-state notifications override: nil = follow the global
    /// notify-sound/badge/system keys; false = suppress all three for this
    /// project; true = force all three. The in-app bell is never gated.
    public var notificationsOverride: Bool?

    public init(
        name: String? = nil,
        color: String? = nil,
        icon: String? = nil,
        preserveSessionsOverride: Bool? = nil,
        notificationsOverride: Bool? = nil
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.preserveSessionsOverride = preserveSessionsOverride
        self.notificationsOverride = notificationsOverride
    }

    /// True when every field is nil — the store drops such entries.
    public var isEmpty: Bool { self == ProjectSettings() }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        preserveSessionsOverride = try c.decodeIfPresent(Bool.self, forKey: .preserveSessionsOverride)
        notificationsOverride = try c.decodeIfPresent(Bool.self, forKey: .notificationsOverride)
    }
}

/// The on-disk shape of `project-settings.json`: settings keyed by the
/// project's canonical absolute rootPath (survives remove-and-re-add, the
/// durable identity a user thinks in — see the design doc's storage section).
public struct ProjectSettingsFile: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var settings: [String: ProjectSettings]

    public init(schemaVersion: Int = 1, settings: [String: ProjectSettings] = [:]) {
        self.schemaVersion = schemaVersion
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        settings = try c.decodeIfPresent([String: ProjectSettings].self, forKey: .settings) ?? [:]
    }

    public func settings(for rootPath: String) -> ProjectSettings? {
        settings[ProjectSettingsStore.canonicalKey(rootPath)]
    }

    /// Stores (or, when `newSettings.isEmpty`, removes) a project's entry.
    public mutating func set(_ newSettings: ProjectSettings, for rootPath: String) {
        let key = ProjectSettingsStore.canonicalKey(rootPath)
        if newSettings.isEmpty {
            settings.removeValue(forKey: key)
        } else {
            settings[key] = newSettings
        }
    }

    /// True when at least one project forces preserve-sessions ON — the
    /// session-command provider must then be installed even if the global
    /// toggle is off.
    public var anyPreserveOverrideOn: Bool {
        settings.values.contains { $0.preserveSessionsOverride == true }
    }
}
```

Create `Sources/ZettyCore/Settings/ProjectSettingsStore.swift`:

```swift
import Foundation

/// Load/save for the private per-user project-settings file, mirroring
/// `WorkspaceStore` (same directory, JSON, atomic pretty-printed writes).
/// Unlike the workspace, settings are non-critical: `load()` returns an
/// empty file on ANY failure — a bad settings file must never brick launch.
public struct ProjectSettingsStore {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("project-settings.json")
    }

    /// Normalizes a project rootPath into the dictionary key: tilde expanded,
    /// `.`/`..` and symlink-free standardized form, no trailing slash.
    public static func canonicalKey(_ rootPath: String) -> String {
        var path = (rootPath as NSString).expandingTildeInPath
        path = (path as NSString).standardizingPath
        path = URL(fileURLWithPath: path).standardizedFileURL
            .resolvingSymlinksInPath().path
        return path
    }

    public func load() -> ProjectSettingsFile {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(ProjectSettingsFile.self, from: data)
        else { return ProjectSettingsFile() }
        return file
    }

    public func save(_ file: ProjectSettingsFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all PASS. If `canonicalKeyNormalizesPaths` fails on the `/tmp` expectation because of symlink resolution differences, that test documents macOS behavior (`/tmp` → `/private/tmp`); adjust the expectation only to match `resolvingSymlinksInPath()` reality, never by removing the normalization.

- [ ] **Step 5: Commit (after Glen's OK per Global Constraints)**

```bash
git add Sources/ZettyCore/Settings Tests/ZettyCoreTests/ProjectSettingsTests.swift
git commit -m "feat(core): per-project settings model + private store"
```

---

### Task 2: Effective-settings resolver

**Files:**
- Create: `Sources/ZettyCore/Settings/ProjectSettingsResolver.swift`
- Test: `Tests/ZettyCoreTests/ProjectSettingsResolverTests.swift`

**Interfaces:**
- Consumes: `ProjectSettings` (Task 1), `AppConfig` (existing: `preserveSessions`, `notifySound`, `notifyBadge`, `notifySystem`).
- Produces:
  - `ResolvedProjectSettings` (Equatable/Sendable): `name: String`, `colorID: String?`, `icon: String?`, `preserveSessions: Bool`, `notifySound: Bool`, `notifyBadge: Bool`, `notifySystem: Bool`.
  - `ProjectSettingsResolver.resolve(_ settings: ProjectSettings?, fallbackName: String, global: AppConfig) -> ResolvedProjectSettings`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ZettyCoreTests/ProjectSettingsResolverTests.swift`:

```swift
import Testing
@testable import ZettyCore

@Test func resolverFallsBackToGlobalsWhenUnset() {
    let global = AppConfig(preserveSessions: true, notifySound: true,
                           notifyBadge: false, notifySystem: true)
    let r = ProjectSettingsResolver.resolve(nil, fallbackName: "zetty", global: global)
    #expect(r.name == "zetty")
    #expect(r.colorID == nil)
    #expect(r.icon == nil)
    #expect(r.preserveSessions == true)
    #expect(r.notifySound == true)
    #expect(r.notifyBadge == false)   // follows each global channel individually
    #expect(r.notifySystem == true)
}

@Test func resolverAppliesNameOverrideUnlessBlank() {
    let global = AppConfig()
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(name: "API Server"), fallbackName: "api", global: global).name == "API Server")
    // Blank/whitespace override falls back — a cleared field means "no override".
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(name: "  "), fallbackName: "api", global: global).name == "api")
}

@Test func resolverPreserveSessionsTriState() {
    let globalOn = AppConfig(preserveSessions: true)
    let globalOff = AppConfig(preserveSessions: false)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(preserveSessionsOverride: false), fallbackName: "x", global: globalOn).preserveSessions == false)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(preserveSessionsOverride: true), fallbackName: "x", global: globalOff).preserveSessions == true)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(), fallbackName: "x", global: globalOn).preserveSessions == true)
}

@Test func resolverNotificationsTriState() {
    let global = AppConfig(notifySound: true, notifyBadge: false, notifySystem: true)
    // Off suppresses all three regardless of globals.
    let off = ProjectSettingsResolver.resolve(
        ProjectSettings(notificationsOverride: false), fallbackName: "x", global: global)
    #expect(off.notifySound == false && off.notifyBadge == false && off.notifySystem == false)
    // On forces all three regardless of globals.
    let on = ProjectSettingsResolver.resolve(
        ProjectSettings(notificationsOverride: true), fallbackName: "x", global: global)
    #expect(on.notifySound == true && on.notifyBadge == true && on.notifySystem == true)
    // nil follows each channel.
    let follow = ProjectSettingsResolver.resolve(
        ProjectSettings(), fallbackName: "x", global: global)
    #expect(follow.notifySound == true && follow.notifyBadge == false && follow.notifySystem == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter Resolver`
Expected: FAIL — compile error, `ProjectSettingsResolver` not found.

- [ ] **Step 3: Implement the resolver**

Create `Sources/ZettyCore/Settings/ProjectSettingsResolver.swift`:

```swift
import Foundation

/// What actually applies to a project right now — the precedence chain
/// (project private override → global config → built-in default) collapsed
/// into concrete values. The app layer asks this one place instead of
/// re-implementing precedence at every seam.
public struct ResolvedProjectSettings: Equatable, Sendable {
    public var name: String
    public var colorID: String?
    public var icon: String?
    public var preserveSessions: Bool
    public var notifySound: Bool
    public var notifyBadge: Bool
    public var notifySystem: Bool
}

public enum ProjectSettingsResolver {

    public static func resolve(
        _ settings: ProjectSettings?,
        fallbackName: String,
        global: AppConfig
    ) -> ResolvedProjectSettings {
        let trimmedName = settings?.name?.trimmingCharacters(in: .whitespaces)
        let name = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? fallbackName

        // Tri-state notifications: false suppresses all channels, true forces
        // all, nil follows each global channel individually.
        let notifySound: Bool
        let notifyBadge: Bool
        let notifySystem: Bool
        switch settings?.notificationsOverride {
        case .some(let forced):
            notifySound = forced
            notifyBadge = forced
            notifySystem = forced
        case .none:
            notifySound = global.notifySound
            notifyBadge = global.notifyBadge
            notifySystem = global.notifySystem
        }

        return ResolvedProjectSettings(
            name: name,
            colorID: settings?.color,
            icon: settings?.icon,
            preserveSessions: settings?.preserveSessionsOverride ?? global.preserveSessions,
            notifySound: notifySound,
            notifyBadge: notifyBadge,
            notifySystem: notifySystem
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add Sources/ZettyCore/Settings/ProjectSettingsResolver.swift Tests/ZettyCoreTests/ProjectSettingsResolverTests.swift
git commit -m "feat(core): effective project-settings resolver"
```

---

### Task 3: `WorkspaceModel` helpers — surface→project lookup + rename

**Files:**
- Modify: `Sources/ZettyCore/Model/WorkspaceModel.swift` (add two methods after `togglePin(at:)`, ~line 75)
- Test: `Tests/ZettyCoreTests/WorkspaceModelTests.swift` (append)

**Interfaces:**
- Consumes: existing `ProjectRuntime` (`tabList.trees[].layout.surfaces`), private `resort()`.
- Produces: `func project(containing surfaceID: UUID) -> ProjectRuntime?` and `func rename(projectAt index: Int, to newName: String)` (renames, resorts pinned-first/by-name, preserves the active project by identity — same contract as `togglePin`).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ZettyCoreTests/WorkspaceModelTests.swift` (match the file's existing helper style for constructing a model — read the file's top before writing; it already builds `WorkspaceModel`s in other tests):

```swift
@Test func projectContainingSurfaceFindsOwner() {
    let model = WorkspaceModel()
    let second = model.addProject(name: "beta", rootPath: "/tmp/beta")
    let surfaceID = second.tabList.trees[0].layout.surfaces[0].id
    #expect(model.project(containing: surfaceID) === second)
    #expect(model.project(containing: UUID()) == nil)
}

@Test func renameProjectResortsAndKeepsActiveIdentity() {
    let model = WorkspaceModel()
    let zebra = model.addProject(name: "zebra", rootPath: "/tmp/zebra")
    model.addProject(name: "alpha", rootPath: "/tmp/alpha")
    // Active is "alpha" (last added). Rename zebra → "aaa": it must sort first
    // while the active project stays "alpha" by identity.
    guard let zebraIndex = model.projects.firstIndex(where: { $0 === zebra }) else {
        Issue.record("zebra missing"); return
    }
    model.rename(projectAt: zebraIndex, to: "aaa")
    #expect(model.projects.first?.name == "aaa")
    #expect(model.activeProject.name == "alpha")
    // Out-of-range index is a no-op.
    model.rename(projectAt: 99, to: "nope")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter projectContainingSurface`
Expected: FAIL — compile error, no member `project(containing:)`.

- [ ] **Step 3: Implement the helpers**

In `Sources/ZettyCore/Model/WorkspaceModel.swift`, after `togglePin(at:)`:

```swift
    /// The project owning `surfaceID`, or nil. Used by the app layer to
    /// resolve per-project settings at pane-spawn time.
    public func project(containing surfaceID: UUID) -> ProjectRuntime? {
        projects.first { project in
            project.tabList.trees.contains { tree in
                tree.layout.surfaces.contains { $0.id == surfaceID }
            }
        }
    }

    /// Renames a project and re-sorts (name participates in sidebar order);
    /// the active project is preserved by identity, like `togglePin`.
    public func rename(projectAt index: Int, to newName: String) {
        guard projects.indices.contains(index) else { return }
        projects[index].name = newName
        resort()
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add Sources/ZettyCore/Model/WorkspaceModel.swift Tests/ZettyCoreTests/WorkspaceModelTests.swift
git commit -m "feat(core): surface-to-project lookup + project rename on WorkspaceModel"
```

---

### Task 4: App wiring — store load, name overrides, per-project preserve-sessions

**Files:**
- Modify: `App/Sources/App/AppDelegate.swift` (store property near `workspaceStore` ~line 52; launch sequence ~line 95; `applySessionPreservation` ~line 399)

**Interfaces:**
- Consumes: `ProjectSettingsStore`/`ProjectSettingsFile` (Task 1), `ProjectSettingsResolver` (Task 2), `WorkspaceModel.project(containing:)` (Task 3), existing `SessionPersistence.attachCommand(zmxPath:surfaceID:restoreScriptPath:)`.
- Produces (used by Tasks 5–8):
  - `private(set) var projectSettings: ProjectSettingsFile` + `private lazy var projectSettingsStore`
  - `func resolvedSettings(for project: ProjectRuntime) -> ResolvedProjectSettings`
  - `func updateProjectSettings(_ new: ProjectSettings, for project: ProjectRuntime)` — persists, re-applies name + session preservation, refreshes chrome.

- [ ] **Step 1: Add the store and resolved-settings helper**

In `AppDelegate.swift`, extract the shared Application Support directory and add the settings store next to `workspaceStore` (replace the existing `workspaceStore` lazy with):

```swift
    /// `~/Library/Application Support/zetty/` (created on first use) — shared
    /// by the workspace and project-settings stores.
    private lazy var appSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("zetty")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The persistent workspace store backed by `~/Library/Application Support/zetty/`.
    private lazy var workspaceStore = WorkspaceStore(directory: appSupportDirectory)

    /// Private per-project settings (identity + overrides), keyed by rootPath.
    private lazy var projectSettingsStore = ProjectSettingsStore(directory: appSupportDirectory)

    /// In-memory project settings; loaded at launch, saved on every edit.
    private(set) var projectSettings = ProjectSettingsFile()
```

Add the resolver + update helpers (near `applySessionPreservation`):

```swift
    // MARK: - Per-project settings

    /// What applies to `project` right now (private override → global).
    /// The fallback name is the folder name, NOT the runtime name — the
    /// runtime name may already carry the override.
    func resolvedSettings(for project: ProjectRuntime) -> ResolvedProjectSettings {
        ProjectSettingsResolver.resolve(
            projectSettings.settings(for: project.rootPath),
            fallbackName: (project.rootPath as NSString).lastPathComponent,
            global: appConfig)
    }

    /// Persists new settings for `project` and re-applies everything they
    /// influence: runtime name (+ sidebar re-sort), session preservation for
    /// future panes, and chrome refresh. Notifications are resolved at fire
    /// time, so no re-apply is needed there.
    func updateProjectSettings(_ new: ProjectSettings, for project: ProjectRuntime) {
        projectSettings.set(new, for: project.rootPath)
        try? projectSettingsStore.save(projectSettings)
        guard let tvc = terminalViewController else { return }
        if let index = tvc.workspace.projects.firstIndex(where: { $0 === project }) {
            tvc.workspace.rename(projectAt: index, to: resolvedSettings(for: project).name)
        }
        applySessionPreservation(to: tvc)
        tvc.refreshSidebar()
        tvc.refreshTabBar()
        scheduleSave()   // runtime name persists via the workspace snapshot
    }

    /// Applies stored name overrides to the restored runtimes (called once
    /// right after the workspace is restored, before the first sidebar render).
    private func applyProjectNameOverrides(to tvc: TerminalViewController) {
        for (index, project) in tvc.workspace.projects.enumerated() {
            let resolved = resolvedSettings(for: project)
            if resolved.name != project.name {
                tvc.workspace.rename(projectAt: index, to: resolved.name)
            }
        }
    }
```

- [ ] **Step 2: Load and apply at launch**

In `applicationDidFinishLaunching`, right after `let restoredFromDisk = restoreWorkspace(into: tvc)` (~line 97):

```swift
        projectSettings = projectSettingsStore.load()
        applyProjectNameOverrides(to: tvc)
```

- [ ] **Step 3: Per-project preserve-sessions in the command provider**

Replace the enabled branch of `applySessionPreservation(to:)`:

```swift
    private func applySessionPreservation(to tvc: TerminalViewController) {
        let zmxPath = ZmxRunner.locate()

        // The provider must be installed if ANY project can preserve — the
        // global toggle or a per-project override forcing it on. The
        // per-pane decision happens inside the closure at spawn time.
        let anyPreserve = appConfig.preserveSessions || projectSettings.anyPreserveOverrideOn
        if anyPreserve, let zmx = zmxPath {
            let restoreScript = appConfig.restoreScrollback ? ScrollbackRestore.ensureScript() : nil
            tvc.sessionCommandProvider = { [weak self, weak tvc] id in
                guard let self else { return nil }
                // Resolve the owning project's effective value; a surface not
                // yet in the model (shouldn't happen) follows the global.
                if let project = tvc?.workspace.project(containing: id) {
                    guard self.resolvedSettings(for: project).preserveSessions else { return nil }
                } else {
                    guard self.appConfig.preserveSessions else { return nil }
                }
                return SessionPersistence.attachCommand(
                    zmxPath: zmx, surfaceID: id, restoreScriptPath: restoreScript)
            }
        } else {
            tvc.sessionCommandProvider = nil
            if anyPreserve { presentZmxMissingAlertOnce() }
        }

        if let zmx = zmxPath {
            tvc.onSurfacesClosed = { ids in
                ZmxRunner.kill(sessions: ids.map(SessionPersistence.sessionName(for:)), zmxPath: zmx)
            }
        } else {
            tvc.onSurfacesClosed = nil
        }
    }
```

Check `TerminalViewController.workspace` and `refreshSidebar`/`refreshTabBar` access: they are internal (`var workspace`, `func refreshSidebar()` at ~1445, `func refreshTabBar()` at ~1417) — same module, callable. If `workspace` turns out to be `private`, change it to `private(set) var workspace` (internal read).

- [ ] **Step 4: Build and run the full suite**

```bash
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
swift test
```
Expected: `** BUILD SUCCEEDED **`, all tests PASS. (No new file yet — no tuist regenerate needed for this task.)

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/AppDelegate.swift
git commit -m "feat: load project settings and honor per-project preserve-sessions"
```

---

### Task 5: Notifications gating (sound, system banners, dock badge)

**Files:**
- Modify: `App/Sources/App/TerminalViewController.swift` (`onAgentNeedsAttention` ~line 789, fire site ~line 808, `publishAttentionCount` ~line 833; new `badgeEligible` closure)
- Modify: `App/Sources/App/AppDelegate.swift` (`agentNeedsAttention` ~line 497, wiring ~line 121)

**Interfaces:**
- Consumes: `resolvedSettings(for:)` (Task 4), `AttentionInbox.unread: Set<UUID>` (existing).
- Produces: `TerminalViewController.onAgentNeedsAttention: ((Surface, AgentKind, ProjectRuntime) -> Void)?` (signature change), `TerminalViewController.badgeEligible: ((ProjectRuntime) -> Bool)?`, `onAttentionCountChanged` now receives the **badge-eligible** unread count (bell keeps the full count).

- [ ] **Step 1: Forward the project, not just its name**

In `TerminalViewController.swift` change the callback declaration (~line 789):

```swift
    /// Fired when a pane's agent transitions INTO needs-attention (never
    /// during the startup replay). Payload: pane surface, agent kind, and the
    /// owning project (per-project notification overrides are resolved by the
    /// receiver).
    var onAgentNeedsAttention: ((Surface, AgentKind, ProjectRuntime) -> Void)?
```

and the fire site inside `handleAgentEvents` (~line 808):

```swift
                            if notify, next.status == .needsAttention, previous != .needsAttention,
                               let kind = next.kind {
                                onAgentNeedsAttention?(surface, kind, project)
                            }
```

- [ ] **Step 2: Badge-eligible count (bell/inbox unaffected)**

Add a filter closure near `onAttentionCountChanged` and rework `publishAttentionCount`:

```swift
    /// Per-project dock-badge gate (nil → everything counts). The in-app
    /// bell/inbox always sees every unread pane — only the Dock badge is
    /// filtered (a suppressed project shouldn't nag from the Dock).
    var badgeEligible: ((ProjectRuntime) -> Bool)?

    /// Recomputes the UNREAD attention count and fires the callback — always,
    /// so a config reload can re-apply Dock-badge gating even when the count
    /// itself is unchanged (re-setting the same badge is free). Syncs the
    /// inbox first so ended attention episodes drop their read marks. The
    /// bell shows every unread pane; the Dock badge only badge-eligible ones.
    func publishAttentionCount() {
        let needsAttention = Set(
            workspace.projects
                .flatMap { $0.tabList.trees.flatMap { $0.layout.surfaces } }
                .filter { agentDetector.state(for: $0.id).status == .needsAttention }
                .map(\.id)
        )
        attentionInbox.update(needsAttention: needsAttention)
        sidebarView?.updateBell(count: attentionInbox.unreadCount)

        let unread = attentionInbox.unread
        let badgeCount = workspace.projects
            .filter { badgeEligible?($0) ?? true }
            .flatMap { $0.tabList.trees.flatMap { $0.layout.surfaces } }
            .filter { unread.contains($0.id) }
            .count
        onAttentionCountChanged?(badgeCount)
    }
```

- [ ] **Step 3: Gate sound/system in AppDelegate**

Update the wiring in `applicationDidFinishLaunching` (~line 121):

```swift
        tvc.onAgentNeedsAttention = { [weak self] surface, kind, project in
            self?.agentNeedsAttention(surface: surface, kind: kind, project: project)
        }
        tvc.badgeEligible = { [weak self] project in
            self?.resolvedSettings(for: project).notifyBadge ?? true
        }
```

and replace `agentNeedsAttention` (~line 497) — the resolved values fold the global keys, so the old `appConfig.notifySound`/`notifySystem` reads are replaced, not supplemented:

```swift
    private func agentNeedsAttention(surface: Surface, kind: AgentKind, project: ProjectRuntime) {
        let resolved = resolvedSettings(for: project)
        if resolved.notifySound {
            NSSound(named: "Ping")?.play()
            if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        }
        guard resolved.notifySystem, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(kind.displayName.capitalized) needs attention"
            content.body = "\(project.name) — \(surface.workingDir)"
            content.userInfo = ["pane": SessionPersistence.shortID(for: surface.id)]
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
```

The dock-badge sink (~line 124) keeps its `appConfig.notifyBadge` global gate — per-project filtering already happened in the count:

```swift
        tvc.onAttentionCountChanged = { [weak self] count in
            guard let self else { return }
            NSApp.dockTile.badgeLabel = (self.appConfig.notifyBadge && count > 0) ? "\(count)" : nil
        }
```

(Leave this closure as-is; it is shown for context.)

- [ ] **Step 4: Build + tests**

```bash
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
swift test
```
Expected: `** BUILD SUCCEEDED **`, all PASS.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat: per-project notification gating (sound, banners, dock badge)"
```

---

### Task 6: Curated project palette + sidebar color/icon

**Files:**
- Modify: `App/Sources/App/Theme.swift` (static palette + lookup, near the `color(_:)` helper ~line 340)
- Modify: `App/Sources/App/SidebarView.swift` (`SidebarProject` ~line 10, `viewFor` call site ~line 688, `ProjectCellView.configure` ~line 895)
- Modify: `App/Sources/App/TerminalViewController.swift` (`refreshSidebar` `SidebarProject` construction ~line 1485; new `projectIdentity` closure)
- Modify: `App/Sources/App/AppDelegate.swift` (wire the closure)

**Interfaces:**
- Consumes: `resolvedSettings(for:)` (Task 4).
- Produces: `ZTheme.projectPalette: [(id: String, hex: String)]`, `ZTheme.projectColor(id: String?) -> NSColor?`, `SidebarProject.projectColor: NSColor?` + `.customGlyph: String?`, `TerminalViewController.projectIdentity: ((ProjectRuntime) -> (color: NSColor?, glyph: String?))?`. Task 8's sheet reuses `ZTheme.projectPalette` for its swatches.

- [ ] **Step 1: Palette tokens in Theme.swift**

Add near the `color(_:)` helper:

```swift
    // MARK: - Project identity palette

    /// Curated per-project colors (design doc: a fixed palette, not free hex).
    /// Deliberately offset from the semantic status hues — green (running),
    /// yellow (attention), red (error), purple (git) — and from the accent,
    /// which stays reserved for focus/brand. Values read on both dark and
    /// light `bg1`. Stored in project settings by `id` so the hex can be
    /// tuned later without re-assigning anyone's projects.
    static let projectPalette: [(id: String, hex: String)] = [
        ("sky",    "5b9dd9"),
        ("teal",   "4fa8a8"),
        ("moss",   "7fa86f"),
        ("sand",   "c2a377"),
        ("orange", "d98a4f"),
        ("pink",   "d97fa8"),
        ("mauve",  "b08ac9"),
        ("steel",  "8a97a6"),
    ]

    /// The NSColor for a stored palette id; nil for nil/unknown ids (a
    /// removed palette entry degrades to "no color", never an error).
    static func projectColor(id: String?) -> NSColor? {
        guard let id, let entry = projectPalette.first(where: { $0.id == id }) else { return nil }
        return color(entry.hex)
    }
```

- [ ] **Step 2: Thread color + glyph through SidebarProject**

In `SidebarView.swift`, extend the struct (~line 10):

```swift
struct SidebarProject {
    let name: String
    let isPinned: Bool
    let tabTitles: [String]              // .count >= 2 → expandable
    let tabStatuses: [AgentStatus?]      // parallel to tabTitles (agent status per tab)
    let tabIcons: [NSImage?]             // parallel to tabTitles (tool logo per tab)
    let icon: NSImage?                   // single-tab projects: the pane's tool logo
    let status: AgentStatus?             // project roll-up (most-severe across tabs)
    let projectColor: NSColor?           // per-project identity color (nil = default)
    let customGlyph: String?             // SF Symbol overriding the diamond (nil = default)
}
```

Update `ProjectCellView.configure` (~line 895) — signature gains the two fields; the glyph honors the custom symbol and the tint precedence is **status > project color > active/dim** (status colors carry meaning and always win):

```swift
    func configure(name: String, isPinned: Bool, isActive: Bool, agentStatus: AgentStatus?,
                   toolIcon: NSImage? = nil, projectColor: NSColor? = nil,
                   customGlyph: String? = nil, projectIndex: Int,
                   target: AnyObject, action: Selector) {
        nameLabel.stringValue = name
        nameLabel.textColor = isActive ? ZTheme.current.fgColor : ZTheme.current.fg2Color

        // Single-tab projects surface the pane's tool logo on the row itself
        // (multi-tab projects show logos on their tab child rows instead).
        toolIconView.image = toolIcon
        toolIconView.contentTintColor = nameLabel.textColor
        toolIconWidth.constant = toolIcon == nil ? 0 : 13
        toolIconGap.constant = toolIcon == nil ? 0 : 6

        // Project glyph: a custom SF Symbol when set, else the diamond
        // (filled when an agent is present or the project is active). Tint
        // precedence: agent status > project color > active accent / dim.
        let hasAgent = agentStatus != nil
        let glyph = customGlyph ?? ((hasAgent || isActive) ? "diamond.fill" : "diamond")
        glyphView.image = NSImage(systemSymbolName: glyph, accessibilityDescription: "Project")
            ?? NSImage(systemSymbolName: (hasAgent || isActive) ? "diamond.fill" : "diamond",
                       accessibilityDescription: "Project")
        glyphView.contentTintColor = agentStatusColor(agentStatus)
            ?? projectColor
            ?? (isActive ? ZTheme.current.accentColor : ZTheme.current.fg3Color)

        // Pinned rows use a filled accent star; unpinned rows show a dim hollow star.
        let symbolName = isPinned ? "star.fill" : "star"
        if let image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: isPinned ? "Pinned" : "Pin") {
            pinButton.image = image
            pinButton.contentTintColor = isPinned
                ? ZTheme.current.accentColor
                : ZTheme.current.fg3Color
        } else {
            pinButton.title = isPinned ? "★" : "☆"
        }

        pinButton.tag = projectIndex
        pinButton.target = target
        pinButton.action = action
    }
```

Update the `viewFor` call site (~line 688) to pass the new fields:

```swift
            cellView.configure(
                name: project.name,
                isPinned: project.isPinned,
                isActive: p == activeProject,
                agentStatus: project.status,
                toolIcon: project.icon,
                projectColor: project.projectColor,
                customGlyph: project.customGlyph,
                projectIndex: p,
                target: self,
                action: #selector(pinButtonClicked(_:))
            )
```

- [ ] **Step 3: Resolve identity in refreshSidebar**

In `TerminalViewController.swift`, add the closure near the other callbacks:

```swift
    /// Resolves a project's identity (color + custom glyph) from its
    /// settings; nil closure or nil fields → default rendering.
    var projectIdentity: ((ProjectRuntime) -> (color: NSColor?, glyph: String?))?
```

and in `refreshSidebar`'s `SidebarProject` construction (~line 1485):

```swift
            let identity = projectIdentity?(project)
            return SidebarProject(
                name: project.name,
                isPinned: project.isPinned,
                tabTitles: tabTitles,
                tabStatuses: tabStatuses,
                tabIcons: tabIcons,
                icon: projectIcon,
                status: rollup,
                projectColor: identity?.color,
                customGlyph: identity?.glyph
            )
```

In `AppDelegate.applicationDidFinishLaunching` (with the other `tvc.` closures):

```swift
        tvc.projectIdentity = { [weak self] project in
            guard let self else { return (nil, nil) }
            let resolved = self.resolvedSettings(for: project)
            return (ZTheme.projectColor(id: resolved.colorID), resolved.icon)
        }
```

- [ ] **Step 4: Build + tests**

```bash
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
swift test
```
Expected: `** BUILD SUCCEEDED **`, all PASS. (Visual check comes in Task 9 — colors/icons need settings to exist first, via Task 8's sheet or a hand-written `project-settings.json`.)

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/Theme.swift App/Sources/App/SidebarView.swift App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat: project identity color + icon on sidebar rows"
```

---

### Task 7: Rename… context-menu item

**Files:**
- Modify: `App/Sources/App/SidebarView.swift` (callback ~line 102, `menuNeedsUpdate` ~line 528)
- Modify: `App/Sources/App/TerminalViewController.swift` (forward the callback, ~line 1500 where other sidebar callbacks are wired — locate the block wiring `onRemoveProject`)
- Modify: `App/Sources/App/AppDelegate.swift` (NSAlert rename sheet)

**Interfaces:**
- Consumes: `updateProjectSettings(_:for:)`, `projectSettings.settings(for:)` (Task 4).
- Produces: `SidebarView.onRenameProject: ((Int) -> Void)?`, `TerminalViewController.onRenameProject: ((ProjectRuntime) -> Void)?`.

- [ ] **Step 1: Menu item + callbacks**

In `SidebarView.swift`, next to `onRemoveProject` (~line 102):

```swift
    /// Rename the project at the given index (opens the rename prompt).
    var onRenameProject: ((Int) -> Void)?
```

In `menuNeedsUpdate` (~line 528), before the Remove item:

```swift
        let rename = NSMenuItem(title: "Rename\u{2026}",
                                action: #selector(renameProjectMenuClicked(_:)),
                                keyEquivalent: "")
        rename.target = self
        rename.tag = p
        menu.addItem(rename)

        menu.addItem(.separator())
```

and next to `removeProjectMenuClicked` (~line 519):

```swift
    @objc private func renameProjectMenuClicked(_ sender: NSMenuItem) {
        onRenameProject?(sender.tag)
    }
```

- [ ] **Step 2: Forward through the view controller**

In `TerminalViewController.swift`, add near `onAgentNeedsAttention`:

```swift
    /// Sidebar "Rename…" — payload is the project runtime (the receiver
    /// resolves and persists the name override).
    var onRenameProject: ((ProjectRuntime) -> Void)?
```

and where the sidebar callbacks are wired (same block as `sidebarView.onRemoveProject = …` — find it via `onRemoveProject =` in the file):

```swift
        sidebar.onRenameProject = { [weak self] index in
            guard let self, self.workspace.projects.indices.contains(index) else { return }
            self.onRenameProject?(self.workspace.projects[index])
        }
```

(Match the surrounding wiring style — if the existing block captures the sidebar variable differently, e.g. `sidebarView?.onRemoveProject`, mirror it.)

- [ ] **Step 3: The rename sheet in AppDelegate**

Add near `updateProjectSettings`:

```swift
    /// "Rename…" prompt: an NSAlert sheet with a text field (the established
    /// sheet pattern — see confirmRemoveProject). An empty submission clears
    /// the override, restoring the folder name.
    private func promptRenameProject(_ project: ProjectRuntime) {
        guard let window = terminalViewController?.view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Leave empty to use the folder name (\((project.rootPath as NSString).lastPathComponent))."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: project.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            var settings = self.projectSettings.settings(for: project.rootPath) ?? ProjectSettings()
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
            settings.name = trimmed.isEmpty ? nil : trimmed
            self.updateProjectSettings(settings, for: project)
        }
    }
```

and wire it in `applicationDidFinishLaunching` (with the other `tvc.` closures):

```swift
        tvc.onRenameProject = { [weak self] project in self?.promptRenameProject(project) }
```

- [ ] **Step 4: Build, then verify via the control CLI**

```bash
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`.

Functional check (after Task 9's install/relaunch — note it here, execute there): rename a project via the context menu, then `zetty status --json | grep '"name"'` shows the override; quit/relaunch → the override persists (from `project-settings.json`); rename to empty → folder name returns.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/SidebarView.swift App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat: rename project via sidebar context menu"
```

---

### Task 8: Project Settings… sheet

**Files:**
- Create: `App/Sources/App/ProjectSettingsSheet.swift`
- Modify: `App/Sources/App/SidebarView.swift` (menu item + callback, same seam as Task 7)
- Modify: `App/Sources/App/TerminalViewController.swift` (forward callback)
- Modify: `App/Sources/App/AppDelegate.swift` (present + save)

**Interfaces:**
- Consumes: `ZTheme.projectPalette` (Task 6), `ProjectSettings` (Task 1), `updateProjectSettings(_:for:)` (Task 4).
- Produces: `ProjectSettingsSheet.present(for:current:fallbackName:on:onSave:)`, `SidebarView.onOpenProjectSettings: ((Int) -> Void)?`, `TerminalViewController.onOpenProjectSettings: ((ProjectRuntime) -> Void)?`.

- [ ] **Step 1: Menu item + forwarding**

`SidebarView.swift` — callback next to `onRenameProject`:

```swift
    /// Open the per-project settings sheet for the project at the index.
    var onOpenProjectSettings: ((Int) -> Void)?
```

In `menuNeedsUpdate`, between Rename and the separator:

```swift
        let settings = NSMenuItem(title: "Project Settings\u{2026}",
                                  action: #selector(projectSettingsMenuClicked(_:)),
                                  keyEquivalent: "")
        settings.target = self
        settings.tag = p
        menu.addItem(settings)
```

```swift
    @objc private func projectSettingsMenuClicked(_ sender: NSMenuItem) {
        onOpenProjectSettings?(sender.tag)
    }
```

`TerminalViewController.swift` — mirror Task 7's forwarding:

```swift
    /// Sidebar "Project Settings…" — payload is the project runtime.
    var onOpenProjectSettings: ((ProjectRuntime) -> Void)?
```

```swift
        sidebar.onOpenProjectSettings = { [weak self] index in
            guard let self, self.workspace.projects.indices.contains(index) else { return }
            self.onOpenProjectSettings?(self.workspace.projects[index])
        }
```

- [ ] **Step 2: The sheet**

Create `App/Sources/App/ProjectSettingsSheet.swift`:

```swift
import AppKit
import ZettyCore

/// The per-project settings sheet (sidebar → Project Settings…). Programmatic
/// AppKit styled with ZTheme, following SettingsWindowController's idiom.
/// Purely an editor: reads a `ProjectSettings`, hands the edited copy to
/// `onSave` — persistence and re-application live in AppDelegate.
enum ProjectSettingsSheet {

    /// Curated SF Symbols offered as project icons (plus "Default").
    static let iconChoices: [String] = [
        "folder", "terminal", "hammer", "wrench.and.screwdriver", "globe",
        "server.rack", "shippingbox", "book", "flask", "bolt",
    ]

    static func present(
        for projectName: String,
        current: ProjectSettings,
        fallbackName: String,
        on window: NSWindow,
        onSave: @escaping (ProjectSettings) -> Void
    ) {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 0),
            styleMask: [.titled],
            backing: .buffered, defer: false)
        panel.title = "Project Settings — \(projectName)"
        panel.appearance = ZTheme.current.appearance
        panel.backgroundColor = ZTheme.current.bg1Color

        // Controls ------------------------------------------------------
        let nameField = NSTextField(string: current.name ?? "")
        nameField.placeholderString = fallbackName
        nameField.font = ZTheme.monoFont(size: 13)

        var swatchButtons: [NSButton] = []
        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 6
        var selectedColorID: String? = current.color
        func refreshSwatches() {
            for (index, button) in swatchButtons.enumerated() {
                let isNone = index == 0
                let id: String? = isNone ? nil : ZTheme.projectPalette[index - 1].id
                button.layer?.borderWidth = (id == selectedColorID) ? 2 : 0
            }
        }
        func makeSwatch(colorHex: String?, tooltip: String) -> NSButton {
            let button = NSButton(title: "", target: nil, action: nil)
            button.isBordered = false
            button.wantsLayer = true
            button.toolTip = tooltip
            button.layer?.cornerRadius = 9
            button.layer?.borderColor = ZTheme.current.fgColor.cgColor
            button.layer?.backgroundColor = colorHex.map { ZTheme.color($0).cgColor }
                ?? ZTheme.current.bg3Color.cgColor
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return button
        }
        let noneSwatch = makeSwatch(colorHex: nil, tooltip: "Default")
        swatchButtons.append(noneSwatch)
        colorRow.addArrangedSubview(noneSwatch)
        for entry in ZTheme.projectPalette {
            let swatch = makeSwatch(colorHex: entry.hex, tooltip: entry.id)
            swatchButtons.append(swatch)
            colorRow.addArrangedSubview(swatch)
        }
        for (index, button) in swatchButtons.enumerated() {
            button.target = SwatchTarget.shared
            button.action = #selector(SwatchTarget.clicked(_:))
            SwatchTarget.shared.handlers[ObjectIdentifier(button)] = {
                selectedColorID = index == 0 ? nil : ZTheme.projectPalette[index - 1].id
                refreshSwatches()
            }
        }
        refreshSwatches()

        let iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        iconPopup.addItem(withTitle: "Default")
        for symbol in iconChoices {
            iconPopup.addItem(withTitle: symbol)
            iconPopup.lastItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        }
        if let icon = current.icon, let index = iconChoices.firstIndex(of: icon) {
            iconPopup.selectItem(at: index + 1)
        }

        func triState(_ value: Bool?) -> NSSegmentedControl {
            let control = NSSegmentedControl(
                labels: ["Follow Global", "On", "Off"],
                trackingMode: .selectOne, target: nil, action: nil)
            control.selectedSegment = value == nil ? 0 : (value == true ? 1 : 2)
            return control
        }
        let preserveControl = triState(current.preserveSessionsOverride)
        let notifyControl = triState(current.notificationsOverride)
        func triStateValue(_ control: NSSegmentedControl) -> Bool? {
            switch control.selectedSegment {
            case 1: true
            case 2: false
            default: nil
            }
        }

        // Layout ---------------------------------------------------------
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = ZTheme.monoFont(size: 13, weight: .medium)
            field.textColor = ZTheme.current.fgColor
            return field
        }
        func row(_ title: String, _ control: NSView) -> NSStackView {
            let stack = NSStackView(views: [label(title), NSView(), control])
            stack.orientation = .horizontal
            return stack
        }
        let content = NSStackView(views: [
            row("Name", nameField),
            row("Color", colorRow),
            row("Icon", iconPopup),
            row("Preserve Sessions", preserveControl),
            row("Notifications", notifyControl),
        ])
        content.orientation = .vertical
        content.spacing = 12
        content.alignment = .leading
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        for case let stack as NSStackView in content.views {
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal

        let root = NSStackView(views: [content, buttons])
        root.orientation = .vertical
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        panel.contentView = root
        panel.setContentSize(root.fittingSize)

        // Actions ---------------------------------------------------------
        SheetTarget.shared.save = {
            var edited = ProjectSettings()
            let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            edited.name = trimmed.isEmpty ? nil : trimmed
            edited.color = selectedColorID
            edited.icon = iconPopup.indexOfSelectedItem > 0
                ? iconChoices[iconPopup.indexOfSelectedItem - 1] : nil
            edited.preserveSessionsOverride = triStateValue(preserveControl)
            edited.notificationsOverride = triStateValue(notifyControl)
            window.endSheet(panel)
            onSave(edited)
        }
        SheetTarget.shared.cancel = { window.endSheet(panel) }
        saveButton.target = SheetTarget.shared
        saveButton.action = #selector(SheetTarget.saveClicked)
        cancelButton.target = SheetTarget.shared
        cancelButton.action = #selector(SheetTarget.cancelClicked)

        window.beginSheet(panel)
    }
}

/// Objective-C action trampolines (NSButton needs an @objc target; the sheet
/// is a value-less enum, so a tiny shared object carries the closures).
private final class SheetTarget: NSObject {
    static let shared = SheetTarget()
    var save: (() -> Void)?
    var cancel: (() -> Void)?
    @objc func saveClicked() { save?() }
    @objc func cancelClicked() { cancel?() }
}

private final class SwatchTarget: NSObject {
    static let shared = SwatchTarget()
    var handlers: [ObjectIdentifier: () -> Void] = [:]
    @objc func clicked(_ sender: NSButton) { handlers[ObjectIdentifier(sender)]?() }
}
```

- [ ] **Step 3: Present + save in AppDelegate**

Near `promptRenameProject`:

```swift
    private func presentProjectSettings(_ project: ProjectRuntime) {
        guard let window = terminalViewController?.view.window else { return }
        ProjectSettingsSheet.present(
            for: project.name,
            current: projectSettings.settings(for: project.rootPath) ?? ProjectSettings(),
            fallbackName: (project.rootPath as NSString).lastPathComponent,
            on: window
        ) { [weak self] edited in
            self?.updateProjectSettings(edited, for: project)
        }
    }
```

Wire in `applicationDidFinishLaunching`:

```swift
        tvc.onOpenProjectSettings = { [weak self] project in self?.presentProjectSettings(project) }
```

- [ ] **Step 4: Regenerate (new file), build, tests**

```bash
mise exec -- tuist clean
mise exec -- tuist generate --no-open
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
swift test
```
Expected: `** BUILD SUCCEEDED **`, all PASS.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/ProjectSettingsSheet.swift App/Sources/App/SidebarView.swift App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat: per-project settings sheet (identity + overrides)"
```

---

### Task 9: Docs, install, end-to-end verification

**Files:**
- Modify: `README.md` (features list; a new "Per-project settings" subsection near Session persistence)
- Modify: `AGENTS.md` (new subsection in the app-layer/features area, near the preserve-sessions section)
- Modify: `CLAUDE.md` (Configuration section pointer)
- Modify: `docs/plans/2026-07-04-per-project-settings-design.md` (status → v1 shipped, v2/v3 pending)

**Interfaces:** prose only. Key facts: sidebar context menu → Rename… / Project Settings…; private store `~/Library/Application Support/zetty/project-settings.json` keyed by canonical rootPath; tri-state overrides (Follow global / On / Off) for preserve-sessions and notifications; curated 8-color palette + SF Symbol icons; bell/inbox and status dots never gated; settings survive remove-and-re-add at the same path; per-project preserve changes affect NEW panes only.

- [ ] **Step 1: README** — add to the features list after the Session persistence bullet:

```markdown
- **Per-project settings** — right-click a project → **Rename…** or **Project
  Settings…**: custom name, identity color, and icon for the sidebar, plus
  per-project overrides (Follow global / On / Off) of session preservation
  and agent notifications. Stored privately per user; nothing is written
  into the repo.
```

- [ ] **Step 2: AGENTS.md** — add a compact subsection after the session-persistence block:

```markdown
### Per-project settings

Right-click a project row → **Rename…** / **Project Settings…** (name, curated
color, SF Symbol icon, preserve-sessions + notifications tri-states). Pure
model in `ZettyCore/Settings/` (`ProjectSettings` · `ProjectSettingsFile` ·
`ProjectSettingsStore` · `ProjectSettingsResolver`); private JSON at
`~/Library/Application Support/zetty/project-settings.json` keyed by
**canonical rootPath** (survives remove/re-add; a moved directory orphans its
settings — accepted for v1). Precedence: project override → global config →
default. App wiring: `AppDelegate.resolvedSettings(for:)` +
`updateProjectSettings(_:for:)`; per-pane preserve decision inside
`applySessionPreservation`'s provider via `WorkspaceModel.project(containing:)`
(affects NEW panes only); notification gating at the fire site
(sound/banners) and in `publishAttentionCount` (dock badge) — the in-app
bell/inbox and status dots are never gated. Palette ids in
`ZTheme.projectPalette` (8 curated hues, distinct from accent + semantic
status colors). Theme override, `.zetty/project.json`, and env vars are
v2/v3 — see the design doc.
```

- [ ] **Step 3: CLAUDE.md** — in the Configuration section, after the `preserve-sessions` bullet:

```markdown
- **Per-project settings** — sidebar right-click → Rename…/Project Settings…
  (name/color/icon + preserve-sessions & notifications tri-state overrides);
  private store in Application Support, pure core in `ZettyCore/Settings/`.
  Details in [`AGENTS.md`](AGENTS.md).
```

- [ ] **Step 4: Design doc status** — update the header line of `docs/plans/2026-07-04-per-project-settings-design.md`:

```markdown
**Date:** 2026-07-04 · **Status:** v1 shipped (identity + preserve/notification overrides); v2 (theme + layout) and v3 (env) pending ·
```

- [ ] **Step 5: Full suite + install**

```bash
swift test
mise exec -- tuist generate --no-open
xcodebuild -project zetty.xcodeproj -scheme zetty -configuration Release -destination 'platform=macOS' build
ditto ~/Library/Developer/Xcode/DerivedData/zetty-*/Build/Products/Release/zetty.app /Applications/Zetty.app
defaults read /Applications/Zetty.app/Contents/Info.plist ZettyBuildCommit   # must match git rev-parse --short HEAD
```

- [ ] **Step 6: End-to-end verification (live app — coordinate the relaunch with Glen; sessions are preserved so it's non-destructive)**

Programmatic (via `zetty` CLI + files):
1. Relaunch Zetty (quit + open — same technique as the scrollback-restore e2e).
2. Rename a scratch project via the sheet or Rename… → `zetty status --json` shows the new name; `~/Library/Application Support/zetty/project-settings.json` contains the entry keyed by the canonical rootPath.
3. Set a scratch project's Preserve Sessions to **Off** (global on) → open a new pane there → `ps` shows a plain shell (no `zmx attach zetty-*` for that pane); other projects still spawn `zmx attach`.
4. Set it to **Follow Global** again → new panes attach again.
5. Remove and re-add the project at the same path → name/color/icon return.

Visual (Glen): identity color + icon on the row; status colors still win while an agent runs; notifications Off on a project with a running agent → no sound/banner/badge from it, but the yellow dot and bell still show.

- [ ] **Step 7: Commit docs (after Glen's OK)**

```bash
git add README.md AGENTS.md CLAUDE.md docs/plans/2026-07-04-per-project-settings-design.md
git commit -m "docs: document per-project settings v1"
```
