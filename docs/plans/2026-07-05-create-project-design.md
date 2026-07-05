# Create Project — Design

**Date:** 2026-07-05 · **Status:** Approved

Add a **Create Project** action that makes a new folder on disk and then adds it
as a project — reusing the entire existing add-project path. Alongside it, the
existing "Add Project" (pick an *existing* directory) is relabelled **"Add
Existing Project…"**, and the sidebar "+" becomes a small menu offering both.

## Why it's small

The only genuinely new work is: choose a parent directory + type a name,
`mkdir`, and optionally `git init`. Everything after the folder exists is the
current flow: `addProjectFromURL(url:name:)` already spawns the pane, applies a
resolved layout template, updates the tab bar/sidebar, and autosaves.

## Decisions (settled with Glen)

| Question | Decision |
|---|---|
| Where the folder is created | Pick a **parent** directory, **type a name** → `<parent>/<name>` |
| Create vs Add in the UI | Sidebar "+" becomes a menu: **New Project…** + **Add Existing Project…** (rename) |
| git init | **Optional checkbox**, default **off** |
| CLI | Add `zetty new-project <path> [--name] [--git]` |
| Create dialog | A single `NSOpenPanel` with an **accessory view** (name field + git checkbox), not a separate sheet |

## Architecture

- **Pure core (`ZettyCore`)** — a small, unit-tested `NewProjectRequest` helper:
  trims/validates the name (non-empty, no path separators, not `.`/`..`, no
  leading dot), composes the target path from parent + name, and reports why a
  name is invalid. No filesystem access — keeps the guardrail (`ZettyCore` has
  no AppKit and no FS side-effects).
- **Filesystem side-effects live in the app layer** — `FileManager
  .createDirectory` + (when checked) a `git init` shell-out via `Process`. Both
  funnel into the existing `addProjectFromURL(url:name:)`.
- **CLI / protocol** — a new `ControlCommand.newProject(path:name:gitInit:)`.
  The `mkdir` / `git init` happen **app-side** in the socket handler (the same
  code path the GUI uses), so `zetty new-project` and the button behave
  identically.

### The rename

The current "Add Project" (pick existing dir) becomes **"Add Existing
Project…"** everywhere its label appears — the sidebar menu, the Project menu,
and the command palette. The `@objc addProject(_:)` selector and the
`add-project` CLI verb **keep their names** (only user-facing strings change) to
avoid churning the menu wiring and to keep any existing `zetty add-project`
scripts working.

## UX — the create dialog

Clicking the sidebar "+" opens a small `NSMenu`:

- **New Project…**
- **Add Existing Project…**

**New Project…** presents a single `NSOpenPanel`:

- `canChooseDirectories = true`, `canChooseFiles = false`,
  `canCreateDirectories = true` — the selected directory is the **parent**.
- `accessoryView` holds a **Name** `NSTextField` and an **Initialize git
  repository** `NSButton` (checkbox, default off).
- Prompt button reads **Create**.
- The name field shows an inline error and disables Create when the name is
  invalid or a folder of that name already exists in the selected parent.

Both menu items and the panel follow the existing programmatic-AppKit + `ZTheme`
idiom; no hardcoded colors.

## Data flow

**GUI:** "+" → menu → New Project… → accessory panel → on Create:

1. `NewProjectRequest.validate` (pure) → target path.
2. `FileManager.createDirectory(withIntermediateDirectories: false)` at target.
3. If checked: `git init` (via `Process`) in the new folder.
4. `addProjectFromURL(url:name:)` — existing spawn / template / autosave path.

**CLI:** `zetty new-project <path> [--name <name>] [--git]` → `ControlCommand
.newProject` over the socket → same app-side handler → prints the first pane id.

## Error handling (surfaced, never silent)

- **Empty / invalid name** → inline error in the panel; Create disabled.
- **Target already exists** → inline error "A folder named X already exists
  here." v1 blocks rather than silently adding the existing folder.
- **`createDirectory` fails** (permissions, read-only parent) → `NSAlert` with
  the underlying error; the project is **not** added.
- **`git init` fails** → **non-fatal**: the project is still added, followed by
  a warning alert ("Folder created and added, but git init failed: …"). We
  don't discard a good folder over a git hiccup.
- **CLI** mirrors the *hard* errors: exit 1 with a stderr message on already-
  exists / mkdir failures; exit 0 printing the first pane id on success. A soft
  `git init` failure is **non-fatal and silent** on the CLI path (the socket
  response is just the pane id — the folder is still created, exit 0). The GUI
  surfaces the git warning via an alert. Widening the response protocol for this
  rare case isn't worth it in v1.

## Layout templates

`addProjectFromURL` already applies a resolved layout template. A brand-new
folder is empty, so a template's relative cwds may point at subdirectories that
don't exist yet; behavior is unchanged from add (ghostty falls back to the
project root for a missing cwd). No special handling in v1.

## Testing

- **`ZettyCore` (swift-testing):**
  - `NewProjectRequest` validation matrix — empty, whitespace-only, `/`, `..`,
    leading dot, valid — plus target-path composition.
  - `ControlProtocol` encode/decode round-trip for `newProject`.
  - `ControlCLI` arg parsing: `new-project <path> [--name] [--git]`, and the
    missing-path error.
- **App layer** (not unit-tested — AppKit + FS): verified live on the running
  app — create a project, confirm the folder on disk, the pane spawns, a
  template applies, and the git checkbox produces a `.git`. GUI verification
  respects the session's TCC limits (driven headlessly where possible, or
  confirmed by Glen).

## Non-goals

- Choosing / scaffolding from project templates (language starters, etc.).
- `git init` options (remote, initial commit, branch name).
- A configurable default "projects home" (the folder-location decision was
  pick-parent-then-name, not a fixed root).
