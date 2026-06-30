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

---

## Task 4: Split / close / click-to-focus pane actions

### Manual checks

Run the app:
```bash
open ~/Library/Developer/Xcode/DerivedData/quertty-giuacqmlsqkgkrdadhyyjabydjxb/Build/Products/Debug/quertty.app
```

Or open `quertty.xcworkspace` in Xcode and press ⌘R.

1. **Split Vertically (⌘D)**: Press ⌘D — the window should split into two side-by-side panes. The newly created (right) pane should receive focus (accent border).
2. **Split Horizontally (⇧⌘D)**: With a pane focused, press ⇧⌘D — the focused pane should split top/bottom.
3. **Type in each pane independently**: Click into each terminal and type — input should go to the correct pane only.
4. **Surviving sessions keep their state**: After splitting, type something in the original pane, then close the other pane with ⌘W — the original pane should fill the space and retain all its scrollback/history.
5. **Close pane (⌘W)**: Press ⌘W — the focused pane closes and the sibling expands to fill. If only one pane remains, ⌘W is a no-op (last pane is preserved).
6. **Click switches focus**: In a multi-pane layout, click on a non-focused pane — the accent border should move to the clicked pane and keypresses should go there.
7. **Focus indicator**: The focused pane has a 2-pt accent-coloured border; unfocused panes have a thin separator-coloured border (0.5 pt).

**Status: PENDING USER VERIFICATION**

### Build verification (headless)

```bash
mise exec -- tuist generate && mise exec -- tuist build quertty
```

Result: **Build Succeeded** (confirmed by automated build step).
