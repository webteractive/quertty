# Break Pane into Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`docs/plans/2026-07-04-break-pane-into-tab-design.md`](2026-07-04-break-pane-into-tab-design.md) — the source of truth for *what/why*. This plan is the *how/order*; step references point back to the spec's sections.

**Goal:** Move the focused pane of the active tab into a new tab inserted right after it, re-parenting the live terminal without recreating it (tmux `break-pane`).

**Architecture:** A pure-core mutation on `TabList` (`breakFocusedPaneIntoNewTab()`) does the model move; the moved `Surface` keeps its `id`, so `rebuildSurfaceNodeView()`'s prune-by-union keeps the live ghostty surface alive. Five trigger surfaces (prefix key, app menu, command palette, per-pane button, pane context menu) all funnel through one `PaneActions` method.

**Tech Stack:** Swift, AppKit (App target), swift-testing (`import Testing`) for `ZettyCore` unit tests, Tuist-generated Xcode project, libghostty via `SurfaceRegistry`.

## Global Constraints

- **Keep `ZettyCore` pure** — no AppKit imports in `Sources/ZettyCore/**`.
- **Never hardcode a color** — read `ZTheme.current.<token>Color`; the new button tints with `fg3Color`, matching the existing `×`.
- **No debug `NSLog`/`print`** in committed code.
- **Commits require Glen's approval** (per CLAUDE.md: never commit automatically). Each "Commit" step means *stage the change and ask Glen before committing*.
- **No new source files** are added by this plan — every change modifies an existing file, so no `tuist generate` is required. Run `ZettyCore` tests with `mise exec -- tuist test`. If a build is needed for the AppKit tasks: `mise exec -- tuist generate --no-open` is unnecessary (no file adds); build with `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`. If a bogus "Manifest not found …/AgentLogos" error appears, run `mise exec -- tuist clean` first.
- **Prefix key** for break is `!`; **menu/palette shortcut** is `⌥⌘T` (`t` + `[.command, .option]`), free today.

---

### Task 1: Core — `TabList.breakFocusedPaneIntoNewTab()`

Implements spec §"Core (pure, `ZettyCore`)".

**Files:**
- Modify: `Sources/ZettyCore/Model/TabList.swift` (add one method after `newTab()`, ~line 59)
- Test: `Tests/ZettyCoreTests/TabListTests.swift` (append cases)

**Interfaces:**
- Consumes: existing `PaneTree.closeFocused()`, `PaneTree.splitFocused(direction:newSurface:)`, `Layout`, `Surface`, `TabList.activeTree`, `TabList.trees`, `TabList.activeIndex`.
- Produces: `@discardableResult public func breakFocusedPaneIntoNewTab() -> Bool` on `TabList`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ZettyCoreTests/TabListTests.swift`:

```swift
// MARK: - Break pane into tab

/// Build a fresh 2-pane active tab (focused = the second, newly split pane).
private func twoPaneTabList() -> TabList {
    let list = TabList(defaultWorkingDir: "/tmp/proj")
    var tree = list.activeTree
    _ = tree.splitFocused(direction: .vertical,
                          newSurface: Surface(workingDir: "/tmp/proj"))
    list.activeTree = tree
    return list
}

@Test func breakMovesFocusedPaneIntoNewAdjacentTab() {
    let list = twoPaneTabList()
    let movedID = list.activeTree.focusedSurfaceID!
    let sourceIndex = list.activeIndex

    #expect(list.breakFocusedPaneIntoNewTab() == true)

    #expect(list.trees.count == 2)
    #expect(list.activeIndex == sourceIndex + 1)          // inserted right after
    // New tab is a single pane holding the SAME surface id (live view survives).
    #expect(list.activeTree.layout.surfaces.map(\.id) == [movedID])
    #expect(list.activeTree.focusedSurfaceID == movedID)
    // Source tab collapsed to its remaining pane and no longer holds the moved id.
    #expect(list.trees[sourceIndex].layout.surfaces.contains { $0.id == movedID } == false)
    #expect(list.trees[sourceIndex].layout.surfaces.count == 1)
    #expect(list.trees[sourceIndex].focusedSurfaceID != nil)
}

@Test func breakIsNoOpOnSinglePaneTab() {
    let list = TabList(defaultWorkingDir: "/tmp/proj")   // one pane
    #expect(list.breakFocusedPaneIntoNewTab() == false)
    #expect(list.trees.count == 1)
    #expect(list.activeIndex == 0)
}

