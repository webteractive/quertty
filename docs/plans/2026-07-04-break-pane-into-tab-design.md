# Break Pane into Tab — Design

**Date:** 2026-07-04 · **Status:** Proposed

Take the focused pane out of its current tab's split layout and move it into a
**new tab, inserted right after the current one**, which becomes active. This is
tmux's `break-pane`. The inverse (`join-pane` / merging a tab back into a split)
is deliberately **out of scope**.

## Why it's clean in this codebase

Live terminals are keyed by `Surface.id` in `SurfaceRegistry`, and
`rebuildSurfaceNodeView()` prunes the registry to the **union of all surface IDs
across all projects' all tabs**. So moving a pane's `Surface` leaf from one
`PaneTree` into a brand-new `PaneTree` in the same `TabList` **re-parents the
live PTY without tearing it down**: the surface UUID is still in the prune
union, so the ghostty surface, scrollback, and zmx session all survive the move
untouched. No reconnect, no scrollback loss.

The move itself is a pure-core mutation on `TabList`; every trigger funnels
through the existing `rebuildAndFocus()` → `rebuildSurfaceNodeView()` path, which
already autosaves `workspace.json`.

## Behavior

- Move the **focused** pane of the active tab into a new single-pane tab
  inserted at `activeIndex + 1`; the new tab becomes active and its pane keeps
  focus.
- The source tab collapses the now-orphaned split to the sibling (existing
  `Layout.close` collapse logic); source focus moves to a remaining pane.
- **No-op when the active tab has only one pane** — it is already its own tab.
- If the broken-out pane was the source tab's zoomed pane, the new tab is a
  plain single pane (unzoomed) and the source tab's zoom is cleared. Both fall
  out of routing the removal through `PaneTree.closeFocused()`, which already
  fixes source focus and clears source zoom.

## Core (pure, `ZettyCore`)

One new method on `TabList` (`Sources/ZettyCore/Model/TabList.swift`):

```swift
/// Move the active tab's focused pane into a new single-pane tab inserted
/// right after the current tab, which becomes active. The moved Surface keeps
/// its identity (id/workingDir/command/lastTitle) so the live terminal is
/// re-parented, not recreated. No-op (returns false) when the active tab has
/// one pane or has no focused surface.
@discardableResult
public func breakFocusedPaneIntoNewTab() -> Bool
```

Implementation sketch:

1. Guard: `activeTree.layout.surfaces.count > 1` and there is a
   `focusedSurfaceID`.
2. Read the focused `Surface` value from `activeTree.layout.surfaces`.
3. Remove it from the active tree via `activeTree.closeFocused()` (reuses the
   existing collapse + source-focus + source-zoom-clear semantics).
4. Build `PaneTree(layout: Layout(root: .leaf(surface)), focusedSurfaceID: surface.id)`.
5. Insert at `activeIndex + 1`; set `activeIndex` to that slot.

No new `Layout` primitive is needed — `surfaces.first(where:)` reads the
`Surface`, `closeFocused()` removes it. Because the same `Surface` value (same
`id`) is placed into the new tree, the registry entry survives the next prune.

## Command plumbing

- New `BindingCommand.breakPane`
  (`Sources/ZettyCore/Keybindings/BindingCommand.swift`), config name
  `break-pane`, added to `namesByCommand`.
- Default prefix bind in `defaultPrefixTable`: **`!`** (tmux `break-pane`).
  Fully remappable via `bind = <chord> break-pane`.
- Dispatch in `KeyInterceptor.perform(binding:interceptor:)`
  (`App/Sources/App/KeyInterceptor.swift`): `case .breakPane: breakPaneIntoTab(nil)`.
- New action in `PaneActions`
  (`App/Sources/App/PaneActions.swift`):

  ```swift
  @objc func breakPaneIntoTab(_ sender: Any?) {
      guard workspace.activeTabList.breakFocusedPaneIntoNewTab() else { return }
      rebuildAndFocus()
  }
  ```

