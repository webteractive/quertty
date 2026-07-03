# Font Settings — Design

**Date:** 2026-07-03 · **Status:** Approved pending user review

Add font family + font size controls to **Settings → Appearance**, driving the
terminal **and** Zetty's chrome uniformly, live, with no relaunch. Prefixed by a
mechanical rename of the Quertty-era theme type names.

## Goals

- Pick a font family and size from Settings; every live terminal pane updates
  at once, and the chrome (tabs, sidebar, status bar, kbd chips) follows.
- Stay ghostty-native: the source of truth is the existing `font-family` /
  `font-size` ghostty directives in `~/.config/zetty/config`. A user who pastes
  their ghostty config gets the same uniform result with no Settings visit.
- No new reserved config keys.

## Non-goals

- Per-pane or per-project fonts.
- Ligature/feature toggles, fallback chains, `font-family-bold` etc. (users can
  still paste those directives; they just aren't surfaced in Settings).
- Reflowing chrome layout metrics (row heights, tab bar height) — the chrome
  scale clamp keeps text fitting inside today's fixed heights.

## Step 0 — Rename QTheme → ZTheme (separate commit)

`QTheme` (157 uses) and `QColorScheme` (30 uses) are Quertty leftovers, all in
the App layer (no package-public API, no test usage). Mechanical rename:

- `QTheme` → `ZTheme`, `QColorScheme` → `ZColorScheme`, across `App/Sources`.
- Docs sweep: `DESIGN.md`, `AGENTS.md`, `CLAUDE.md` (18 mentions).
- Rebuild + run tests. Lands as its own commit so the feature diff stays readable.

## Architecture

Confirmed plumbing (all exists today):

- libghostty-spm's `TerminalConfiguration` has first-class `.fontFamily(String)`
  and `.fontSize(Float)`; Zetty already forwards them as pasted directives via
  `builder.withCustom` (`AppDelegate.makeTerminalConfiguration()`).
- `TerminalController.setTerminalConfiguration` regenerates the ghostty config
  and re-applies it to the live surface — fonts update in place. This is the
  same path ⇧⌘, reload uses (`SurfaceRegistry.reapplyTerminalConfiguration`).
- `AppConfig.rendered()` already persists the ghostty directive block.

### 1. Config layer (`ZettyCore` — pure, tested)

`AppConfig` gains:

- `func ghosttyValue(_ key: String) -> String?` — the **last** directive with
  that key (case-insensitive), matching ghostty's last-wins semantics for
  scalar keys. `nil` when absent.
- `func settingGhostty(key: String, value: String?) -> AppConfig` — returns a
  copy with the **last** matching directive's value replaced in place (earlier
  duplicates removed), or the directive appended when absent. `value: nil`
  removes the directive entirely (= "Default"). Preserves the order of all
  other directives.

### 2. Theme layer (`ZTheme`, App)

Two new static properties, set by `AppDelegate` whenever config is
loaded/reloaded/changed:

- `static var fontFamily: String?` — the effective `font-family`, `nil` =
  default (JetBrains Mono → system mono fallback, unchanged).
- `static var fontScale: CGFloat` — effective `font-size` ÷ 13 (ghostty's
  default), **clamped to 0.85…1.35**. The terminal itself is unclamped; the
  clamp only protects chrome layout.

`monoFont(size:weight:)` becomes: if `fontFamily` is set, resolve that family
via `NSFontManager` (weight-appropriate member, falling back to the family's
regular face); else the existing JetBrains Mono chain. The requested size is
multiplied by `fontScale`. An uninstalled/invalid family falls back to the
default chain (ghostty does its own fallback on the terminal side).

### 3. Settings UI (`SettingsWindowController` → Appearance tab)

Two rows below "Sidebar position":

- **Font** — editable `NSComboBox`. Item 0: `Default (JetBrains Mono)`; then a
  curated candidate list filtered to installed families (SF Mono, Menlo,
  Monaco, JetBrains Mono, Fira Code, Hack, Source Code Pro, IBM Plex Mono,
  Cascadia Code, Iosevka, Geist Mono). Free text accepted — any family name
  ghostty accepts (committed on Enter / focus loss). Selecting Default removes
  the directive.
- **Font size** — `NSTextField` + `NSStepper`, range 8–32, step 1, decimals
  allowed (ghostty's `font-size` is a float). Placeholder/default 13; clearing
  the field removes the directive.

`refreshAppearance()` syncs both from `ghosttyValue("font-family"/"font-size")`.
Two new callbacks follow the existing one-callback-per-control pattern
(`onSelectTheme`, `onSetSidebarPosition`): `onSetFontFamily: ((String?) -> Void)?`
and `onSetFontSize: ((Float?) -> Void)?` — `nil` means "back to default"
(directive removed).

### 4. Apply path (`AppDelegate`)

One handler for both controls:

1. `appConfig = appConfig.settingGhostty(...)` → `saveConfig()` (watcher bounce
   already suppressed).
2. `terminalViewController?.reloadGhosttyConfiguration(makeTerminalConfiguration())`
   — all live panes re-font.
3. Update `ZTheme.fontFamily` / `ZTheme.fontScale` → `terminalViewController?.applyTheme()`
   — chrome rebuilds.

`reloadConfiguration(_:)` (⇧⌘, and the config-file watcher) gains step 3's
`ZTheme` update so hand-edited configs drive chrome too. Settings window
rebuilds via the existing `rebuildAfterThemeChange()`.

## Edge cases

- **Duplicate directives** (pasted config with two `font-size` lines): last
  wins everywhere — `ghosttyValue` reads the last, `settingGhostty` collapses
  duplicates on write, ghostty itself applies last-wins.
- **Invalid family name:** terminal — ghostty falls back to its default;
  chrome — `NSFontManager` resolution fails → default chain. Uniformly "looks
  like default"; no error UI.
- **Out-of-range size typed in config file:** chrome clamps via `fontScale`;
  terminal honors it (ghostty accepts it). Settings stepper enforces 8–32 only
  for values it writes.
- **`font-family` with quotes or trailing spaces:** values are trimmed by the
  parser already; quotes are passed through verbatim (ghostty accepts both).

## Testing

`ZettyCoreTests` (pure):

- `ghosttyValue`: absent → nil; single; duplicates → last wins; key
  case-insensitivity.
- `settingGhostty`: append when absent; replace-in-place preserving order;
  duplicate collapse; nil removes; round-trips through `rendered()` + `parse`.

App layer (`ZTheme.fontScale` clamp, family resolution fallback) is covered by
a small pure helper where practicable; visual verification (live pane update,
chrome scale, combo behavior) is manual — GUI capture is TCC-blocked here.

## Rollout

1. Commit 1: ZTheme/ZColorScheme rename (mechanical).
2. Commit 2: config helpers + tests.
3. Commit 3: ZTheme font state + Settings UI + apply path.
