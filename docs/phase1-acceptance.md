# Phase 1 Acceptance Checklist

## Task 3: Recursive split rendering — SurfaceNodeView + PaneTree

### Manual check

To visually verify that two panes render side-by-side and are both interactive:

1. Open `App/Sources/App/TerminalViewController.swift`.
2. Change the `debugTwoPane` flag to `true`:
   ```swift
   private static let debugTwoPane: Bool = true
   ```
3. Regenerate and run the app:
   ```bash
   mise exec -- tuist generate
   open quertty.xcworkspace
   # Build & Run in Xcode (Cmd+R)
   ```
4. Observe that the window shows **two terminal panes side by side** (vertical split, 50/50).
5. Click into each pane and type — both should accept keyboard input and run a live shell.
6. Resize the window — both panes should resize proportionally.
7. Drag the divider — the split ratio should adjust interactively.
8. Revert `debugTwoPane` back to `false` before committing.

**Status: PENDING USER VERIFICATION**

---

### Build verification (headless)

Two-pane split compiles cleanly via:

```bash
mise exec -- tuist generate && mise exec -- tuist build quertty
```

Result: **Build Succeeded** (confirmed by automated build step).