@Test func breakClearsSourceZoomAndYieldsUnzoomedTab() {
    let list = twoPaneTabList()
    var tree = list.activeTree
    _ = tree.toggleZoom()                                 // zoom the focused pane
    list.activeTree = tree
    #expect(list.activeTree.zoomedSurfaceID != nil)

    #expect(list.breakFocusedPaneIntoNewTab() == true)

    #expect(list.activeTree.zoomedSurfaceID == nil)        // new tab unzoomed
    let sourceIndex = list.activeIndex - 1
    #expect(list.trees[sourceIndex].zoomedSurfaceID == nil) // source zoom cleared
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: FAIL — `value of type 'TabList' has no member 'breakFocusedPaneIntoNewTab'`.

- [ ] **Step 3: Implement the method**

In `Sources/ZettyCore/Model/TabList.swift`, add after `newTab()`:

```swift
/// Move the active tab's focused pane into a new single-pane tab inserted
/// right after the current tab, which becomes active. The moved `Surface`
/// keeps its identity (id/workingDir/command/lastTitle), so the live terminal
/// is re-parented rather than recreated. Returns false (no-op) when the active
/// tab has a single pane or no focused surface.
@discardableResult
public func breakFocusedPaneIntoNewTab() -> Bool {
    var tree = activeTree
    guard tree.layout.surfaces.count > 1,
          let id = tree.focusedSurfaceID,
          let surface = tree.layout.surfaces.first(where: { $0.id == id }) else {
        return false
    }
    // Removing via closeFocused reuses the collapse + source-focus fix and
    // clears the source tab's zoom if the moved pane was the zoomed one.
    guard tree.closeFocused() else { return false }
    activeTree = tree

    let newTree = PaneTree(layout: Layout(root: .leaf(surface)),
                           focusedSurfaceID: surface.id)
    trees.insert(newTree, at: activeIndex + 1)
    activeIndex += 1
    return true
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: PASS (all three new cases plus the existing suite).

- [ ] **Step 5: Commit** (stage; ask Glen before committing)

```bash
git add Sources/ZettyCore/Model/TabList.swift Tests/ZettyCoreTests/TabListTests.swift
git commit -m "feat(core): break focused pane into a new adjacent tab"
```

---

### Task 2: Core — `BindingCommand.breakPane` + default `!` bind

Implements spec §"Command plumbing" (the `BindingCommand` half).

**Files:**
- Modify: `Sources/ZettyCore/Keybindings/BindingCommand.swift` (enum case, name table, default prefix table)
- Test: `Tests/ZettyCoreTests/BindingCommandTests.swift`

**Interfaces:**
- Produces: `BindingCommand.breakPane` (config name `break-pane`), present in `defaultPrefixTable` under `!`.

- [ ] **Step 1: Write the failing tests**

In `Tests/ZettyCoreTests/BindingCommandTests.swift`, add `.breakPane` to the array in `commandConfigNameRoundTripsForEveryPrefixCommand` (the `// Panes` line becomes):

```swift
        .closePane, .zoomPane, .breakPane,
```

and add a new test:

```swift
@Test func breakPaneBoundToBangByDefault() {
    #expect(prefixDefault("!") == .breakPane)
    #expect(BindingCommand(configName: "break-pane") == .breakPane)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: FAIL — `type 'BindingCommand' has no member 'breakPane'`.

- [ ] **Step 3: Implement**

In `Sources/ZettyCore/Keybindings/BindingCommand.swift`:

Add the case under the `// Prefix table — panes` group (after `case zoomPane`):

```swift
    case breakPane
```

Add to `namesByCommand` (after the `.zoomPane` line):

```swift
        .breakPane: "break-pane",
```

Add to `defaultPrefixTable` (after `bind("z", .zoomPane)`):

```swift
        bind("!", .breakPane)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: PASS.

- [ ] **Step 5: Commit** (stage; ask Glen before committing)

```bash
git add Sources/ZettyCore/Keybindings/BindingCommand.swift Tests/ZettyCoreTests/BindingCommandTests.swift
git commit -m "feat(core): add break-pane binding command bound to prefix !"
```

---

### Task 3: App — dispatch + `PaneActions` methods

Implements spec §"Command plumbing" (the AppKit half). No unit tests (consistent with the rest of the App target); verified by build + Task 7 manual check.

**Files:**
- Modify: `App/Sources/App/KeyInterceptor.swift:186` (add a dispatch case)
- Modify: `App/Sources/App/PaneActions.swift` (two new methods)

**Interfaces:**
- Consumes: `TabList.breakFocusedPaneIntoNewTab()` (Task 1), `BindingCommand.breakPane` (Task 2), existing `rebuildAndFocus()`, `workspace.activeTabList`, `paneTree`.
- Produces: `@objc func breakPaneIntoTab(_ sender: Any?)` and `func breakPane(surfaceID: UUID)` on `TerminalViewController`.

- [ ] **Step 1: Add the dispatch case**

In `App/Sources/App/KeyInterceptor.swift`, in `perform(binding:interceptor:)`, after `case .zoomPane: zoomPane(nil)`:

```swift
        case .breakPane: breakPaneIntoTab(nil)
```

- [ ] **Step 2: Add the actions**

In `App/Sources/App/PaneActions.swift`, after the `closePane(surfaceID:confirmIfBusy:)` method (before `// MARK: - Helpers`):

```swift
    // MARK: - Break action

    /// Move the focused pane into a new tab right after the current one.
    /// No-op if it is the only pane in the tab. Prefix `!` · ⌥⌘T · palette · menu.
    @objc func breakPaneIntoTab(_ sender: Any?) {
        guard workspace.activeTabList.breakFocusedPaneIntoNewTab() else { return }
        rebuildAndFocus()
    }

    /// Break the pane identified by `surfaceID` (called by the per-pane button
    /// and the pane context menu): focus it first, then break.
    func breakPane(surfaceID: UUID) {
        paneTree.focus(surfaceID)
        guard workspace.activeTabList.breakFocusedPaneIntoNewTab() else { return }
        rebuildAndFocus()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (If "Manifest not found …/AgentLogos" appears, `mise exec -- tuist clean` then rebuild.)

- [ ] **Step 4: Commit** (stage; ask Glen before committing)

```bash
git add App/Sources/App/KeyInterceptor.swift App/Sources/App/PaneActions.swift
git commit -m "feat: dispatch break-pane and add PaneActions break methods"
```

---

### Task 4: App — App menu item + command palette entry

Implements spec §"Trigger surfaces" items 2 and 3.

**Files:**
- Modify: `App/Sources/App/AppDelegate.swift` (menu item after "Close Tab", ~line 1001; `validateMenuItem`… note: `validateMenuItem` lives in `TerminalViewController.swift:1933`)
- Modify: `App/Sources/App/TerminalViewController.swift:1011` (palette entry) and `:1933` (`validateMenuItem`)

**Interfaces:**
- Consumes: `breakPaneIntoTab(_:)` (Task 3), `PaletteCommand`, `workspace.activeTabList`.
- Produces: menu item, palette command, and enable-state logic keyed on active-tab pane count.

- [ ] **Step 1: Add the app menu item**

In `App/Sources/App/AppDelegate.swift`, immediately after the "Close Tab" item is added to `shellMenu` (after line ~1001, before the following `shellMenu.addItem(.separator())`):

```swift
        // "Break Pane into Tab"  ⌥⌘T
        let breakPane = NSMenuItem(
            title: "Break Pane into Tab",
            action: #selector(TerminalViewController.breakPaneIntoTab(_:)),
            keyEquivalent: "t"
        )
        breakPane.keyEquivalentModifierMask = [.command, .option]
        shellMenu.addItem(breakPane)
```

- [ ] **Step 2: Add the enable-state to `validateMenuItem`**

In `App/Sources/App/TerminalViewController.swift`, replace the body of `validateMenuItem(_:)` (line ~1933) with:

```swift
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(removeProject(_:)) {
            return workspace.projects.count > 1
        }
        if menuItem.action == #selector(breakPaneIntoTab(_:)) {
            return workspace.activeTabList.activeTree.layout.surfaces.count > 1
        }
        return true
    }
