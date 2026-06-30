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

---

## Task 5: Tabs — one PaneTree per tab, tab bar, new/close/switch

### Manual checks

Run the app:
```bash
open ~/Library/Developer/Xcode/DerivedData/quertty-giuacqmlsqkgkrdadhyyjabydjxb/Build/Products/Debug/quertty.app
```

Or open `quertty.xcworkspace` in Xcode and press ⌘R.

1. **Tab bar visible**: The window should show a 28-pt tab bar strip above the pane area, with one segment labelled "Tab 1" and a "+" button to its right.
2. **New Tab (⌘T)**: Press ⌘T — a second segment "Tab 2" appears; the pane area resets to a fresh single-pane terminal. Pressing ⌘T again gives "Tab 3".
3. **Split within a tab (⌘D)**: While on Tab 2, press ⌘D to split vertically. Switch to Tab 1 (⌘{) — it should still show its original single pane. Switch back to Tab 2 — the split should still be present.
4. **Live sessions survive tab switch**: Type text in a pane on Tab 1, switch to Tab 2 and back — the text and shell history on Tab 1 must be intact (background sessions are never pruned).
5. **Close Tab (⇧⌘W)**: With Tab 2 active and a split inside it, press ⇧⌘W — Tab 2 disappears, remaining tabs reindex, and the pane area shows the next available tab's layout.
6. **Close Tab no-op on last tab**: With only one tab open, ⇧⌘W must be a no-op (tab stays).
7. **Select Next Tab (⌘})**: Cycles forward through tabs, wrapping from the last back to Tab 1.
8. **Select Previous Tab (⌘{)**: Cycles backward through tabs, wrapping from Tab 1 to the last tab.
9. **Tab bar click**: Click a segment in the tab bar — the pane area should switch to that tab's layout.
10. **Focus indicator**: Within a tab, the focused pane retains its 2-pt accent border; switching tabs restores the correct focus highlight for that tab.

**Status: PENDING USER VERIFICATION**

---

### Build verification (headless)

```bash
mise exec -- tuist generate && mise exec -- tuist build quertty
```

Result: **Build Succeeded** (confirmed by automated build step).
