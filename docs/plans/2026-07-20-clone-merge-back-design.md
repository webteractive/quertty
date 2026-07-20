# Clone merge-back — instruction + automated merge

**Date:** 2026-07-20
**Status:** Approved design

## Problem

A project clone is an APFS copy-on-write fork whose `.git` is a full copy of the
source — it carries the source's `main` (and the same `origin` config), and
Zetty puts the clone's work on its own branch `<name>` via `git switch -c
<name>`. Users trying to get clone work back into the source hit two traps:

1. They commit onto `main` in the clone and try to push — producing two
   divergent `main`s (and worse, the clone shares the source's `origin`).
2. When the repo has **no origin remote**, "commit and push" has nowhere to go
   at all.

The current `CloneWarningBanner` states the *what* ("commit and push, or merge
back into the source branch") but not the *how*, and there is no in-app action
to actually integrate the work.

## Goals

- Teach the safe, branch-based integration path in-app and in docs.
- Provide a safe automated "Merge into Source" action for the common case.
- Handle non-git clones cleanly (they can't merge at all).

## Non-goals

- Resolving merge conflicts automatically.
- Copying files back for non-git clones.
- Removing the clone as part of merging (merge ≠ remove).

## Design

### 1. Pure logic — `Sources/ZettyCore/Clone/CloneSupport.swift` (unit-tested)

- **Instruction text:** `mergeGuide(branch:clonePath:sourcePath:defaultBranch:)`
  returns structured steps for both integration paths:
  - **With origin (PR):** `git push -u origin <branch>` in the clone, then open a
    PR against the source's default branch.
  - **No origin (local merge):**
    ```
    # in the SOURCE repo
    git fetch <clonePath> <branch>
    git switch <defaultBranch>
    git merge <branch>
    ```
- **Merge arg builders (run via `git -C <dir>` in the app layer):**
  - `sourceStatusArgs` → `["status", "--porcelain"]`
  - `currentBranchArgs` → `["rev-parse", "--abbrev-ref", "HEAD"]`
  - `isGitWorkTreeArgs` → `["rev-parse", "--is-inside-work-tree"]`
  - `mergeFetchArgs(clonePath:)` → `["fetch", clonePath, "HEAD"]` — fetch the
    clone's **actual current HEAD** into `FETCH_HEAD` (no named refspec), so it
    works whether the clone is on `<name>` or fell back to `main`.
  - `mergeArgs` → `["merge", "--no-edit", "FETCH_HEAD"]`
  - `mergeAbortArgs` → `["merge", "--abort"]`
- **Readiness classifier** `MergeReadiness`:
  - `.notGit` — clone is not a git work tree
  - `.nothingToMerge` — no committed work beyond the source
  - `.cloneDirty` — clone has uncommitted changes (only commits merge)
  - `.sourceDirty` — source working tree is dirty (refuse; merge touches it)
  - `.ready(fastForward: Bool)`
  Derived from the probes + existing `CloneWorkState`.

### 2. Process IO — `App/Sources/App/CloneRunner.swift` (off-main)

`merge(...)`:
1. Probe: is the clone a git work tree? → `.notGit` refusal.
2. Probe source `status --porcelain` + current branch; refuse on `.sourceDirty`.
3. Refuse on `.cloneDirty` ("commit in the clone first") / `.nothingToMerge`.
4. `git -C source fetch <clonePath> HEAD` → `git -C source merge --no-edit FETCH_HEAD`.
5. **On conflict:** `git -C source merge --abort`, report the conflicting files.
   Never leave the source repo mid-merge.

The clone's current branch is probed (in the clone) only for display/messaging.
Runs on a background/socket queue like the copy, so the UI never blocks. Returns
a structured outcome (merged fast-forward / merged with commit / refused-reason /
conflict-with-files).

### 3. Instruction UI — `App/Sources/App/CloneWarningBanner.swift`

- Trailing accent-text button **"How do I merge this back?"** (`ZTheme` accent,
  mono font per the terminal-adjacent rule). Banner stays one line at 26pt.
- Click opens an `NSPopover` (following the `IconPicker` popover pattern) hosting
  a compact `CloneMergeGuideView`, filled with **this clone's real branch and
  source path** from `mergeGuide(...)`.
- **Non-git clone:** hide the button entirely — there is no version control to
  merge; the base data-loss warning already applies (more strongly).

Banner construction in `TerminalViewController.rebuildSurfaceNodeView()` gains
the clone's branch name (derived: component of `name` after the source prefix =
`ClonePlan.branchName`), clone path (`activeProject.rootPath`), and source path
(`activeProject.cloneSource`).

### 4. Automated action surfaces

- **GUI:** clone-row context menu **"Merge into Source…"** + a button in the
  popover. Confirmation shows target branch + ff-vs-merge-commit + warnings;
  success/refusal alert afterward. Hidden/disabled for non-git clones.
- **CLI:** `zetty merge-clone <name>` as a **slow verb** — routed in
  `AppDelegate.startControlSocket` alongside `clone`/`capture`/`quit` (plan on
  main, run fetch+merge off-main, report on main); `handleOnMain`'s default
  errors if it lands there. New `ControlCommand.mergeClone` in
  `ControlProtocol`, help + parse in `ControlCLI`. Returns a clear error for
  non-git clones and for every refusal reason.
- **Guards:** refuse if the source project is hibernated; requires committed,
  non-dirty clone work; source working tree must be clean.

### 5. Conflict policy — abort-on-conflict

Automate the clean/fast-forward case; on conflict `git merge --abort` and report,
handing off to the instruction popover / PR path. Never leaves the source repo in
a MERGING state. Matches the app's conservative posture (fetch-back aborts before
deleting; delete guards; "nothing lost on a bad fetch").

### 6. Docs

- `README.md` clone section gains **"Bringing clone work back"**: the
  branch-based rule ("don't push the clone's `main`"), PR-with-origin,
  local-merge-without, the **Merge into Source** action, and `zetty
  merge-clone`.
- Mirror any clone-section note added to `CLAUDE.md` into `AGENTS.md`
  byte-identically.

## Testing

- `CloneSupportTests`: arg builders, `MergeReadiness` matrix (incl. `.notGit`),
  `mergeGuide` assembly (origin + no-origin paths).
- App-layer merge run (fast-forward, merge-commit, conflict abort,
  dirty-source refusal, non-git refusal) verified manually / via the
  live-relaunch technique since it is process IO; GUI verification is user-side
  per the TCC-denied constraint.

## Edge cases

- **Non-git clone (source never git, or `git switch -c` failed):** button
  hidden, action/CLI refuse with a clear message.
- **Branch setup failed → clone on `main`:** the `fetch HEAD` approach merges it
  regardless — this is the divergent-`main` scenario, now handled.
- **Source already has a local branch named `<name>`:** avoided entirely by
  fetching into `FETCH_HEAD` rather than a named refspec.
- **Non-CoW full-copy clones:** unaffected — still real git repos.
