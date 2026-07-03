# Watch: libghostty-vt + pure Swift Metal renderer (GhosttyRender)

**Status:** Not released — watching upstream. Do not implement yet.
**Decision:** Yes, Zetty can and likely should adopt this once it ships. This doc
records what it is, why it matters to us, and the criteria for pulling the trigger.

## What was announced

Mitchell Hashimoto (2026-07-02, X/@mitchellh):

> I've got a pure Swift Metal renderer and bindings for libghostty-vt. This will
> enable libghostty users to basically drop a package into their Swift/Xcode
> projects and get a full blown terminal (emulation, rendering, or both).
> Coming soon…
>
> This … is a pure Swift Apple-ecosystem (macOS and iOS) only package for
> libghostty embedders.

The demo window is titled **"GhosttyRender Example"** — a Metal renderer demo
wrapped in SwiftUI over a `RenderView`. Demo log lines reveal design details:

- glyph atlas with steady-state **0 B/frame** uploads
- retained frame model: **only dirty rows re-plan**
- grid re-fits and content reflows on window resize
- **render-only** demo: "keystrokes go nowhere" — input encoding is not part of
  the renderer
- "cursor blink is view policy; the renderer never blinks" — blink/caret policy
  belongs to the embedding view layer
- styles/underlines/truecolor/wide chars (CJK), emoji, box drawing all shown;
  explicitly "no 2027" (mode 2027 grapheme clustering not in the demo)

Context: Ghostty on macOS has always been Metal-rendered, but through a
complicated generic renderer + font subsystem designed to span any graphics/font
API. This package is a from-scratch, Apple-only (macOS + iOS), pure Swift take.

## Upstream state (as of 2026-07-03)

- **libghostty-vt** — zero-dependency (not even libc) terminal-emulation library:
  VT sequence parsing + terminal state (cursor, styles, wrapping, scrollback).
  Zig API usable today; C API was the active work per the
  ["Libghostty Is Coming"](https://mitchellh.com/writing/libghostty-is-coming)
  post, with a tagged release targeted "within six months" of that post. Public
  alpha: core battle-tested (it *is* Ghostty's core), API still moving.
- **Swift bindings + Metal renderer** — the new piece from the tweet. Not yet
  public; no repo under `ghostty-org` as of today (checked: ghostty, ghostling,
  website, discord-bot, zig-gobject, .github). No package name confirmed beyond
  the "GhosttyRender" demo title.
- Long-term libghostty roadmap explicitly includes input handling / keyboard
  encoding and full "Swift frameworks that handle the entire terminal view" as
  *separate* future pieces.

## What Zetty uses today

Full libghostty via [`Lakr233/libghostty-spm`](https://swiftpackageregistry.com/Lakr233/libghostty-spm)
(GhosttyKit XCFramework). That gives us the **whole surface**: PTY spawn,
emulation, GPU rendering, font discovery/shaping, keyboard/mouse encoding
(kitty keyboard protocol), kitty graphics, shell integration injection, URL
detection, selection, and ghostty config-directive handling
(`TerminalConfiguration` — our "paste your ghostty config" feature rides on
this). PRD risk #1 is that this embedding API is not frozen for third parties.

## Why this matters to Zetty

Adopting vt + GhosttyRender would flip the architecture from "embed Ghostty's
app-shaped surface" to "Zetty owns the terminal, Ghostty provides the engine":

1. **Kills PRD risk #1.** libghostty-vt is a *designed-for-embedders* API with a
   release discipline, vs. the unstable full-libghostty embedding seam we pin
   and pray on.
2. **We'd own terminal state.** Direct access to the grid/scrollback makes
   several roadmap items dramatically easier or newly possible:
   - **copy mode** (Phase 2): keyboard-driven selection over state we can read,
     instead of fighting an opaque surface
   - **full scrollback restore** (Phase 3): serialize/restore vt state ourselves
   - richer `zetty capture` / agent integration (structured reads, not scrapes)
3. **PTY seam already built.** `PTYBackend` (`DirectPTY` / zmx-backed detached
   sessions) was designed in v1 exactly so the terminal stack behind it could
   change without rework.
4. **Pure Swift, Apple-native.** Simpler dependency story than a pinned Zig
   XCFramework; iOS door opens (not a goal, but free optionality).

## What we'd lose / have to re-own (the honest column)

The tweet's package is emulation + rendering. Full libghostty currently gives us,
for free, things that would become **our problem**:

- **Input encoding** — keyboard→escape-sequence encoding incl. kitty keyboard
  protocol, IME, mouse reporting. The demo is explicitly render-only. Upstream
  lists input handling as a future libghostty lib; until it exists we'd write it.
- **Ghostty config directives** — the "paste your ghostty config" feature
  (fonts, colors, everything in `TerminalConfiguration`) is full-libghostty
  semantics. We'd need to map the directives we care about onto the renderer's
  API ourselves, or scope the feature down.
- **Shell integration** injection, **URL detection**, **kitty graphics**,
  ligature-quality font shaping — unknown coverage until the package is public.
- **Maturity**: brand-new renderer vs. Ghostty's shipped one.

## Adoption criteria (re-evaluate when it ships)

Adopt (behind the existing seams, one pane type at a time) when **all** hold:

1. Package is public with a tagged release and a stated API-stability posture.
2. Input story exists — either an upstream input-encoding lib or the package
   demonstrates a complete interactive terminal (not render-only).
3. Feature-parity checklist passes for what Zetty ships today: truecolor,
   underline styles, wide chars/emoji, selection, scrollback, font
   family/size control (our Settings ties into this), kitty keyboard protocol.
   Kitty *graphics* is nice-to-have, may lag.
4. We can map our reserved-key + ghostty-directive config model onto it without
   breaking existing user configs (or we consciously scope the passthrough
   feature and document the diff).

**Migration shape when we go:** add a second surface implementation alongside
GhosttyKit (the `SurfaceRegistry` / `PTYBackend` seams stay), dogfood it behind
a config flag (`experimental-renderer = ghostty-render` or similar), cut over
when parity holds, then drop libghostty-spm.

## Watch list

- https://github.com/ghostty-org — new repo appearing (name unknown; demo says "GhosttyRender")
- https://mitchellh.com/writing — announcement post
- [awesome-libghostty](https://github.com/Uzaaft/awesome-libghostty) — community tracker
- Ghostty Discord #libghostty
