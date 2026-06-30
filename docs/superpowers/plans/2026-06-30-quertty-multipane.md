# quertty Phase 1 — Multi-Pane Core (splits + tabs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-pane spike into a real multiplexer pane core: a window showing one tab's `SurfaceNode` layout as nested, resizable h/v splits — each leaf a live `GhosttyTerminal` surface — with split/close/click-to-focus, multiple tabs, and layout persistence.

**Architecture:** The focus-aware tree logic lives in `QuerttyCore` as a pure, fully-tested `PaneTree` value type (wrapping the existing `Layout`/`SurfaceNode`). The app layer renders a `PaneTree` recursively (leaf → terminal pane, split → resizable divider), backed by a `SurfaceRegistry` that maps each `Surface.id` to a persistent `TerminalController`/terminal view so re-renders never recreate a live terminal. Tabs each own a `PaneTree`; the whole set persists via the existing `WorkspaceStore`.

**Tech Stack:** Swift 6, SPM (`QuerttyCore`) + Tuist app, `libghostty-spm` (`GhosttyTerminal`), AppKit/SwiftUI, XCTest (app target), Swift Testing via `apple/swift-testing` (`QuerttyCore`).

## Global Constraints

- **Layer rule:** `QuerttyCore` imports only Swift + Foundation — no UI, no libghostty. `PaneTree` is pure logic. All `GhosttyTerminal`/AppKit code lives in the app target.
- **`QuerttyCore` tests:** Swift Testing (`import Testing`) via the `apple/swift-testing` package (already wired). **App-target tests:** XCTest (Swift Testing discovery doesn't work under the Tuist-generated project — proven in Phase 0).
- **Live-surface preservation:** splitting/closing/re-rendering MUST NOT destroy or recreate the `TerminalController` of an unchanged pane. Surfaces are keyed by `Surface.id` in a registry; only added/removed leaves create/tear-down controllers.
- **libghostty init:** `TerminalController` calls `ghostty_init` internally once; never call `Ghostty.initializeRuntime()` in the app path (double-init crashes — established Phase 0).
- **App entry point:** programmatic `main.swift` + `AppDelegate` (no `@main`/`NSApplicationMain` — Tuist's Info.plist `NSMainStoryboardFile` crashes it; established Phase 0).
- **Reuse, don't rebuild:** `Layout.split/close/setRatio/surfaces` and `WorkspaceStore` already exist and are tested — build on them.
- **Commits:** frequent, one per task min; `git -c commit.gpgsign=false commit`. Don't push without owner's say-so. Build the app headlessly with `mise exec -- tuist build quertty`; GUI behavior is user-verified.
- **GhosttyTerminal API is read from the package during implementation** (the concrete view type, how a controller binds to a view, divider/resize hooks) — confirm against the resolved package source; do not fabricate.

---

### Task 1: `PaneTree` — focus-aware split tree (QuerttyCore, TDD)

**Files:**
- Create: `Sources/QuerttyCore/Model/PaneTree.swift`
- Create: `Tests/QuerttyCoreTests/PaneTreeTests.swift`

**Interfaces:**
- Consumes: `Layout`, `SurfaceNode`, `Surface`, `SplitDirection` (Phase 0).
- Produces: `struct PaneTree: Codable, Sendable, Equatable` — `var layout: Layout`, `var focusedSurfaceID: UUID?`; `mutating func splitFocused(direction:newSurface:ratio:) -> Bool` (splits the focused leaf, focus moves to the new surface); `mutating func closeFocused() -> Bool` (closes focused leaf, focus moves to the first remaining surface, false if it was the only one); `mutating func focus(_ id: UUID)` (no-op if id absent); `var focusedSurface: Surface?`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/QuerttyCoreTests/PaneTreeTests.swift
import Testing
import Foundation
@testable import QuerttyCore

private func surface(_ n: Int) -> Surface {
    Surface(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!, workingDir: "/tmp")
}

@Test func newTreeFocusesItsOnlyLeaf() {
    let tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: surface(1).id)
    #expect(tree.focusedSurface?.id == surface(1).id)
}

@Test func splitFocusedMovesFocusToNewSurface() {
    var tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: surface(1).id)
    let ok = tree.splitFocused(direction: .vertical, newSurface: surface(2))
    #expect(ok)
    #expect(tree.layout.surfaces.map(\.id) == [surface(1).id, surface(2).id])
    #expect(tree.focusedSurfaceID == surface(2).id)
}