```

- [ ] **Step 3: Add the command palette entry**

In `App/Sources/App/TerminalViewController.swift`, in `buildCommands()`, immediately after the "Close Pane" `PaletteCommand` (line ~1011):

```swift
            PaletteCommand(glyph: "↗", label: "Break Pane into Tab", kbd: "⌥⌘T") { [weak self] in self?.breakPaneIntoTab(nil) },
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit** (stage; ask Glen before committing)

```bash
git add App/Sources/App/AppDelegate.swift App/Sources/App/TerminalViewController.swift
git commit -m "feat: break-pane app menu item (⌥⌘T) and command palette entry"
```

---

### Task 5: App — per-pane break button + `onBreak` plumbing

Implements spec §"Trigger surfaces" item 4.

**Files:**
- Modify: `App/Sources/App/SurfaceNodeView.swift` (thread `onBreak` through `SurfaceNodeView` init, `buildContent`, `RatioSplitView` init, and `LeafContainerView`; add the button)
- Modify: `App/Sources/App/TerminalViewController.swift:1841` (`rebuildSurfaceNodeView` — pass `onBreak`)

**Interfaces:**
- Consumes: `breakPane(surfaceID:)` (Task 3).
- Produces: `onBreak: ((UUID) -> Void)?` parameter on `SurfaceNodeView.init` and `RatioSplitView.init`, and a break button in `LeafContainerView` shown when `showsClose` is true.

