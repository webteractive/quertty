# CLI No-Focus-Steal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `zetty` CLI verbs `new-tab`, `split`, `break`, and `scratch` operate in the background by default — never changing the active (visible) project or keyboard focus — with an opt-in `--focus` flag, matching the existing `add-project`/`new-project` pattern.

**Architecture:** The focus/selection side effects live entirely in the app layer (`TerminalViewController`). The fix pushes the structural mutation into new **pure** `ZettyCore` model helpers (`TabList`/`PaneTree`) that mutate a *specific* tree/pane without touching any "active" index, then has the app layer refresh chrome and — only for `--focus` — select + focus the result. The wire protocol gains a `focus: Bool` on the four requests (default `false`, backward-compatible via `decodeIfPresent`).

**Tech Stack:** Swift, AppKit, Swift Testing (`import Testing`), Tuist-generated Xcode project, SwiftPM for the pure `ZettyCore` suite.

## Global Constraints

- `ZettyCore` stays pure — **no AppKit import** in any `Sources/ZettyCore/**` file.
- Never hardcode a color; not relevant here (no UI tokens touched).
- Do not commit debug `NSLog`/`print`.
- **Document every user-facing change in `README.md`** as part of the same change.
- **Keep `CLAUDE.md` and `AGENTS.md` byte-identical** — any edit to one is mirrored to the other in the same commit.
- Never commit or push without being asked; no `Co-Authored-By`, no session link in commit messages.
- Wire protocol is backward-compatible: new fields decode with `decodeIfPresent(...) ?? false`.
- Pure `ZettyCore` tests: `mise exec -- swift test` (single: `--filter <name>`). App target: `mise exec -- tuist test`.
- After adding/removing a file, regenerate: `mise exec -- tuist generate --no-open`. If generate errors at a resources dir, run `mise exec -- tuist clean` first (only needed for `App/Resources/` changes — not expected here).

---

### Task 1: Wire protocol — add `focus` to newTab / split / break / scratch

**Files:**
- Modify: `Sources/ZettyCore/CLI/ControlProtocol.swift`
- Test: `Tests/ZettyCoreTests/ControlProtocolTests.swift`

**Interfaces:**
- Produces:
  - `ControlRequest.newTab(project: String?, focus: Bool)`
  - `ControlRequest.split(target: PaneSelector, vertical: Bool, focus: Bool)`
  - `ControlRequest.breakPane(target: PaneSelector, focus: Bool)`
  - `ControlRequest.scratch(focus: Bool)`

- [ ] **Step 1: Write the failing test**

Add these `#expect`s inside the existing `roundTripsAllRequests` test in `Tests/ZettyCoreTests/ControlProtocolTests.swift` (replace the current `.scratch`, `.newTab`, `.split`, `.breakPane` lines — lines ~17, 19-20, 39-44 — with the focus-carrying versions):

```swift
// scratch now carries focus
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.scratch(focus: false))) == .scratch(focus: false))
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.scratch(focus: true))) == .scratch(focus: true))

// new-tab carries focus
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.newTab(project: "glen", focus: true))) == .newTab(project: "glen", focus: true))
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.newTab(project: nil, focus: false))) == .newTab(project: nil, focus: false))

// split carries focus
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.split(target: .focused, vertical: true, focus: false)))
        == .split(target: .focused, vertical: true, focus: false))
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.split(target: .pane("ab12"), vertical: false, focus: true)))
        == .split(target: .pane("ab12"), vertical: false, focus: true))

// break carries focus
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.breakPane(target: .pane("ab12"), focus: true)))
        == .breakPane(target: .pane("ab12"), focus: true))
#expect(try ControlWire.decodeRequest(ControlWire.encodeLine(ControlRequest.breakPane(target: .focused, focus: false)))
        == .breakPane(target: .focused, focus: false))
```

Add one new test asserting the backward-compatible default (absent `focus` → `false`):

```swift
@Test func focusDefaultsToFalseWhenAbsent() throws {
    // Simulate an older CLI that omits the focus key.
    #expect(try ControlWire.decodeRequest(#"{"command":"new-tab"}"#) == .newTab(project: nil, focus: false))
    #expect(try ControlWire.decodeRequest(#"{"command":"scratch"}"#) == .scratch(focus: false))
    #expect(try ControlWire.decodeRequest(#"{"command":"split","target":{"kind":"focused"}}"#) == .split(target: .focused, vertical: true, focus: false))
    #expect(try ControlWire.decodeRequest(#"{"command":"break","target":{"kind":"focused"}}"#) == .breakPane(target: .focused, focus: false))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- swift test --filter roundTripsAllRequests`
Expected: FAIL — compile error, `.scratch` is not a function / missing `focus:` argument.

- [ ] **Step 3: Implement the protocol change**

In `Sources/ZettyCore/CLI/ControlProtocol.swift`:

