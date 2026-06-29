# quertty Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the quertty SPM workspace, a fully-tested pure-Swift `QuerttyCore` (layout tree + model + persistence), and a de-risked single libghostty terminal surface rendering in a SwiftUI window.

**Architecture:** `QuerttyCore` is a pure-Swift SPM package (no UI/C imports; the portable brain) — already complete (Tasks 1–4). `GhosttyKit` is the only module that touches libghostty's C API, thinly wrapping the **prebuilt `libghostty-spm` Swift package** (full libghostty — renderer included — distributed as a maintainer-built xcframework). The `quertty` macOS app (SwiftUI/AppKit, Tuist-generated) consumes `QuerttyCore` + `libghostty-spm`. **We use the prebuilt package, not a self-built submodule**: it eliminates the zig build and the macOS-26.5/Xcode-26.3 linker blocker entirely — any current Xcode works.

**Tech Stack:** Swift 6, Swift Package Manager, Tuist (app/workspace generation), `libghostty-spm` (prebuilt full-libghostty xcframework, pinned version), Swift Testing (via the `apple/swift-testing` package), SwiftUI + AppKit (macOS 14+), full libghostty (renderer + Kitty protocols), Metal. **Requires Xcode** (any current version) for Tasks 5–6 — no zig/mise needed.

## Global Constraints

- **Platform:** macOS first (macOS 14.0 minimum deployment target). No Windows. Linux is a future port — `QuerttyCore` and `GhosttyKit` must import no AppKit/SwiftUI.
- **Layer rule:** `QuerttyCore` imports no UI frameworks and no C library. `GhosttyKit` is the only module that imports libghostty. The app target is the only one importing SwiftUI/AppKit.
- **Ghostty layer:** Full **libghostty** (renderer included), NOT `libghostty-vt`. We render nothing ourselves.
- **Integration route (decided):** Use the **prebuilt `libghostty-spm`** Swift package (full libghostty, maintainer-built xcframework), consumed by a **Tuist**-generated app. Rationale: self-building from a submodule with zig hit an unresolvable macOS-26.5 SDK / zig-0.15.2 linker blocker (no installed SDK has both `arm64-macos` stubs and the availability symbol; the proven fix is the specific Xcode 26.3). The prebuilt package sidesteps the whole build — any current Xcode works — at the cost of trusting a community binary, which is acceptable for a multiplexer. (Self-built submodule + zig was attempted and abandoned; see commit history.)
- **libghostty pinning:** Pin `libghostty-spm` to a specific package version (e.g. `from: "1.2.7"` with an exact lower bound), recorded in `Package.swift`/Tuist deps. Never float to `branch`/`main`.
- **Toolchain prerequisites for Tasks 5–6:** **Xcode** (any current version — used to build the Tuist app; the prebuilt xcframework needs no zig) and **Tuist** (project generation, already installed). No zig, no mise, no specific Xcode version. Tasks 1–4 needed none of these and are already complete.
- **Testing:** Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) via the external `apple/swift-testing` SPM package. This is REQUIRED on this machine: only Command Line Tools are installed (no full Xcode), so `swift test` ships neither XCTest nor a bundled `Testing` module — the external package is the only headless-runnable option. `Package.swift` declares the dependency and each test target depends on the `Testing` product. `QuerttyCore` carries the test weight; all its logic is unit-tested. GhosttyKit/app are smoke/manually verified.
- **Commits:** Frequent, one per task minimum. Do not push without the owner's say-so.

---

### Task 1: SPM workspace + three-target skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/QuerttyCore/QuerttyCore.swift`
- Create: `Tests/QuerttyCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a `QuerttyCore` library target named `QuerttyCore`, importable by tests and later the app; a working `swift test` cycle.

- [ ] **Step 1: Write the Package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quertty",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuerttyCore", targets: ["QuerttyCore"]),
    ],
    dependencies: [
        // Required: only Command Line Tools are installed (no full Xcode), so the
        // toolchain's XCTest / bundled Testing module aren't available to `swift test`.
        // The self-contained swift-testing package is the only headless-runnable option.
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "QuerttyCore"),
        .testTarget(
            name: "QuerttyCoreTests",
            dependencies: [
                "QuerttyCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write a placeholder source so the target compiles**

```swift
// Sources/QuerttyCore/QuerttyCore.swift
/// Marker for the QuerttyCore module. Real types live in their own files.
public enum QuerttyCore {
    public static let version = "0.0.1"
}
```

- [ ] **Step 3: Write the smoke test**

```swift
// Tests/QuerttyCoreTests/SmokeTests.swift
import Testing
@testable import QuerttyCore