@Test func splitWithNoFocusReturnsFalse() {
    var tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: nil)
    #expect(tree.splitFocused(direction: .horizontal, newSurface: surface(2)) == false)
}

@Test func closeFocusedRefocusesARemainingSurface() {
    var tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: surface(1).id)
    _ = tree.splitFocused(direction: .horizontal, newSurface: surface(2)) // focus now surface(2)
    let ok = tree.closeFocused() // closes surface(2)
    #expect(ok)
    #expect(tree.layout.surfaces.map(\.id) == [surface(1).id])
    #expect(tree.focusedSurfaceID == surface(1).id)
}

@Test func closingOnlySurfaceFailsAndKeepsFocus() {
    var tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: surface(1).id)
    #expect(tree.closeFocused() == false)
    #expect(tree.focusedSurfaceID == surface(1).id)
}

@Test func focusIgnoresUnknownID() {
    var tree = PaneTree(layout: Layout(root: .leaf(surface(1))), focusedSurfaceID: surface(1).id)
    tree.focus(surface(9).id)
    #expect(tree.focusedSurfaceID == surface(1).id)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PaneTreeTests`
Expected: FAIL — `PaneTree` not found.

- [ ] **Step 3: Implement `PaneTree`**

```swift
// Sources/QuerttyCore/Model/PaneTree.swift
import Foundation

public struct PaneTree: Codable, Sendable, Equatable {
    public var layout: Layout
    public var focusedSurfaceID: UUID?

    public init(layout: Layout, focusedSurfaceID: UUID? = nil) {
        self.layout = layout
        self.focusedSurfaceID = focusedSurfaceID
    }

    public var focusedSurface: Surface? {
        guard let id = focusedSurfaceID else { return nil }
        return layout.surfaces.first { $0.id == id }
    }

    /// Split the focused leaf; focus moves to `newSurface`. False if no focus / not found.
    @discardableResult
    public mutating func splitFocused(direction: SplitDirection, newSurface: Surface, ratio: Double = 0.5) -> Bool {
        guard let id = focusedSurfaceID else { return false }
        guard layout.split(surfaceID: id, direction: direction, newSurface: newSurface, ratio: ratio) else { return false }
        focusedSurfaceID = newSurface.id
        return true
    }

    /// Close the focused leaf; focus moves to the first remaining surface. False if it was the only one.
    @discardableResult
    public mutating func closeFocused() -> Bool {
        guard let id = focusedSurfaceID else { return false }
        guard layout.close(surfaceID: id) else { return false }
        focusedSurfaceID = layout.surfaces.first?.id
        return true
    }

    /// Focus the surface with `id`; no-op if it isn't in the tree.
    public mutating func focus(_ id: UUID) {
        guard layout.surfaces.contains(where: { $0.id == id }) else { return }
        focusedSurfaceID = id
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PaneTreeTests` → PASS (6 tests). Then `swift test` → full core suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuerttyCore/Model/PaneTree.swift Tests/QuerttyCoreTests/PaneTreeTests.swift
git -c commit.gpgsign=false commit -m "feat(core): PaneTree — focus-aware split tree (splitFocused/closeFocused/focus)"
```

---

### Task 2: `SurfaceRegistry` — persistent terminal-controller store (app)

**Files:**
- Create: `App/Sources/App/SurfaceRegistry.swift`
- Create: `App/Tests/QuerttyGhosttyTests/SurfaceRegistryTests.swift` (logic-only test of add/remove/reuse bookkeeping — no real terminals)

**Interfaces:**
- Consumes: `Surface` (QuerttyCore); `GhosttyTerminal` (`TerminalController`, the terminal view type — confirm names from the package).
- Produces: `final class SurfaceRegistry` — `func controller(for surface: Surface) -> TerminalController` (creates on first request with the surface's `workingDir`/`command`, reuses thereafter); `func prune(keeping ids: Set<UUID>)` (tears down controllers whose surface id is not in `ids`); `var liveIDs: Set<UUID>`.

> **Discovery:** read `TerminalController`'s init + how it's told a working directory / command (Phase 0 used `TerminalSurfaceOptions(backend: .exec)`); use the real API. Keep the registry the single owner of controller lifecycles.

- [ ] **Step 1: Write the failing test (bookkeeping only)**

```swift
// App/Tests/QuerttyGhosttyTests/SurfaceRegistryTests.swift
import XCTest
import QuerttyCore
@testable import quertty   // app module name as generated by Tuist; adjust if different

final class SurfaceRegistryTests: XCTestCase {
    func testReusesControllerForSameSurfaceID() {
        let reg = SurfaceRegistry()
        let s = Surface(workingDir: "/tmp")
        let a = reg.controller(for: s)
        let b = reg.controller(for: s)
        XCTAssertTrue(a === b)                 // same instance reused
        XCTAssertEqual(reg.liveIDs, [s.id])
    }

    func testPruneTearsDownAbsentSurfaces() {
        let reg = SurfaceRegistry()
        let s1 = Surface(workingDir: "/tmp"); let s2 = Surface(workingDir: "/tmp")
        _ = reg.controller(for: s1); _ = reg.controller(for: s2)
        reg.prune(keeping: [s1.id])
        XCTAssertEqual(reg.liveIDs, [s1.id])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `mise exec -- tuist test QuerttyGhosttyTests` → FAIL (`SurfaceRegistry` undefined). (Note: the app test scheme is the explicit `QuerttyGhosttyTests` scheme from Phase 0; if this test target lives in a different scheme, add it there.)

- [ ] **Step 3: Implement `SurfaceRegistry`**

Implement with a `[UUID: TerminalController]` dict. `controller(for:)` returns the existing controller or creates one (configuring `.exec` backend + the surface's `workingDir`/`command` per the package API found in discovery). `prune(keeping:)` removes and releases entries whose key isn't kept (call any teardown the package exposes). `liveIDs` returns `Set(dict.keys)`.

> If `TerminalController` has no explicit teardown, dropping the reference is sufficient; note this in the report.

- [ ] **Step 4: Run to verify it passes**

Run: `mise exec -- tuist test QuerttyGhosttyTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/App/SurfaceRegistry.swift App/Tests/QuerttyGhosttyTests/SurfaceRegistryTests.swift
git -c commit.gpgsign=false commit -m "feat(app): SurfaceRegistry — persistent per-surface terminal controllers"
```

---

### Task 3: Recursive split rendering of a `SurfaceNode` (app, build + manual)

**Files:**
- Create: `App/Sources/App/SurfaceNodeView.swift` (recursive AppKit view: leaf → terminal pane hosting `SurfaceRegistry.controller(for:)`'s view; split → an `NSSplitView` with the two children and `ratio`)
- Modify: `App/Sources/App/TerminalViewController.swift` (host a root `SurfaceNodeView` driven by a `PaneTree` instead of a single `TerminalView`)

**Interfaces:**
- Consumes: `PaneTree`/`SurfaceNode` (QuerttyCore), `SurfaceRegistry` (Task 2), `GhosttyTerminal` view type.
- Produces: a view that renders any `SurfaceNode` as nested resizable splits, each leaf showing its registry-owned terminal.

- [ ] **Step 1: Build a recursive renderer**

Implement `SurfaceNodeView` that, given a `SurfaceNode` + `SurfaceRegistry`: for `.leaf(surface)`, embeds the terminal view from `registry.controller(for: surface)`; for `.split(direction, ratio, first, second)`, creates an `NSSplitView` (`isVertical = direction == .vertical`), adds recursively-built child views, and sets the divider position from `ratio` after layout. Rebuilding the tree must fetch leaves from the registry (so unchanged panes keep their live terminal).

- [ ] **Step 2: Drive it from a `PaneTree` in the view controller**

Replace `TerminalViewController`'s single `TerminalView` with a root container that (re)builds a `SurfaceNodeView` from `paneTree.layout.root`. Seed `paneTree` with one leaf (a fresh `Surface(workingDir: NSHomeDirectory())`) so the default window still shows one terminal. After any tree change, call `registry.prune(keeping: Set(paneTree.layout.surfaces.map(\.id)))`.

- [ ] **Step 3: Build**

Run: `mise exec -- tuist build quertty` → Build Succeeded.

- [ ] **Step 4: Manual check (record in `docs/phase1-acceptance.md`)**

Hard-code a two-leaf split in the seed (temporarily) to confirm two terminals render side-by-side and both are interactive; then revert to a single seed leaf. Note PASS/PENDING.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/App/SurfaceNodeView.swift App/Sources/App/TerminalViewController.swift docs/phase1-acceptance.md
git -c commit.gpgsign=false commit -m "feat(app): recursive SurfaceNode split rendering driven by PaneTree"
```

---

### Task 4: Split / close / click-to-focus actions (app, build + manual)

**Files:**
- Modify: `App/Sources/App/TerminalViewController.swift` (focus tracking + menu/keyboard actions)
- Create: `App/Sources/App/PaneActions.swift` (the action methods, thin wrappers over `PaneTree`)
- Modify: `App/Sources/App/AppDelegate.swift` (menu items / key equivalents)

**Interfaces:**
- Consumes: `PaneTree` (Task 1), the renderer (Task 3).
- Produces: working "split vertical" (⌘D), "split horizontal" (⇧⌘D), "close pane" (⌘W) acting on the focused pane; clicking a pane sets focus (visible focus ring/highlight on the focused leaf).

- [ ] **Step 1: Focus tracking**

When a terminal pane becomes first responder (click), call `paneTree.focus(surface.id)` and re-render the focus highlight. Map the focused leaf via the registry.

- [ ] **Step 2: Actions**

`splitVertical()`/`splitHorizontal()` create a `Surface(workingDir: <focused surface's workingDir or home>)`, call `paneTree.splitFocused(direction:newSurface:)`, rebuild + prune. `closePane()` calls `paneTree.closeFocused()` (ignore when it returns false — last pane), rebuild + prune. Wire to menu items with ⌘D / ⇧⌘D / ⌘W in `AppDelegate`.

- [ ] **Step 3: Build + manual check**

`mise exec -- tuist build quertty` → succeeds. Manually: split a pane both ways, type in each, close one, confirm the sibling fills the space and the surviving terminals keep their session (scrollback intact). Record in `docs/phase1-acceptance.md`.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/App/PaneActions.swift App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift docs/phase1-acceptance.md
git -c commit.gpgsign=false commit -m "feat(app): split/close/focus pane actions wired to PaneTree"
```

---

### Task 5: Tabs (app, build + manual)

**Files:**
- Create: `App/Sources/App/TabBarController.swift` (a tab bar + a `[Tab]` model where each `Tab` owns a `PaneTree`)
- Modify: `App/Sources/App/TerminalViewController.swift` (host the active tab's pane tree)

**Interfaces:**
- Consumes: `Tab`/`PaneTree` (QuerttyCore), the renderer + actions (Tasks 3–4).
- Produces: a tab strip; new-tab (⌘T) creates a `Tab` with a single fresh surface; switching tabs swaps the rendered `PaneTree`; close-tab. Each tab's surfaces persist in the registry while the tab exists.

> **Model note:** `Tab.layout` exists (Phase 0). Either store focus per tab by composing `PaneTree` into the tab-management model, or extend the app's tab model to hold `PaneTree` per tab. Keep `QuerttyCore`'s `Tab` as the persisted shape; the app may hold a parallel focus map.

- [ ] **Step 1: Tab model + bar**

Implement a tab list holding one `PaneTree` per tab, an active-tab index, and `newTab()`/`closeTab(_:)`/`select(_:)`. Render a simple tab bar (buttons/segmented control) above the pane area.

- [ ] **Step 2: Swap rendering on tab switch**

On active-tab change, rebuild the pane area from that tab's `PaneTree`. Prune the registry to the union of surfaces across *all* tabs (don't tear down background-tab terminals).

- [ ] **Step 3: Build + manual check**

`mise exec -- tuist build quertty` → succeeds. Manually: new tab, split within it, switch tabs (both retain their layouts + live sessions), close a tab. Record in `docs/phase1-acceptance.md`.

- [ ] **Step 4: Commit**

```bash
git add App/Sources/App/TabBarController.swift App/Sources/App/TerminalViewController.swift docs/phase1-acceptance.md
git -c commit.gpgsign=false commit -m "feat(app): tabs — one PaneTree per tab with new/close/switch"
```

---

### Task 6: Persist & restore layout via `WorkspaceStore` (app, build + manual + round-trip)

**Files:**
- Create: `App/Sources/App/SessionPersistence.swift` (maps the app's tabs/pane-trees ⇄ `QuerttyCore` model; loads on launch, saves on change/quit via `WorkspaceStore`)
- Modify: `App/Sources/App/AppDelegate.swift` (load on `applicationDidFinishLaunching`, save on `applicationWillTerminate`)
- Create: `App/Tests/QuerttyGhosttyTests/SessionPersistenceTests.swift`

**Interfaces:**
- Consumes: `Workspace`/`WorkspaceStore`/`Project`/`Session`/`Tab`/`Layout` (QuerttyCore, Phase 0).
- Produces: on launch, restored tabs/splits (terminals re-spawn at saved `workingDir`); on quit, the current tab/split arrangement is written to `workspace.json`.

- [ ] **Step 1: Failing round-trip test (app logic)**

```swift
// App/Tests/QuerttyGhosttyTests/SessionPersistenceTests.swift
import XCTest
import QuerttyCore
@testable import quertty

final class SessionPersistenceTests: XCTestCase {
    func testTabsSurviveSaveAndLoad() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WorkspaceStore(directory: dir)

        let snapshot = SessionPersistence.snapshot(  // builds a Workspace from app tab models
            tabs: [Tab(title: "one", layout: Layout(root: .leaf(Surface(workingDir: "/tmp"))))]
        )
        try store.save(snapshot)

        let restored = try store.load()
        let tabs = SessionPersistence.tabs(from: restored)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.layout.surfaces.first?.workingDir, "/tmp")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `mise exec -- tuist test QuerttyGhosttyTests` → FAIL (`SessionPersistence` undefined).

- [ ] **Step 3: Implement persistence mapping + wire lifecycle**

Implement `SessionPersistence.snapshot(tabs:) -> Workspace` and `.tabs(from: Workspace) -> [Tab]` (wrap tabs in a single default `Project`/`Session` for now — richer project modeling is a later slice). In `AppDelegate`, load on launch (fall back to one default tab if the workspace is empty) and save on terminate.

- [ ] **Step 4: Run test + build**

`mise exec -- tuist test QuerttyGhosttyTests` → PASS; `mise exec -- tuist build quertty` → succeeds.

- [ ] **Step 5: Manual check**

Open quertty, make a 2-tab + split arrangement, quit, relaunch → arrangement restored (terminals re-spawned at saved dirs; scrollback not restored — expected, no daemon). Record in `docs/phase1-acceptance.md`.

- [ ] **Step 6: Commit**

```bash
git add App/Sources/App/SessionPersistence.swift App/Sources/App/AppDelegate.swift App/Tests/QuerttyGhosttyTests/SessionPersistenceTests.swift docs/phase1-acceptance.md
git -c commit.gpgsign=false commit -m "feat(app): persist & restore tabs/splits via WorkspaceStore"
```

---

## Self-Review

**Spec coverage (PRD multiplexer core):**
- Tabs + h/v splits rendered from the model → Tasks 3, 4, 5. ✓
- Each pane a real libghostty terminal, sessions preserved across tree changes → Task 2 (registry) + constraint. ✓
- Split/close/focus → Tasks 1 (logic, tested) + 4 (UI). ✓
- Layout persistence/restore → Task 6 (reuses tested `WorkspaceStore`). ✓
- **Deferred to later slices:** the sidebar (pinnable projects → sessions navigation), AI agent detection (Plan A — `2026-06-25-quertty-agent-detection.md`), the `quertty` CLI/socket, `DetachedPTY`/zmx, tmux-style keybindings beyond ⌘D/⌘W. Also the open Phase-0 cleanup: `GhosttyKit` static-linked via both `GhosttyTerminal` and `QuerttyGhostty` — revisit if the app no longer needs the `QuerttyGhostty` C wrapper (Task path uses `GhosttyTerminal` directly).

**Placeholder scan:** Task 1 (core) has complete code. Tasks 2–6 are app/UI integration whose exact `GhosttyTerminal` API calls (controller init, view embedding, divider/resize, teardown) are explicitly flagged for discovery from the resolved package — correct, since that API must be read, not fabricated. Each UI task ends in a concrete build command + a manual acceptance line.

**Type consistency:** `PaneTree(layout:focusedSurfaceID:)` / `splitFocused(direction:newSurface:ratio:)` / `closeFocused()` / `focus(_:)` / `focusedSurface`; `SurfaceRegistry.controller(for:)` / `prune(keeping:)` / `liveIDs`; `SessionPersistence.snapshot(tabs:)` / `tabs(from:)` — consistent across tasks and tests, and built on Phase 0's `Layout`/`Surface`/`Tab`/`Workspace`/`WorkspaceStore`.