Change the four `enum ControlRequest` cases (currently around lines 11-59):

```swift
    /// Open a project-less, ephemeral "scratch" terminal (plain shell, not
    /// persisted) in the Scratch sidebar section. Background by default; `focus`
    /// switches to it. Response `.pane` with the new pane's short id.
    case scratch(focus: Bool)
```

```swift
    /// Open a new tab in the named project (nil → the active project). Background
    /// by default — the active project/tab and keyboard focus stay put; `focus`
    /// switches to the new tab. Response `.pane` with the new pane's short id.
    case newTab(project: String?, focus: Bool)
```

```swift
    /// Split the targeted pane (vertical = side by side). Background by default —
    /// the split appears but keyboard focus stays on the current pane; `focus`
    /// moves focus to the new pane. Response `.pane` with the new pane's short id.
    case split(target: PaneSelector, vertical: Bool, focus: Bool)
```

```swift
    /// Break the targeted pane out into a new tab inserted right after the
    /// current one. Background by default — the new tab is not selected; `focus`
    /// switches to it. Response `.pane` with the moved pane's short id. Fails when
    /// the pane is the only one in its tab.
    case breakPane(target: PaneSelector, focus: Bool)
```

In `init(from:)` (the decode switch), update the four cases to read `focus` with a default:

```swift
        case "scratch":
            self = .scratch(focus: try container.decodeIfPresent(Bool.self, forKey: .focus) ?? false)
```
```swift
        case "new-tab":
            self = .newTab(
                project: try container.decodeIfPresent(String.self, forKey: .project),
                focus: try container.decodeIfPresent(Bool.self, forKey: .focus) ?? false
            )
```
```swift
        case "split":
            self = .split(
                target: try container.decodeIfPresent(PaneSelector.self, forKey: .target) ?? .focused,
                vertical: try container.decodeIfPresent(Bool.self, forKey: .vertical) ?? true,
                focus: try container.decodeIfPresent(Bool.self, forKey: .focus) ?? false
            )
```
```swift
        case "break":
            self = .breakPane(
                target: try container.decodeIfPresent(PaneSelector.self, forKey: .target) ?? .focused,
                focus: try container.decodeIfPresent(Bool.self, forKey: .focus) ?? false
            )
```

In `encode(to:)`, update the four cases to write `focus`:

```swift
        case .scratch(let focus):
            try container.encode("scratch", forKey: .command)
            try container.encode(focus, forKey: .focus)
```
```swift
        case .newTab(let project, let focus):
            try container.encode("new-tab", forKey: .command)
            try container.encodeIfPresent(project, forKey: .project)
            try container.encode(focus, forKey: .focus)
```
```swift
        case .split(let target, let vertical, let focus):
            try container.encode("split", forKey: .command)
            try container.encode(target, forKey: .target)
            try container.encode(vertical, forKey: .vertical)
            try container.encode(focus, forKey: .focus)
```
```swift
        case .breakPane(let target, let focus):
            try container.encode("break", forKey: .command)
            try container.encode(target, forKey: .target)
            try container.encode(focus, forKey: .focus)
```

Note: `.scratchClear` is unchanged. The `CodingKeys` already include `focus`.

- [ ] **Step 4: Run test to verify it passes**

Run: `mise exec -- swift test --filter ControlProtocol`
Expected: PASS (both `roundTripsAllRequests` and `focusDefaultsToFalseWhenAbsent`).