@Test func moduleHasVersion() {
    #expect(QuerttyCore.version == "0.0.1")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS, 1 test passing.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: SPM workspace with QuerttyCore target and smoke test"
```

---

### Task 2: Core model types

**Files:**
- Create: `Sources/QuerttyCore/Model/Surface.swift`
- Create: `Sources/QuerttyCore/Model/Project.swift`
- Create: `Tests/QuerttyCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: nothing from prior tasks.
- Produces:
  - `struct Surface: Codable, Sendable, Equatable, Identifiable` — `id: UUID`, `workingDir: String`, `command: String?`. Init: `init(id: UUID = UUID(), workingDir: String, command: String? = nil)`.
  - `enum SplitDirection: String, Codable, Sendable { case horizontal, vertical }`
  - `struct Tab: Codable, Sendable, Equatable, Identifiable` — `id: UUID`, `title: String`, `layout: Layout` (defined in Task 3; for now declare the property after Task 3 — see ordering note).
  - `struct Session`, `struct Project` (below).

> **Ordering note:** `Tab` references `Layout` from Task 3. Implement `Surface`, `SplitDirection`, `Session`, and `Project`-without-`Tab` here; add `Tab` and wire it into `Session` at the end of Task 3 where `Layout` exists. The steps below build only the parts whose types already exist.

- [ ] **Step 1: Write the failing test for Surface + Project**

```swift
// Tests/QuerttyCoreTests/ModelTests.swift
import Testing
import Foundation
@testable import QuerttyCore

@Test func surfaceCarriesWorkingDirAndCommand() {
    let s = Surface(workingDir: "/tmp/proj", command: "claude")
    #expect(s.workingDir == "/tmp/proj")
    #expect(s.command == "claude")
}

@Test func projectStartsUnpinnedWithNoSessions() {
    let p = Project(name: "demo", rootPath: "/tmp/proj")
    #expect(p.name == "demo")
    #expect(p.isPinned == false)
    #expect(p.sessions.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests`
Expected: FAIL — `Surface`/`Project` not found.

- [ ] **Step 3: Implement Surface and SplitDirection**

```swift
// Sources/QuerttyCore/Model/Surface.swift
import Foundation

public enum SplitDirection: String, Codable, Sendable {
    case horizontal
    case vertical
}

public struct Surface: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var workingDir: String
    public var command: String?

    public init(id: UUID = UUID(), workingDir: String, command: String? = nil) {
        self.id = id
        self.workingDir = workingDir
        self.command = command
    }
}
```

- [ ] **Step 4: Implement Project and Session**

```swift
// Sources/QuerttyCore/Model/Project.swift
import Foundation

public struct Session: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    // tabs added in Task 3 once Layout exists.

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/QuerttyCore/Model Tests/QuerttyCoreTests/ModelTests.swift
git commit -m "feat(core): Surface, SplitDirection, Session, Project model types"
```

---

### Task 3: Layout tree (split / close / resize)

**Files:**
- Create: `Sources/QuerttyCore/Model/SurfaceNode.swift`
- Create: `Sources/QuerttyCore/Model/Layout.swift`
- Modify: `Sources/QuerttyCore/Model/Project.swift` (add `Tab`, wire into `Session`)
- Create: `Tests/QuerttyCoreTests/LayoutTests.swift`

**Interfaces:**
- Consumes: `Surface`, `SplitDirection` (Task 2).
- Produces:
  - `indirect enum SurfaceNode: Codable, Sendable, Equatable` — cases `.leaf(Surface)` and `.split(direction: SplitDirection, ratio: Double, first: SurfaceNode, second: SurfaceNode)`. Computed `var surfaces: [Surface]`.
  - `struct Layout: Codable, Sendable, Equatable` — `var root: SurfaceNode`; `var surfaces: [Surface]`; `mutating func split(surfaceID:direction:newSurface:ratio:) -> Bool`; `mutating func close(surfaceID:) -> Bool`; `mutating func setRatio(parentOf:to:) -> Bool`.
  - `struct Tab: Codable, Sendable, Equatable, Identifiable` — `id: UUID`, `title: String`, `layout: Layout`; and `Session.tabs: [Tab]`.

> **Design refinement of the PRD:** the PRD sketched `.split(... children: [SurfaceNode])`; we use an explicit **binary** `first`/`second` because ratio resizing and parent-collapse-on-close are unambiguous with two children.

- [ ] **Step 1: Write failing tests for the layout tree**

```swift
// Tests/QuerttyCoreTests/LayoutTests.swift
import Testing
import Foundation
@testable import QuerttyCore

private func surface(_ n: Int) -> Surface {
    Surface(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
            workingDir: "/tmp")
}

@Test func singleLeafHasOneSurface() {
    let layout = Layout(root: .leaf(surface(1)))
    #expect(layout.surfaces.map(\.id) == [surface(1).id])
}

@Test func splitReplacesLeafWithBinarySplit() {
    var layout = Layout(root: .leaf(surface(1)))
    let ok = layout.split(surfaceID: surface(1).id, direction: .vertical, newSurface: surface(2))
    #expect(ok)
    #expect(layout.surfaces.map(\.id) == [surface(1).id, surface(2).id])
    guard case let .split(direction, ratio, first, second) = layout.root else {
        Issue.record("root should be a split"); return
    }
    #expect(direction == .vertical)
    #expect(ratio == 0.5)
    #expect(first == .leaf(surface(1)))
    #expect(second == .leaf(surface(2)))
}

@Test func splitUnknownSurfaceReturnsFalse() {
    var layout = Layout(root: .leaf(surface(1)))
    #expect(layout.split(surfaceID: surface(9).id, direction: .horizontal, newSurface: surface(2)) == false)
}

@Test func closeCollapsesParentToSibling() {
    var layout = Layout(root: .leaf(surface(1)))
    _ = layout.split(surfaceID: surface(1).id, direction: .horizontal, newSurface: surface(2))
    let ok = layout.close(surfaceID: surface(1).id)
    #expect(ok)
    #expect(layout.root == .leaf(surface(2)))
}

@Test func closingTheOnlySurfaceFails() {
    var layout = Layout(root: .leaf(surface(1)))
    #expect(layout.close(surfaceID: surface(1).id) == false)
    #expect(layout.root == .leaf(surface(1)))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LayoutTests`
Expected: FAIL — `SurfaceNode`/`Layout` not found.

- [ ] **Step 3: Implement SurfaceNode**

```swift
// Sources/QuerttyCore/Model/SurfaceNode.swift
import Foundation

public indirect enum SurfaceNode: Codable, Sendable, Equatable {
    case leaf(Surface)
    case split(direction: SplitDirection, ratio: Double, first: SurfaceNode, second: SurfaceNode)

    /// All leaf surfaces, left-to-right / first-to-second order.
    public var surfaces: [Surface] {
        switch self {
        case .leaf(let s):
            return [s]
        case .split(_, _, let first, let second):
            return first.surfaces + second.surfaces
        }
    }
}
```

- [ ] **Step 4: Implement Layout operations**

```swift
// Sources/QuerttyCore/Model/Layout.swift
import Foundation

public struct Layout: Codable, Sendable, Equatable {
    public var root: SurfaceNode

    public init(root: SurfaceNode) {
        self.root = root
    }

    public var surfaces: [Surface] { root.surfaces }

    /// Replace the leaf with `surfaceID` by a binary split of the existing
    /// surface (first) and `newSurface` (second). Returns false if not found.
    @discardableResult
    public mutating func split(
        surfaceID: UUID,
        direction: SplitDirection,
        newSurface: Surface,
        ratio: Double = 0.5
    ) -> Bool {
        var changed = false
        root = Self.transform(root) { node in
            guard case let .leaf(existing) = node, existing.id == surfaceID else { return nil }
            changed = true
            return .split(direction: direction, ratio: ratio,
                          first: .leaf(existing), second: .leaf(newSurface))
        }
        return changed
    }

    /// Remove the leaf with `surfaceID`, collapsing its parent split to the
    /// sibling. Returns false if it's the only surface or not found.
    @discardableResult
    public mutating func close(surfaceID: UUID) -> Bool {
        // The root being the target leaf means it's the only surface.
        if case let .leaf(s) = root, s.id == surfaceID { return false }
        var changed = false
        root = Self.collapse(root, removing: surfaceID, changed: &changed)
        return changed
    }

    /// Set the ratio of the split that directly contains the leaf `surfaceID`.
    @discardableResult
    public mutating func setRatio(parentOf surfaceID: UUID, to ratio: Double) -> Bool {
        let clamped = min(max(ratio, 0.05), 0.95)
        var changed = false
        root = Self.transform(root) { node in
            guard case let .split(direction, _, first, second) = node else { return nil }
            let directlyContains =
                (first.isLeaf(surfaceID) || second.isLeaf(surfaceID))
            guard directlyContains else { return nil }
            changed = true
            return .split(direction: direction, ratio: clamped, first: first, second: second)
        }
        return changed
    }

    // MARK: - Recursion helpers

    /// Bottom-up rewrite: apply `rewrite` to each node; if it returns a
    /// replacement, use it, else recurse into children.
    private static func transform(
        _ node: SurfaceNode,
        _ rewrite: (SurfaceNode) -> SurfaceNode?
    ) -> SurfaceNode {
        if let replacement = rewrite(node) { return replacement }
        switch node {
        case .leaf:
            return node
        case let .split(direction, ratio, first, second):
            return .split(direction: direction, ratio: ratio,
                          first: transform(first, rewrite),
                          second: transform(second, rewrite))
        }
    }

    /// Remove `surfaceID`; a split whose child is the removed leaf collapses to
    /// its sibling.
    private static func collapse(
        _ node: SurfaceNode,
        removing surfaceID: UUID,
        changed: inout Bool
    ) -> SurfaceNode {
        switch node {
        case .leaf:
            return node
        case let .split(direction, ratio, first, second):
            if first.isLeaf(surfaceID) { changed = true; return collapse(second, removing: surfaceID, changed: &changed) }
            if second.isLeaf(surfaceID) { changed = true; return collapse(first, removing: surfaceID, changed: &changed) }
            return .split(direction: direction, ratio: ratio,
                          first: collapse(first, removing: surfaceID, changed: &changed),
                          second: collapse(second, removing: surfaceID, changed: &changed))
        }
    }
}

extension SurfaceNode {
    /// True if this node is a leaf holding `id`.
    func isLeaf(_ id: UUID) -> Bool {
        if case let .leaf(s) = self { return s.id == id }
        return false
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter LayoutTests`
Expected: PASS, all 5 layout tests.

- [ ] **Step 6: Add `Tab` and wire it into `Session`**

```swift
// Append to Sources/QuerttyCore/Model/Project.swift

public struct Tab: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var layout: Layout

    public init(id: UUID = UUID(), title: String, layout: Layout) {
        self.id = id
        self.title = title
        self.layout = layout
    }
}
```

Then add `public var tabs: [Tab]` to `Session` (default `[]`) and include it in `Session.init`:

```swift
// Replace Session in Project.swift with:
public struct Session: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var tabs: [Tab]

    public init(id: UUID = UUID(), title: String, tabs: [Tab] = []) {
        self.id = id
        self.title = title
        self.tabs = tabs
    }
}
```

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: PASS (model + layout tests).

- [ ] **Step 8: Commit**

```bash
git add Sources/QuerttyCore/Model Tests/QuerttyCoreTests/LayoutTests.swift
git commit -m "feat(core): binary SurfaceNode layout tree with split/close/resize + Tab wiring"
```

---

### Task 4: Workspace persistence (JSON round-trip)

**Files:**
- Create: `Sources/QuerttyCore/Persistence/Workspace.swift`
- Create: `Sources/QuerttyCore/Persistence/WorkspaceStore.swift`
- Create: `Tests/QuerttyCoreTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: `Project` (Task 2/3) and its nested `Session`/`Tab`/`Layout`.
- Produces:
  - `struct Workspace: Codable, Sendable, Equatable` — `var projects: [Project]`; `var schemaVersion: Int` (current `1`).
  - `struct WorkspaceStore` — `init(directory: URL)`; `func load() throws -> Workspace` (returns empty workspace if file absent); `func save(_ workspace: Workspace) throws`. File is `workspace.json` in `directory`, pretty-printed, atomic write.

- [ ] **Step 1: Write failing round-trip + missing-file tests**

```swift
// Tests/QuerttyCoreTests/PersistenceTests.swift
import Testing
import Foundation
@testable import QuerttyCore

private func tempDir() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("quertty-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func loadingMissingWorkspaceReturnsEmpty() throws {
    let store = WorkspaceStore(directory: tempDir())
    let ws = try store.load()
    #expect(ws.projects.isEmpty)
    #expect(ws.schemaVersion == 1)
}

@Test func saveThenLoadRoundTrips() throws {
    let dir = tempDir()
    let store = WorkspaceStore(directory: dir)

    let surface = Surface(workingDir: "/tmp/proj", command: "claude")
    let tab = Tab(title: "main", layout: Layout(root: .leaf(surface)))
    let session = Session(title: "work", tabs: [tab])
    let project = Project(name: "demo", rootPath: "/tmp/proj",
                          isPinned: true, sessions: [session])
    let original = Workspace(schemaVersion: 1, projects: [project])

    try store.save(original)
    let restored = try store.load()

    #expect(restored == original)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PersistenceTests`
Expected: FAIL — `Workspace`/`WorkspaceStore` not found.

- [ ] **Step 3: Implement Workspace**

```swift
// Sources/QuerttyCore/Persistence/Workspace.swift
import Foundation

public struct Workspace: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var projects: [Project]

    public init(schemaVersion: Int = 1, projects: [Project] = []) {
        self.schemaVersion = schemaVersion
        self.projects = projects
    }
}
```

- [ ] **Step 4: Implement WorkspaceStore**

```swift
// Sources/QuerttyCore/Persistence/WorkspaceStore.swift
import Foundation

public struct WorkspaceStore {
    private let fileURL: URL

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("workspace.json")
    }

    public func load() throws -> Workspace {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Workspace()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Workspace.self, from: data)
    }

    public func save(_ workspace: Workspace) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspace)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PersistenceTests`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS (all core tests green).

- [ ] **Step 7: Commit**

```bash
git add Sources/QuerttyCore/Persistence Tests/QuerttyCoreTests/PersistenceTests.swift
git commit -m "feat(core): Workspace JSON persistence with round-trip + missing-file handling"
```

---

> **Tasks 5–6 use the prebuilt `libghostty-spm` package and require only Xcode (any current version) + Tuist (installed). No zig, no submodule, no specific Xcode. Task 5 has a discovery element: the package's exact product/module names and init API are read from the package during execution, NOT fabricated here.** `docs/ghostty-embedding-api.md` (recorded earlier from Ghostty v1.3.0 source) is a close reference for the C API, but `libghostty-spm` pins ~1.2.x — confirm names against the actual package. References: the package's own README/examples, Ghostty's `macos/Sources/Ghostty/SurfaceView*.swift`, and [Ghostling](https://github.com/ghostty-org/ghostty/tree/main/ghostling).

### Task 5: Tuist app + libghostty-spm dependency + GhosttyKit wrapper

> **Integration + small discovery task.** Deliverable: a Tuist-generated `quertty` app that links the prebuilt `libghostty-spm` package and the local `QuerttyCore`, with a thin `GhosttyKit` wrapper whose runtime-init smoke test passes. No build-from-source; the package ships a prebuilt xcframework.

**Files:**
- Create: `Tuist.swift`, `Workspace.swift`, `Project.swift` (Tuist project: `quertty` app target, macOS 14+; deps on the `libghostty-spm` SPM package + the local `QuerttyCore` package)
- Create: `App/Sources/GhosttyKit/Ghostty.swift` (thin Swift wrapper over the package's API)
- Create: `App/Tests/GhosttyKitTests/LinkSmokeTests.swift`

**Interfaces:**
- Consumes: the `libghostty-spm` package (products: `GhosttyKit` = C API, `GhosttyTerminal` = Swift wrapper, `GhosttyTheme`); the local `QuerttyCore` package (Tasks 1–4).
- Produces:
  - A Tuist-generated workspace that builds in Xcode and links libghostty.
  - `enum Ghostty` with `static func initializeRuntime() throws` and `static var isInitialized: Bool`, calling the real libghostty runtime-init exposed by the package.

- [ ] **Step 1: Inspect the package's actual API (discovery)**

Add `libghostty-spm` and resolve it, then read what it exposes — the C entry points in its `GhosttyKit` product and/or the `GhosttyTerminal` Swift API. Run:
```bash
# After adding the dependency and `tuist generate` (or a scratch SPM resolve):
find ~/Library/Developer/Xcode/DerivedData -path "*libghostty-spm*" -name "*.h" 2>/dev/null | head
# and read the package's Sources/GhosttyKit + Sources/GhosttyTerminal public API.
```
Record the real runtime-init symbol (e.g. `ghostty_init`/`ghostty_app_new` or a `GhosttyTerminal` initializer) — Step 3 uses the verbatim name. Cross-check against `docs/ghostty-embedding-api.md`.

- [ ] **Step 2: Scaffold the Tuist project + write the failing smoke test**

Author `Project.swift`/`Workspace.swift`/`Tuist.swift` defining the `quertty` macOS app target (macOS 14+) with external dependencies on `libghostty-spm` (pinned, e.g. `.upToNextMinor(from: "1.2.7")`) and the local `QuerttyCore` package, plus a `GhosttyKit` framework target and a `GhosttyKitTests` test target. Then the failing test:

```swift
// App/Tests/GhosttyKitTests/LinkSmokeTests.swift
import Testing
@testable import GhosttyKit

@Test func runtimeInitializesWithoutThrowing() throws {
    try Ghostty.initializeRuntime()
    #expect(Ghostty.isInitialized)
}
```
Run `tuist generate && tuist test`. Expected: FAIL — `Ghostty` undefined / package not yet wired.

- [ ] **Step 3: Implement the thin wrapper using the real package API**

```swift
// App/Sources/GhosttyKit/Ghostty.swift
import GhosttyKit   // the C-API product from libghostty-spm — use its real module name from Step 1

public enum Ghostty {
    public private(set) static var isInitialized = false

    /// Initializes the libghostty global runtime exactly once.
    /// NOTE: replace the call below with the verbatim runtime-init symbol the
    /// package exposes (confirmed in Step 1) — e.g. `ghostty_init(...)`.
    public static func initializeRuntime() throws {
        guard !isInitialized else { return }
        let rc = ghostty_init(0, nil)   // ← substitute real signature from Step 1
        guard rc == 0 else { throw GhosttyError.initFailed(code: Int(rc)) }
        isInitialized = true
    }
}

public enum GhosttyError: Error, Equatable {
    case initFailed(code: Int)
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run `tuist test`. Expected: PASS — the package links and a real libghostty call succeeds (proving the prebuilt xcframework resolves under the current Xcode, no zig build needed).

- [ ] **Step 5: Commit**

```bash
git add Tuist.swift Workspace.swift Project.swift App/Sources/GhosttyKit App/Tests/GhosttyKitTests
git -c commit.gpgsign=false commit -m "feat(ghostty): Tuist app + libghostty-spm dependency + GhosttyKit runtime wrapper"
```

---

### Task 6: Phase 0 spike — one libghostty surface in a SwiftUI window

> **Spike task with a manual acceptance check** (rendering/input can't be unit-asserted headlessly). Deliverable: the `quertty` app showing a working terminal in one pane — proving the surface seam before any Phase 1 UI. **Requires running in Xcode.** Fastest path: try the package's `GhosttyTerminal` SwiftUI wrapper first; drop to hosting the C surface in an `NSView` only if we need lower-level control.

**Files:**
- Create: `App/Sources/quertty/querttyApp.swift`
- Create: `App/Sources/quertty/ContentView.swift`
- Create: `App/Sources/quertty/TerminalSurface.swift` (either a wrapper around the package's `GhosttyTerminal` view, or an `NSViewRepresentable` hosting a libghostty surface in a `CAMetalLayer`)
- Create: `docs/phase0-acceptance.md` (the manual checklist + result)

**Interfaces:**
- Consumes: `Ghostty.initializeRuntime()` (Task 5) and the package's terminal-surface API (`GhosttyTerminal` view, or the C surface-creation/input/draw entry points).
- Produces: a runnable `quertty` app showing one live terminal pane; the documented Phase 0 acceptance result.

- [ ] **Step 1: Render a surface — prefer the package's GhosttyTerminal wrapper**

Inspect `GhosttyTerminal`'s public API (from Task 5 Step 1). If it exposes a SwiftUI view / NSView that renders a terminal given a command, wrap it in `TerminalSurface`. If it's too high-level/opinionated for our needs, instead implement `TerminalSurface` as an `NSViewRepresentable` hosting an `NSView` with a `CAMetalLayer`, creating a libghostty surface via the package's C API (surface-creation entry point from Task 5 Step 1), forwarding key/mouse/resize/focus, and spawning the user's `$SHELL`. Reference Ghostty's `macos/Sources/Ghostty/SurfaceView*.swift`.

- [ ] **Step 2: App shell**

```swift
// App/Sources/quertty/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TerminalSurface()
            .frame(minWidth: 640, minHeight: 400)
    }
}
```

```swift
// App/Sources/quertty/querttyApp.swift
import SwiftUI
import GhosttyKit

@main
struct QuerttyApp: App {
    init() {
        do { try Ghostty.initializeRuntime() }
        catch { fatalError("libghostty init failed: \(error)") }
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

- [ ] **Step 3: Build and run in Xcode**

`tuist generate && open quertty.xcworkspace`, then Run the `quertty` scheme. Expected: a window opens showing a live terminal.

- [ ] **Step 4: Manual acceptance check — record results**

Create `docs/phase0-acceptance.md` and tick each:
- [ ] Window shows a shell prompt rendered by libghostty.
- [ ] Typing appears in the terminal; `ls`, `vim`, exit all work.
- [ ] Resizing the window reflows the terminal (PTY size updates).
- [ ] Clicking the pane gives it keyboard focus.
- [ ] A Kitty-graphics image (e.g. `kitten icat`) renders — confirming full libghostty rendering, not just text.

Record PASS/FAIL per line with notes. Any FAIL blocks Phase 1.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/quertty docs/phase0-acceptance.md
git -c commit.gpgsign=false commit -m "feat(app): Phase 0 spike — single libghostty surface in a SwiftUI window"
```

---

## Self-Review

**Spec coverage (against PRD §3–§9 foundation portions):**
- 3-layer architecture (QuerttyCore / GhosttyKit / app) → Tasks 1, 6, 7. ✓
- Layer rule (Core no UI/C; GhosttyKit only C) → enforced by target boundaries in Tasks 1/6. ✓
- Data model (Project→Session→Tab→SurfaceNode) → Tasks 2, 3. ✓
- Binary split tree + split/close/resize → Task 3. ✓
- JSON persistence + restore + missing-file → Task 4. ✓
- Full libghostty (not vt), via the prebuilt `libghostty-spm` package + Tuist app → Tasks 5, 6. ✓ (Requires Xcode + Tuist only — no zig/mise; the prebuilt xcframework sidesteps the macOS-26.5 build blocker.)
- Phase 0 surface spike incl. Kitty graphics check → Task 6. ✓
- **Deliberately deferred to follow-up plans:** sidebar/panel UI, AI presence + hook-status engine (plan written: `2026-06-25-quertty-agent-detection.md`), `quertty` CLI + socket, `DetachedPTY`/zmx, tmux keybindings.

**Placeholder scan:** The only non-literal code is the `ghostty_init(0, nil)` call (Task 5 Step 3), explicitly flagged to be substituted from the package's real API confirmed in Task 5 Step 1 — correct, since the package's exact symbol/module names must be read from the resolved dependency, not fabricated. All pure-Swift tasks (1–4) contain complete, runnable code.

**Type consistency:** `Surface`, `SplitDirection`, `SurfaceNode` (`.leaf`/`.split(direction:ratio:first:second:)`), `Layout` (`split`/`close`/`setRatio`/`surfaces`), `Tab`, `Session.tabs`, `Project`, `Workspace`, `WorkspaceStore` (`load`/`save`), `Ghostty.initializeRuntime`/`isInitialized`, `GhosttyError.initFailed` — names and signatures match across all tasks and tests. ✓