- [ ] **Step 1: Thread `onBreak` through `SurfaceNodeView`**

In `App/Sources/App/SurfaceNodeView.swift`, `SurfaceNodeView.init` — add the parameter after `onClose`:

```swift
        onClose: ((UUID) -> Void)? = nil,
        onBreak: ((UUID) -> Void)? = nil,
```

Pass it into `buildContent` (add `onBreak: onBreak,` to the call), and add `onBreak: ((UUID) -> Void)?,` to `buildContent`'s signature after `onClose`.

In `buildContent`'s `.leaf` case, pass it to `LeafContainerView`:

```swift
            let container = LeafContainerView(
                surfaceID: surface.id,
                terminalView: terminalView,
                isFocused: surface.id == focusedSurfaceID,
                showsClose: showsClose,
                onClose: onClose,
                onBreak: onBreak
            )
```

In `buildContent`'s `.split` case, pass it to `RatioSplitView` (add `onBreak: onBreak,` after `onClose: onClose,`).

- [ ] **Step 2: Thread `onBreak` through `RatioSplitView`**

In `RatioSplitView.init`, add the parameter after `onClose`:

```swift
        onClose: ((UUID) -> Void)? = nil,
        onBreak: ((UUID) -> Void)? = nil,
```

and pass `onBreak: onBreak,` into both child `SurfaceNodeView(...)` constructions (after `onClose: onClose,`).

- [ ] **Step 3: Add the button to `LeafContainerView`**

In `LeafContainerView`, add a stored property near `onClose`:

```swift
    private var onBreak: ((UUID) -> Void)?
    private var breakButton: NSButton?
```

Extend `init` signature (after `onClose`):

```swift
        onClose: ((UUID) -> Void)?,
        onBreak: ((UUID) -> Void)? = nil,
```

Assign in `init` (next to `self.onClose = onClose`):

```swift
        self.onBreak = onBreak
```

In the `if showsClose {` block, add the break button after `addCloseButton()`:

```swift
            addBreakButton()
```

Add the builder method after `addCloseButton()`:

```swift
    private func addBreakButton() {
        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .circular
        button.isBordered = false
        button.title = ""
        if let image = NSImage(systemSymbolName: "arrow.up.forward.square",
                               accessibilityDescription: "Break pane into tab") {
            button.image = image
        } else {
            button.title = "↗"
        }
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = ZTheme.current.fg3Color
        button.toolTip = "Break pane into tab"
        button.target = self
        button.action = #selector(breakButtonTapped)

        addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 18),
            button.heightAnchor.constraint(equalToConstant: 18),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            // Sit just left of the × (× trailing = -4, width 18, +4 gap).
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -26),
        ])

        breakButton = button
    }

    @objc private func breakButtonTapped() {
        onBreak?(surfaceID)
    }
```

- [ ] **Step 4: Wire the closure in `rebuildSurfaceNodeView`**

In `App/Sources/App/TerminalViewController.swift`, in the `SurfaceNodeView(...)` construction inside `rebuildSurfaceNodeView()` (line ~1841), add after the `onClose:` argument:

```swift
            onBreak: { [weak self] id in self?.breakPane(surfaceID: id) },
```

- [ ] **Step 5: Build**

Run: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit** (stage; ask Glen before committing)

```bash
git add App/Sources/App/SurfaceNodeView.swift App/Sources/App/TerminalViewController.swift
git commit -m "feat: per-pane break-into-tab button beside the close button"
```

---

### Task 6: App — pane context menu

Implements spec §"Trigger surfaces" item 5.

**Files:**
- Modify: `App/Sources/App/SurfaceNodeView.swift` (`LeafContainerView` — attach an `NSMenu` when closable)

**Interfaces:**
- Consumes: `onBreak` and `onClose` closures already stored on `LeafContainerView` (Task 5).
- Produces: a right-click context menu on the pane chrome (gutter), not the terminal body.

- [ ] **Step 1: Attach the menu**

In `LeafContainerView`, inside the `if showsClose {` block (after `addBreakButton()`), install a context menu:

```swift
            menu = makePaneMenu()
```

Add the builder after `addBreakButton()`:

