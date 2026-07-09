# CLI structural verbs stop stealing focus

**Date:** 2026-07-09
**Status:** Approved (design)

## Problem

When an agent orchestrates Zetty over the control socket (`zetty` CLI) while the
user is typing in a pane, the active **project** and keyboard focus jump away
mid-keystroke. Several structural verbs force a project/tab/first-responder
switch as a side effect of creating something.

Root cause (verified in the app layer):

- `new-tab` (`openNewTab`) calls `selectProject` when `--project` is given and
  focuses the newly created tab.
- `split` (`splitPane`) and `break` (`breakPaneToTab`) call `focusPane(at:)`
  first, which switches project + tab + first responder.
- `scratch` (`newScratchTerminal`) switches to the new scratch project.

By contrast, `add-project`/`new-project` are already background-by-default with an
opt-in `focus` flag, and `close` deliberately restores the user's prior project
selection. The four verbs above are the inconsistency.

## Goal

No `zetty` CLI command changes the **active (visible) project** or the **first
responder** unless the caller passes `--focus`. Matches the existing
`add-project`/`new-project` pattern and `close`'s restore-selection behavior.

Non-goals (explicitly dropped after scoping with the user):

- **Eager background spawn.** libghostty only creates a surface/pty in
  `TerminalSurfaceCoordinator.rebuildIfReady()`, gated on `isAttached()` (view in
  a window) + `hasValidViewSize`. A detached/off-screen pane never spawns. A
  hidden in-window warm-up mount would work but is timing-sensitive and can't be
  verified headlessly — not worth it for this need.
- **Input buffering for `send`.** A background-created pane spawns lazily on
  first view (parity with `add-project`), so `zetty send` to a brand-new
  background pane still returns "focus its tab first" until it is viewed. Agents
  that want create-and-run pass `--focus`.

## Behavior

| Verb | Today | New default (no `--focus`) | `--focus` |
|---|---|---|---|
| `new-tab [--project X]` | switches to X, focuses new tab | creates the tab in X's (or the active project's) tab list; the user's view stays put | switch to X + focus the new tab (today's behavior) |
| `split` | focuses target's project/tab, then splits | splits the target pane in its own tree; the user's view stays put | focus the new split pane |
| `break` | focuses target, breaks it out | breaks the pane into a new tab in its project; the user's view stays put | switch to the broken-out tab |
| `scratch` | switches to the new scratch terminal | creates it in the Scratch section, unfocused | switch to it (today's behavior) |

Unchanged: `focus` (explicit by definition), `send`, `capture`, `status`,
`reload`, `close`, `quit`, `hibernate`/`wake`, `add-project`, `new-project`,
`remove-project`, `scratch-clear`.

### Same-project layout updates

When the mutated project *is* the one currently on screen (e.g. `new-tab` with no
`--project`, or `split`/`break` of a visible pane), the sidebar and tab bar
refresh so the new node is visible, and a same-tree `split` re-renders the
layout — but the **first responder stays on the pane the user was typing in**.
The new tab/pane is created without being selected/focused.

## Implementation

Wire protocol (`ControlProtocol.swift`): add a `focus: Bool` (default false) to
the `newTab`, `split`, `breakPane`, and `scratch` requests, encoded/decoded like
the existing `addProject.focus`. CLI arg parsing (`ControlCLI`) accepts
`--focus` on those four verbs; `--help` grammar + agent notes updated.

App layer (`TerminalViewController`): give each verb a background path that
mutates the target model objects **directly**, without selecting them:

- `new-tab`: `targetProject.tabList.newTab()` on the resolved project's tab list
  (no `selectProject`). Refresh tab bar/sidebar; rebuild the surface node view
  only when the target is the active project, preserving the current first
  responder. With `--focus`, keep today's select+focus path.
- `split`: resolve the target pane's tree; set the tree's model focus to the
  target (`PaneTree.focus`, model-only), `splitFocused(...)`, then restore the
  tree's focus to the original pane before any rebuild so focus doesn't move.
  With `--focus`, `focusPane(at:)` + focus the new pane as today.
- `break`: focus the target tree's pane in-model, `breakFocusedPaneIntoNewTab()`
  on its tab list without selecting the new tab. With `--focus`, select it.
- `scratch`: a `newScratchTerminal(focus:)` variant that adds the scratch project
  without `onActiveProjectChanged`/`makeFirstResponder` when background.

Follows the precedent already set by `closePane` (operate on a non-active
project, restore the user's selection). Pure-model operations already exist:
`TabList.newTab`, `PaneTree.splitFocused`, `PaneTree.focus`,
`TabList.breakFocusedPaneIntoNewTab`, `WorkspaceModel.addScratchProject`.

The interactive keyboard/menu/palette paths (`newTab(_:)`, `splitVertical`,
`breakPane`, `⌃⌘N` scratch) are untouched — they still focus, because that is
the expected interactive behavior. Only the CLI `Result`-returning entry points
change their default.

## Testing

- App-target tests asserting, after a background `new-tab`/`split`/`scratch`,
  that `workspace.activeIndex` and the focused surface id are **unchanged**, and
  that the new tab/pane exists in the target model.
- Symmetric tests with `--focus` asserting the active project / focus **did**
  move.
- Manual runtime check (app layer, GUI): type in project A, run
  `zetty split --cwd <path in B>` from another pane, confirm A keeps focus and
  the caret; then `zetty new-tab --project B --focus` and confirm it switches.

## Docs

- `README.md`: document `--focus` on `new-tab`/`split`/`break`/`scratch` and the
  new no-focus-by-default behavior in the Control CLI section.
- `CLAUDE.md` + `AGENTS.md` (byte-identical): update the Control CLI command
  list to note the background-by-default + `--focus` opt-in for these verbs.
- `zetty --help` grammar + agent notes.
