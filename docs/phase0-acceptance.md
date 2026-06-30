# Phase 0 Acceptance Checklist

Spike: one libghostty surface (`TerminalView` / `.exec` backend) in the quertty app window.

## How to run

```bash
cd ~/AI/quertty
/opt/homebrew/bin/mise exec -- tuist generate
open quertty.xcworkspace
```

Select the **quertty** scheme, press **Run** (⌘R).

## Acceptance items

- [ ] **Shell prompt renders** — Window opens showing a live shell prompt rendered by libghostty (`TerminalView` with `.exec` backend spawning `$SHELL`).
  - Result: PENDING USER VERIFICATION

- [ ] **Typing works** — Typing appears in the terminal; `ls`, `vim`, `exit` all work correctly.
  - Result: PENDING USER VERIFICATION

- [ ] **Resize reflows** — Resizing the window causes the terminal to reflow (PTY size updates via `fitToSize()` → `synchronizeMetrics()` → `setSize`).
  - Result: PENDING USER VERIFICATION

- [ ] **Focus on click** — Clicking the terminal pane gives it keyboard focus (`makeFirstResponder` called in `viewDidAppear`; `acceptsFirstResponder` returns `true` on `AppTerminalView`).
  - Result: PENDING USER VERIFICATION

- [ ] **Kitty graphics** — A Kitty-graphics image renders (e.g. `kitten icat <some-image>`), confirming full libghostty rendering (not just text output).
  - Result: PENDING USER VERIFICATION

## Notes

- The `.exec` backend spawns the user's `$SHELL` in a real PTY. No sandbox shell is used.
- `TerminalController()` handles `ghostty_init` internally; `Ghostty.initializeRuntime()` is **not** called in the app path to avoid a double-init.
- Any FAIL here blocks Phase 1 multi-pane work.