> Note: this task leaves `ControlCLI.swift` and the app handler NOT compiling yet (they still call the old case shapes). That is fixed in Tasks 3 and 4. Do **not** run a full app build at this checkpoint — only the `swift test` for the protocol. Commit the protocol + its tests together.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/CLI/ControlProtocol.swift Tests/ZettyCoreTests/ControlProtocolTests.swift
git commit -m "feat(cli): add focus flag to newTab/split/break/scratch wire requests"
```

---

### Task 2: Pure model helpers for background structural ops

**Files:**
- Modify: `Sources/ZettyCore/Model/PaneTree.swift`
- Modify: `Sources/ZettyCore/Model/TabList.swift`
- Modify: `Sources/ZettyCore/Model/WorkspaceModel.swift`
- Test: `Tests/ZettyCoreTests/TabListTests.swift`

**Interfaces:**
- Consumes: existing `PaneTree.focus(_:)`, `PaneTree.splitFocused(direction:newSurface:ratio:)`, `PaneTree.closeFocused()`, `TabList.freshTree(workingDir:)`, `TabList.defaultWorkingDir`, `Layout`, `Surface`.
- Produces:
  - `PaneTree.splitPane(_ id: UUID, direction: SplitDirection, newSurface: Surface, ratio: Double = 0.5) -> UUID?` — splits pane `id`, then restores focus to the pane that was focused before, returns `newSurface.id` (nil if `id` absent).
  - `TabList.newBackgroundTab() -> UUID` — appends a fresh single-pane tab WITHOUT changing `activeIndex`; returns the new pane's surface id.
  - `TabList.splitPane(inTreeAt treeIndex: Int, paneID: UUID, direction: SplitDirection, newSurface: Surface, ratio: Double = 0.5) -> UUID?` — thin wrapper writing the mutated tree back into `trees`.
  - `TabList.breakPaneToNewTab(inTreeAt treeIndex: Int, paneID: UUID) -> UUID?` — moves `paneID` out of tree `treeIndex` into a new tab inserted at `treeIndex + 1`, WITHOUT selecting it (keeps the same logical tab visible); returns the moved pane's id.
  - `WorkspaceModel.addScratchProject(makeActive: Bool = true) -> ProjectRuntime` — adds a scratch project; `makeActive: false` leaves the current active project selected.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ZettyCoreTests/TabListTests.swift` (uses the module's existing `Surface`, `PaneTree`, `TabList`, `SplitDirection`, `WorkspaceModel`):

```swift
@Test func newBackgroundTabDoesNotChangeActiveIndex() {
    let list = TabList(defaultWorkingDir: "/tmp")   // starts with one tab, activeIndex 0
    let priorActive = list.activeIndex
    let newID = list.newBackgroundTab()
    #expect(list.trees.count == 2)
    #expect(list.activeIndex == priorActive)             // visible tab unchanged
    #expect(list.trees[1].layout.surfaces.contains { $0.id == newID })
}

@Test func splitPaneKeepsFocusOnOriginalPane() {
    var tree = TabList.freshTree(workingDir: "/tmp")     // single pane
    let original = tree.focusedSurfaceID!
    let added = Surface(workingDir: "/tmp")
    let newID = tree.splitPane(original, direction: .vertical, newSurface: added)
    #expect(newID == added.id)
    #expect(tree.layout.surfaces.count == 2)
    #expect(tree.focusedSurfaceID == original)           // focus did NOT move to the new pane
}

@Test func splitPaneInBackgroundTreeWritesBack() {
    let list = TabList(defaultWorkingDir: "/tmp")
    _ = list.newBackgroundTab()                          // tab index 1, not active
    let target = list.trees[1].focusedSurfaceID!
    let added = Surface(workingDir: "/tmp")
    let newID = list.splitPane(inTreeAt: 1, paneID: target, direction: .horizontal, newSurface: added)
    #expect(newID == added.id)
    #expect(list.trees[1].layout.surfaces.count == 2)
    #expect(list.activeIndex == 0)                       // visible tab still 0
}

@Test func breakPaneToNewTabKeepsCurrentTabVisible() {
    var tree = TabList.freshTree(workingDir: "/tmp")
    let first = tree.focusedSurfaceID!
    let added = Surface(workingDir: "/tmp")
    _ = tree.splitPane(first, direction: .vertical, newSurface: added)
    let list = TabList(trees: [tree], activeIndex: 0)    // one tab, two panes
    let movedID = list.breakPaneToNewTab(inTreeAt: 0, paneID: added.id)
    #expect(movedID == added.id)
    #expect(list.trees.count == 2)                       // new tab inserted
    #expect(list.activeIndex == 0)                       // still viewing the source tab
    #expect(list.trees[1].layout.surfaces.map(\.id) == [added.id])
}

@Test func breakPaneToNewTabRejectsSolePane() {
    let list = TabList(defaultWorkingDir: "/tmp")        // single tab, single pane
    let only = list.trees[0].focusedSurfaceID!
    #expect(list.breakPaneToNewTab(inTreeAt: 0, paneID: only) == nil)
}

@Test func addScratchProjectBackgroundKeepsActive() {
    let ws = WorkspaceModel(projects: [ProjectRuntime(name: "a", rootPath: "/a")], activeIndex: 0)
    _ = ws.addScratchProject(makeActive: false)
    #expect(ws.activeIndex == 0)                         // active project unchanged
    #expect(ws.projects.contains { $0.isScratch })
}
```

> If any initializer used above (`TabList(trees:activeIndex:)`, `TabList(defaultWorkingDir:)`, `WorkspaceModel(projects:activeIndex:)`, `ProjectRuntime(name:rootPath:)`) differs from the real signature, adjust the test to the real one — check the top of `TabList.swift`, `WorkspaceModel.swift`, and `ProjectRuntime.swift` before writing. The assertions stay the same.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise exec -- swift test --filter splitPaneKeepsFocusOnOriginalPane`
Expected: FAIL — `value of type 'PaneTree' has no member 'splitPane'`.

- [ ] **Step 3: Implement the model helpers**

In `Sources/ZettyCore/Model/PaneTree.swift`, add after `splitFocused` (around line 48):

```swift
    /// Splits the pane `id` (regardless of current focus) and restores focus to
    /// whatever pane was focused before — so a background split never moves the
    /// keyboard focus. Returns `newSurface.id`, or nil when `id` is not present.
    @discardableResult
    public mutating func splitPane(_ id: UUID, direction: SplitDirection, newSurface: Surface, ratio: Double = 0.5) -> UUID? {
        guard layout.surfaces.contains(where: { $0.id == id }) else { return nil }
        let priorFocus = focusedSurfaceID
        focus(id)
        guard splitFocused(direction: direction, newSurface: newSurface, ratio: ratio) else { return nil }
        if let priorFocus, layout.surfaces.contains(where: { $0.id == priorFocus }) {
            focus(priorFocus)
        }
        return newSurface.id
    }
```

In `Sources/ZettyCore/Model/TabList.swift`, add after `newTab()` (around line 67):

```swift
    /// Appends a fresh single-pane tab WITHOUT changing `activeIndex` — the
    /// currently visible tab stays visible. Returns the new tab's pane id.
    @discardableResult
    public func newBackgroundTab() -> UUID {
        let tree = TabList.freshTree(workingDir: defaultWorkingDir)
        trees.append(tree)
        // A fresh tree always has exactly one surface.
        return tree.focusedSurfaceID ?? tree.layout.surfaces[0].id
    }

    /// Splits `paneID` inside the tree at `treeIndex`, keeping focus on the
    /// tree's previously focused pane (no active-tab change). Returns the new
    /// pane's id, or nil when the index/pane is invalid.
    @discardableResult
    public func splitPane(inTreeAt treeIndex: Int, paneID: UUID, direction: SplitDirection, newSurface: Surface, ratio: Double = 0.5) -> UUID? {
        guard trees.indices.contains(treeIndex) else { return nil }
        var tree = trees[treeIndex]
        guard let newID = tree.splitPane(paneID, direction: direction, newSurface: newSurface, ratio: ratio) else { return nil }
        trees[treeIndex] = tree
        return newID
    }

    /// Moves `paneID` out of the tree at `treeIndex` into a new single-pane tab
    /// inserted at `treeIndex + 1`, WITHOUT selecting it (the same logical tab
    /// stays visible). Returns the moved pane's id (identity preserved), or nil
    /// when the pane is the tab's only pane or the index/pane is invalid.
    @discardableResult
    public func breakPaneToNewTab(inTreeAt treeIndex: Int, paneID: UUID) -> UUID? {
        guard trees.indices.contains(treeIndex) else { return nil }
        var tree = trees[treeIndex]
        guard tree.layout.surfaces.count > 1,
              let surface = tree.layout.surfaces.first(where: { $0.id == paneID }) else {
            return nil
        }
        tree.focus(paneID)
        guard tree.closeFocused() else { return nil }
        trees[treeIndex] = tree
        let newTree = PaneTree(layout: Layout(root: .leaf(surface)), focusedSurfaceID: surface.id)
        trees.insert(newTree, at: treeIndex + 1)
        // Keep pointing at the SAME logical tab the caller was viewing.
        if activeIndex > treeIndex { activeIndex += 1 }
        return surface.id
    }
```

In `Sources/ZettyCore/Model/WorkspaceModel.swift`, replace `addScratchProject()` (lines 67-75) with a `makeActive`-parameterized version:

```swift
    /// Adds a project-less scratch terminal (rooted at home). It is unpinned (so
    /// it lands in the Scratch section) and ephemeral. `makeActive` (default
    /// true) switches to it; pass false to add it in the background.
    @discardableResult
    public func addScratchProject(makeActive: Bool = true) -> ProjectRuntime {
        let home = NSHomeDirectory()
        let p = ProjectRuntime(name: nextScratchName(), rootPath: home, isScratch: true)
        projects.append(p)
        if makeActive { activeIndex = projects.count - 1 }
        regroup()   // keeps it after the pinned group
        return p
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise exec -- swift test --filter TabList` then `mise exec -- swift test`
Expected: PASS — all new tests green, whole `ZettyCore` suite still green (the `addScratchProject()` callers use the default `makeActive: true`, so they are unaffected).

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/Model/PaneTree.swift Sources/ZettyCore/Model/TabList.swift Sources/ZettyCore/Model/WorkspaceModel.swift Tests/ZettyCoreTests/TabListTests.swift
git commit -m "feat(core): background split/new-tab/break helpers that preserve active selection"
```

---

### Task 3: CLI parsing — accept `--focus`, update usage, scratch returns a pane

**Files:**
- Modify: `Sources/ZettyCore/CLI/ControlCLI.swift`
- Test: `Tests/ZettyCoreTests/NewProjectRequestTests.swift` (add CLI-recognition tests near the existing `cli*` ones) — or a new `Tests/ZettyCoreTests/CLIFocusFlagTests.swift`.

**Interfaces:**
- Consumes: `ControlRequest.newTab(project:focus:)`, `.split(target:vertical:focus:)`, `.breakPane(target:focus:)`, `.scratch(focus:)` from Task 1.
- Produces: `--focus` accepted on `new-tab`, `split`, `break`, `scratch`; `scratch` now goes through `expectPane` (prints the new pane id).

- [ ] **Step 1: Write the failing tests**

Create `Tests/ZettyCoreTests/CLIFocusFlagTests.swift`:

```swift
import Testing
import Foundation
@testable import ZettyCore

// These verbs fail BEFORE the socket round-trip only on bad args; --help always
// exits 0 pre-socket. We assert --help still parses with --focus present, which
// exercises the arg loop without needing a running app.
@Test func scratchHelpExitsZero() {
    #expect(ControlCLI.run(["scratch", "--help"]) == 0)
}

@Test func newTabRejectsUnknownArg() {
    // An unknown flag is rejected pre-socket → exit 1 (proves --focus is a known,
    // consumed flag while a typo is not).
    #expect(ControlCLI.run(["new-tab", "--nope"]) == 1)
}

@Test func splitRejectsUnknownArg() {
    #expect(ControlCLI.run(["split", "--nope"]) == 1)
}

@Test func cliStillRecognizesAllVerbs() {
    for verb in ["new-tab", "split", "break", "scratch"] {
        #expect(ControlCLI.recognizes([verb]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise exec -- swift test --filter CLIFocusFlag`
Expected: FAIL to compile — `ControlCLI.swift` still references the old case shapes (`.scratch`, `.newTab(project:)`, etc.), so the whole module won't build until Step 3.

- [ ] **Step 3: Update the CLI**

In `Sources/ZettyCore/CLI/ControlCLI.swift`:

**(a)** `runNewTab` — add `--focus` to the arg loop and pass it through. Replace the body (lines 226-244):

```swift
    private static func runNewTab(_ arguments: [String]) -> Int32 {
        var project: String?
        var focus = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--project":
                index += 1
                guard index < arguments.count else { return failure("--project needs a value") }
                project = arguments[index]
            case "--focus":
                focus = true
            case "--help", "-h":
                print(usage)
                return 0
            default:
                return failure("unknown argument \"\(arguments[index])\"")
            }
            index += 1
        }
        return expectPane(.newTab(project: project, focus: focus))
    }
```

**(b)** `runSplit` — add `--focus`. In the arg `switch` add a `case "--focus": focus = true`, declare `var focus = false` near `var vertical = true`, and change the final line to `return expectPane(.split(target: target, vertical: vertical, focus: focus))`.

**(c)** `runBreak` — add `--focus`. Declare `var focus = false`, add `case "--focus": focus = true` to the loop, and change the final line to `return expectPane(.breakPane(target: target, focus: focus))`.

**(d)** Replace the `case "scratch":` dispatch line (line 126-127) with a dedicated handler call:

```swift
        case "scratch":
            return runScratch(arguments)
```

and add the handler near `runNewTab`:

```swift
    private static func runScratch(_ arguments: [String]) -> Int32 {
        var focus = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--focus":
                focus = true
            case "--help", "-h":
                print(usage)
                return 0
            default:
                return failure("unknown argument \"\(arguments[index])\"")
            }
            index += 1
        }
        return expectPane(.scratch(focus: focus))
    }
```

**(e)** Update the `usage` string. Change the `new-tab`, `split`, `break`, and `scratch` lines and the agent notes to document background-by-default + `--focus`. Use this wording (match the surrounding column alignment):

```
      zetty new-tab [--project <name>] [--focus]
                                              open a tab in the background (active
                                              project by default); --focus switches
                                              to it. Prints the new pane id.
```
```
      zetty split [--pane <id> | --cwd <path>] [--horizontal] [--focus]
                                              split a pane in the background (focus
                                              stays put); --focus moves focus to the
                                              new pane. Prints the new pane id.
```
```
      zetty break [--pane <id> | --cwd <path>] [--focus]
                                              move a pane into a new adjacent tab in
                                              the background; --focus switches to it.
```
```
      zetty scratch [--focus]                 open an ephemeral scratch terminal in
                                              the background; --focus switches to it.
                                              Prints the new pane id.
```

In the agent-notes block (lines ~65-71), replace the note that says "new-tab/split select the new pane (it must be visible for its shell to spawn)…" with:

```
      - new-tab/split/break/scratch run in the BACKGROUND by default: they never
        change the active project or keyboard focus, so an agent can reshape the
        workspace while you keep typing. Pass --focus to switch to the result.
      - a background pane's shell spawns when you first view it (like add-project),
        so `zetty send` to a brand-new background pane fails until it is viewed or
        created with --focus.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise exec -- swift test --filter CLIFocusFlag` then `mise exec -- swift test`
Expected: PASS — module compiles, all CLI + protocol + model tests green.

Also build the standalone CLI to be sure: `mise exec -- swift build` → Expected: builds clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/CLI/ControlCLI.swift Tests/ZettyCoreTests/CLIFocusFlagTests.swift
git commit -m "feat(cli): parse --focus on new-tab/split/break/scratch; scratch prints pane id"
```

---

### Task 4: App layer — background paths in TerminalViewController + handler wiring

**Files:**
- Modify: `App/Sources/App/TerminalViewController.swift` (`openNewTab`, `splitPane`, `breakPaneToTab`, `newScratchTerminal`)
- Modify: `App/Sources/App/AppDelegate.swift` (`handleOnMain` switch — pass `focus` through; `scratch` now returns a pane)
- No new unit tests (this layer needs live libghostty + a window; verified by build + manual runtime check — see Step 4).

**Interfaces:**
- Consumes: Task 2 model helpers; existing `selectProject(at:)`, `focusPane(at:)`, `locate(shortID:)`, `refreshTabBar()`, `refreshSidebar()`, `rebuildSurfaceNodeView()`, `focusedTerminalView()`, `onWorkspaceDidChange`, `SessionPersistence.shortID(for:)`.
- Produces:
  - `TerminalViewController.openNewTab(inProject:focus:) -> Result<String, ControlError>`
  - `TerminalViewController.splitPane(target:vertical:focus:) -> Result<String, ControlError>`
  - `TerminalViewController.breakPaneToTab(target:focus:) -> Result<String, ControlError>`
  - `TerminalViewController.newScratchTerminal(focus:) -> String` (returns the new pane's short id)

- [ ] **Step 1: Rewrite `openNewTab` (background-by-default)**

Replace `openNewTab(inProject:)` (lines 1318-1334) with:

```swift
    func openNewTab(inProject name: String?, focus: Bool = false) -> Result<String, ControlError> {
        let targetIndex: Int
        if let name {
            guard let idx = workspace.projects.firstIndex(where: {
                $0.name.lowercased() == name.lowercased()
            }) else {
                return .failure(.noSuchPane("no project named \"\(name)\""))
            }
            targetIndex = idx
        } else {
            targetIndex = workspace.activeIndex
        }
        let tabList = workspace.projects[targetIndex].tabList
        let newPaneID = tabList.newBackgroundTab()
        let newTabIndex = tabList.trees.count - 1

        if focus {
            tabList.select(index: newTabIndex)
            if targetIndex != workspace.activeIndex {
                selectProject(at: targetIndex)          // rebuilds + focuses the now-active tab
            } else {
                refreshTabBar()
                rebuildSurfaceNodeView()
                refreshSidebar()
                if let focused = focusedTerminalView() {
                    view.window?.makeFirstResponder(focused)
                }
            }
        } else {
            // Background: the tab exists and shows in the bar, but the visible
            // tab and keyboard focus are unchanged.
            refreshTabBar()
            refreshSidebar()
        }
        onWorkspaceDidChange?()
        return .success(SessionPersistence.shortID(for: newPaneID))
    }
```

- [ ] **Step 2: Rewrite `splitPane` (background-by-default)**

Replace `splitPane(target:vertical:)` (lines 1494-1510) with:

```swift
    func splitPane(target: PaneSelector, vertical: Bool, focus: Bool = false) -> Result<String, ControlError> {
        do {
            let pane = try target.resolve(in: statusSnapshot().panes)
            guard let location = locate(shortID: pane.id) else {
                return .failure(.noSuchPane("pane \(pane.id) not found"))
            }
            let tabList = workspace.projects[location.projectIndex].tabList
            let workingDir = tabList.trees[location.tabIndex].layout.surfaces
                .first(where: { $0.id == location.surfaceID })?.workingDir ?? NSHomeDirectory()
            let newSurface = Surface(workingDir: workingDir)
            guard let newID = tabList.splitPane(
                inTreeAt: location.tabIndex, paneID: location.surfaceID,
                direction: vertical ? .vertical : .horizontal, newSurface: newSurface
            ) else {
                return .failure(.noSuchPane("split failed"))
            }

            if focus {
                focusPane(at: (location.projectIndex, location.tabIndex, newID))
            } else if location.projectIndex == workspace.activeIndex,
                      tabList.activeIndex == location.tabIndex {
                // Visible tree: show the new split, keep the caret on the user's pane
                // (splitPane restored focus to the original in-model).
                rebuildSurfaceNodeView()
                refreshSidebar()
                if let focused = focusedTerminalView() {
                    view.window?.makeFirstResponder(focused)
                }
            } else {
                refreshSidebar()
            }
            onWorkspaceDidChange?()
            return .success(SessionPersistence.shortID(for: newID))
        } catch {
            return .failure(.noSuchPane(error.localizedDescription))
        }
    }
```

- [ ] **Step 3: Rewrite `breakPaneToTab` (background-by-default)**

Replace `breakPaneToTab(target:)` (lines 1514-1531) with:

```swift
    func breakPaneToTab(target: PaneSelector, focus: Bool = false) -> Result<String, ControlError> {
        do {
            let pane = try target.resolve(in: statusSnapshot().panes)
            guard let location = locate(shortID: pane.id) else {
                return .failure(.noSuchPane("pane \(pane.id) not found"))
            }
            let tabList = workspace.projects[location.projectIndex].tabList
            guard let movedID = tabList.breakPaneToNewTab(
                inTreeAt: location.tabIndex, paneID: location.surfaceID
            ) else {
                return .failure(.noSuchPane("pane \(pane.id) is the only pane in its tab"))
            }
            let newTabIndex = location.tabIndex + 1

            if focus {
                if location.projectIndex != workspace.activeIndex {
                    selectProject(at: location.projectIndex)
                }
                tabList.select(index: newTabIndex)
                refreshTabBar()
                rebuildSurfaceNodeView()
                refreshSidebar()
                if let focused = focusedTerminalView() {
                    view.window?.makeFirstResponder(focused)
                }
            } else {
                refreshTabBar()
                refreshSidebar()
                if location.projectIndex == workspace.activeIndex {
                    // The pane left the visible tab — re-render and keep focus on
                    // whatever pane the visible tab now focuses.
                    rebuildSurfaceNodeView()
                    if let focused = focusedTerminalView() {
                        view.window?.makeFirstResponder(focused)
                    }
                }
            }
            onWorkspaceDidChange?()
            return .success(SessionPersistence.shortID(for: movedID))
        } catch {
            return .failure(.noSuchPane(error.localizedDescription))
        }
    }
```

- [ ] **Step 4: Add a background-capable `newScratchTerminal(focus:)`**

In `App/Sources/App/TerminalViewController.swift`, replace the `@objc func newScratchTerminal(_ sender:)` (lines 1952-1961) with a thin wrapper plus a returning variant:

```swift
    /// Interactive entry (⌃⌘N / palette / menu): always switches to the new
    /// scratch terminal.
    @objc func newScratchTerminal(_ sender: Any? = nil) {
        _ = newScratchTerminal(focus: true)
    }

    /// Creates a project-less, ephemeral scratch terminal rooted at home. When
    /// `focus` is true it becomes active and spawns immediately; when false it is
    /// added to the Scratch section without stealing the current view (its shell
    /// spawns when first viewed). Returns the new pane's short id.
    @discardableResult
    func newScratchTerminal(focus: Bool) -> String {
        let project = workspace.addScratchProject(makeActive: focus)
        refreshTabBar()
        refreshSidebar()
        if focus {
            onActiveProjectChanged?()
            rebuildSurfaceNodeView()   // spawns the pane
            if let focused = focusedTerminalView() {
                view.window?.makeFirstResponder(focused)
            }
        } else {
            onWorkspaceDidChange?()     // persist without switching
        }
        let surface = project.tabList.activeTree.focusedSurface
            ?? project.tabList.activeTree.layout.surfaces[0]
        return SessionPersistence.shortID(for: surface.id)
    }
```

- [ ] **Step 5: Wire `focus` through `AppDelegate.handleOnMain`**

In `App/Sources/App/AppDelegate.swift` (lines 1064-1115), update these cases:

```swift
        case .scratch(let focus):
            return .pane(tvc.newScratchTerminal(focus: focus))
```
```swift
        case .newTab(let project, let focus):
            switch tvc.openNewTab(inProject: project, focus: focus) {
            case .success(let pane): return .pane(pane)
            case .failure(let error): return .error(error.localizedDescription)
            }
```
```swift
        case .split(let target, let vertical, let focus):
            switch tvc.splitPane(target: target, vertical: vertical, focus: focus) {
            case .success(let pane): return .pane(pane)
            case .failure(let error): return .error(error.localizedDescription)
            }
```
```swift
        case .breakPane(let target, let focus):
            switch tvc.breakPaneToTab(target: target, focus: focus) {
            case .success(let pane): return .pane(pane)
            case .failure(let error): return .error(error.localizedDescription)
            }
```

- [ ] **Step 6: Build the app**

Run:
```bash
mise exec -- tuist generate --no-open
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. (No files were added/removed, so `tuist generate` is only needed if the project isn't already generated; running it is harmless.)

- [ ] **Step 7: Manual runtime verification (GUI — can't be unit-tested)**

Rebuild + install to `/Applications` (per project workflow), relaunch, then from a pane inside Zetty:

1. **No project shift on split:** focus a pane in project A and start typing. From another pane run `zetty split --cwd <a path in project B>`. Expect: A stays active, your caret keeps blinking in A, and B's tree gains a pane (visible when you switch to B).
2. **Same-project split shows but keeps focus:** while typing in a pane of the *active* project, run `zetty split --pane <that pane's id>`. Expect: the pane splits in view, but the caret stays in your original pane.
3. **new-tab background:** `zetty new-tab --project B`. Expect: a new tab pill appears under B, active project unchanged, no focus jump. `zetty new-tab --project B --focus` → switches to B and the new tab.
4. **scratch background:** `zetty scratch` prints a pane id, adds a Scratch entry, does NOT switch. `zetty scratch --focus` → switches to it.
5. **break background:** `zetty break --pane <id in a background project>`. Expect: a new tab appears in that project; your view doesn't move.

- [ ] **Step 8: Commit**

```bash
git add App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat(app): CLI new-tab/split/break/scratch run in background unless --focus"
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md` (Control CLI section)
- Modify: `CLAUDE.md` and `AGENTS.md` (byte-identical; Control CLI command list)

**Interfaces:** none (docs only).

- [ ] **Step 1: Update `README.md`**

In the Control CLI command list, update the `new-tab`, `split`, `break`, and `scratch` entries to state they run in the background by default and take `--focus`. Add, near the CLI notes, a sentence:

> `new-tab`, `split`, `break`, and `scratch` never change the active project or
> keyboard focus by default — an agent can reshape your workspace while you keep
> typing. Pass `--focus` to switch to the result. A background pane's shell
> spawns when you first view it, so `zetty send` to a brand-new background pane
> fails until it is viewed or created with `--focus`.

Also note that `scratch` now prints the new pane's id (like `new-tab`/`split`).

- [ ] **Step 2: Update `CLAUDE.md` and `AGENTS.md` identically**

In the `## Control CLI (zetty)` command bullet list, update the `new-tab`/`split` bullet and the `scratch` bullet:

```
  - `new-tab [--project <name>] [--focus]` / `split [--pane|--cwd]
    [--horizontal] [--focus]` — create a tab / split a pane in the BACKGROUND
    by default (active project + focus stay put); `--focus` switches to the
    result. Both print the new pane's bare id.
```
```
  - `scratch [--focus]` — open a project-less, ephemeral scratch terminal
    (rooted at home, plain shell, never persisted) in the Scratch section, in
    the background by default; `--focus` switches to it. Prints the new pane id.
    `scratch-clear` closes and clears every scratch terminal at once.
```

And in the `break` line, add `[--focus]` and note it defaults to background.

Verify byte-identical:

```bash
diff CLAUDE.md AGENTS.md && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md AGENTS.md docs/plans/2026-07-09-cli-no-focus-steal-design.md docs/superpowers/plans/2026-07-09-cli-no-focus-steal.md
git commit -m "docs: background-by-default CLI verbs + --focus; design/plan docs"
```

---

## Self-Review

**Spec coverage** (design doc → task):
- `focus` on newTab/split/break/scratch wire requests → Task 1 ✅
- Background model ops preserving active selection → Task 2 ✅
- CLI `--focus` parsing + `--help` grammar + agent notes → Task 3 ✅
- App-layer background paths + handler wiring → Task 4 ✅
- Same-project split shows layout but keeps focus (design point 2) → Task 4 Step 2 (`rebuildSurfaceNodeView` + re-focus original) ✅
- Interactive keyboard/menu/palette paths untouched → Task 4 keeps `@objc newScratchTerminal`, `newTab(_:)`, `splitVertical/Horizontal`, `breakPaneIntoTab` as-is ✅
- Docs (README + CLAUDE/AGENTS) → Task 5 ✅
- No eager spawn / no input buffering (explicitly dropped) → not implemented, by design ✅

**Placeholder scan:** no TBD/TODO; every code step shows full code. ✅

**Type consistency:** `newBackgroundTab() -> UUID`, `splitPane(inTreeAt:paneID:direction:newSurface:ratio:) -> UUID?`, `breakPaneToNewTab(inTreeAt:paneID:) -> UUID?`, `addScratchProject(makeActive:)`, `newScratchTerminal(focus:) -> String` used consistently across Tasks 2 and 4. Wire case shapes `.newTab(project:focus:)`, `.split(target:vertical:focus:)`, `.breakPane(target:focus:)`, `.scratch(focus:)` consistent across Tasks 1, 3, 4. ✅

**Known verification gap:** the app-layer focus/selection behavior can't be unit-tested (needs live libghostty + a window; `ZettyCore` stays AppKit-free). It is covered by the Task 4 Step 7 manual runtime checklist — consistent with the repo (no `TerminalViewController` unit tests exist) and the "GUI verification is TCC-denied" constraint.