```swift
    private func makePaneMenu() -> NSMenu {
        let menu = NSMenu()
        let breakItem = NSMenuItem(title: "Break Pane into Tab",
                                   action: #selector(breakButtonTapped),
                                   keyEquivalent: "")
        breakItem.target = self
        menu.addItem(breakItem)
        let closeItem = NSMenuItem(title: "Close Pane",
                                   action: #selector(closeButtonTapped),
                                   keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }
```

Note: the terminal view fills the container below the 24 pt gutter and handles its own right-click, so this menu appears only on the pane chrome — as intended by the spec.

- [ ] **Step 2: Build**

Run: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit** (stage; ask Glen before committing)

```bash
git add App/Sources/App/SurfaceNodeView.swift
git commit -m "feat: pane context menu with break/close on the pane chrome"
```

---

### Task 7b: Control CLI `break` verb (added during implementation)

Enables headless/scriptable break and end-to-end live verification (GUI-event
triggers can't be synthesized in a restricted session).

**Files:**
- Modify: `Sources/ZettyCore/CLI/ControlProtocol.swift` (`ControlRequest.breakPane(target:)` + codable)
- Modify: `Sources/ZettyCore/CLI/ControlCLI.swift` (`runBreak`, dispatch, `isControlCommand`, usage)
- Modify: `App/Sources/App/TerminalViewController.swift` (`breakPaneToTab(target:)`)
- Modify: `App/Sources/App/AppDelegate.swift` (`handleOnMain` case)
- Test: `Tests/ZettyCoreTests/ControlProtocolTests.swift` (round-trip)

Behavior: `zetty break [--pane <id> | --cwd <path>]` (default focused) focuses
the target, calls `breakFocusedPaneIntoNewTab()`, prints the moved pane's short
id, errors on a single-pane tab. Verified live: `[2,2] → [2,1,1]` with the moved
id preserved, and the single-pane no-op erroring correctly.

---

### Task 7: Manual verification (live app)

No code. Confirms the five triggers work end-to-end and the live terminal survives the move. Uses the live-relaunch/e2e technique already established for this project.

- [ ] **Step 1: Launch the built app** (rebuild + install to /Applications per the project ritual, or run the DerivedData build directly).

- [ ] **Step 2: In a tab, split into two panes** (⌘D). Run something identifiable in the focused pane (e.g. `htop` or `echo hello; cat`).

- [ ] **Step 3: Break via each trigger, one per fresh split, verifying:**
  - Prefix `Ctrl+B !` → focused pane moves to a new tab inserted right after the current one, which becomes active.
  - Menu **Shell → Break Pane into Tab** (⌥⌘T) → same; item is **disabled** when the tab has a single pane.
  - Command palette → "Break Pane into Tab" runs it.
  - Per-pane button (left of ×) → breaks that specific pane; only visible when the tab has >1 pane.
  - Right-click the pane **gutter** (top strip with the status dot) → menu shows "Break Pane into Tab" / "Close Pane"; right-clicking the **terminal body** still shows ghostty's own behavior.

- [ ] **Step 4: Confirm the live process survived** — the moved pane's program keeps running with intact scrollback (no reconnect flash), and the source tab collapsed to its remaining pane with focus intact.

- [ ] **Step 5: Confirm single-pane no-op** — in a single-pane tab, all triggers do nothing (no empty extra tab created).

---

## Self-Review

**Spec coverage:**
- §Behavior (move, insert-after, no-op, zoom clear) → Task 1 (+ tests) and Task 7.
- §Core → Task 1.
- §Command plumbing → Task 2 (`BindingCommand`/`!`) and Task 3 (dispatch + actions).
- §Trigger surfaces 1–5 → prefix (Task 2/3), menu + palette (Task 4), button (Task 5), context menu (Task 6).
- §Edge cases (single pane, zoom, autosave via `rebuildSurfaceNodeView`) → Tasks 1, 3, 7.
- §Design-rule compliance (fg3 tint, chrome only) → Task 5.
- §Testing → Tasks 1 and 2 carry the unit tests named in the spec.

No gaps.

**Placeholder scan:** none — every code step shows the actual code; every command shows expected output.

**Type consistency:** `breakFocusedPaneIntoNewTab()` (Task 1) is the name used in Tasks 3, 4, 5; `breakPaneIntoTab(_:)` (Task 3) is the selector used in Tasks 4; `breakPane(surfaceID:)` (Task 3) is used in Task 5; `onBreak` closure name is consistent across Tasks 5 and 6; `BindingCommand.breakPane` / `"break-pane"` consistent across Tasks 2 and 3.