## Trigger surfaces (all five)

1. **Prefix key** — `Ctrl+B !` (above).
2. **App menu** — "Break Pane into Tab" in the Shell menu, placed after
   "Close Pane" / "Close Tab" (`App/Sources/App/AppDelegate.swift`, ~line 1001).
   Key equivalent **⌥⌘T** (`t`, `[.command, .option]`) — free today (`⌥⌘` +
   arrows are the resize bindings; `⌘T` is New Tab). Disabled via
   `validateMenuItem` when the active tab has ≤ 1 pane.
3. **Command palette** — entry in `buildCommands()`
   (`App/Sources/App/TerminalViewController.swift`, ~line 1011, next to
   "Close Pane"): glyph `↗`, label "Break Pane into Tab", kbd `⌥⌘T`, action
   `breakPaneIntoTab(nil)`.
4. **Pane button** — a sibling to the `×` in `LeafContainerView`
   (`App/Sources/App/SurfaceNodeView.swift`), shown only when `showsClose` is
   true (i.e. > 1 pane), placed **just left of** the `×`. SF Symbol
   `arrow.up.forward.square` (arrow leaving a box = "pop out"; fallback `↗`), `contentTintColor = fg3`,
   tooltip "Break pane into tab". A new `onBreak: ((UUID) -> Void)?` closure is
   threaded `SurfaceNodeView` → `RatioSplitView` → `LeafContainerView`,
   mirroring the existing `onClose` plumbing exactly. Wired in
   `rebuildSurfaceNodeView()` as
   `onBreak: { [weak self] id in self?.breakPane(surfaceID: id) }`, where
   `breakPane(surfaceID:)` focuses that surface then calls the core method
   (mirroring `closePane(surfaceID:)`).
5. **Pane context menu** — right-click on the pane **chrome gutter** (the 24 pt
   strip in `LeafContainerView` holding the status dot and buttons) shows a
   small `NSMenu` with "Break Pane into Tab" and "Close Pane". Attached to
   `LeafContainerView.menu` so it does **not** fight ghostty's terminal-body
   right-click (paste / selection), which continues to own the terminal area.
   The "Break" item is present only when the pane is closable (> 1 pane).
6. **Control CLI** (added during implementation) — `zetty break [--pane <id> |
   --cwd <path>]` (default target: the focused pane) mirrors `split`/`new-tab`,
   prints the moved pane's short id, and errors when the pane is the only one in
   its tab. This makes the feature scriptable/agent-driveable and was the path
   used to verify the move end-to-end in the live app (GUI-event triggers can't
   be synthesized headlessly). Request `ControlRequest.breakPane(target:)` →
   `TerminalViewController.breakPaneToTab(target:)`.

## Design-rule compliance

- Button uses `ZTheme.current.fg3Color` for tint (rule 1 — no hardcoded
  colors), matching the existing `×` button.
- Button/menu are chrome; no new greys or accents introduced (rules 3–4).
- All UI reads through existing tokens; no shadows added (rule 9).

## Testing

- **`TabListTests`** (new cases):
  - break moves the focused surface (same `id`) into a new tab at
    `activeIndex + 1`, which becomes active;
  - the source tab collapses to the sibling and its focus lands on a remaining
    surface;
  - no-op (returns false) on a single-pane tab and when there is no focus;
  - breaking a zoomed pane clears source zoom and yields an unzoomed new tab;
  - tab count grows by exactly one; other tabs' trees are unchanged.
- **`BindingCommand`** round-trip: `break-pane` ⇄ `.breakPane`, and it appears
  in `defaultPrefixTable` under `!`.

## Out of scope

- `join-pane` / merging a tab into another tab's split (needs a target-picker
  UX; separate spec if wanted later).
- Breaking a pane into a **new window** (Zetty is single-window today).
- Moving a whole subtree (a nested split) into a tab — only the single focused
  leaf moves; break again to peel off more.
