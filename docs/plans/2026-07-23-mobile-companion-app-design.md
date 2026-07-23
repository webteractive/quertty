# Mobile companion app — design notes

**Date:** 2026-07-23
**Status:** Exploratory (idea capture — not approved, revisit later)

## Idea

A **Zetty client on the phone** — not a remote control, but an actual mobile
client that connects to a running Zetty instance and renders its live terminals
natively. Open the app, pick which running Zetty to attach to (you may have
several across devices), and see what's running with the *actual* output
rendered **via libghostty on the phone**. Multiple devices connect to the same
instance and each loads what's currently running.

The distinguishing choice: **stream the pty byte stream, not pixels.** libghostty
on the phone is a VT renderer fed bytes — lightweight (text, not a VNC pixel
feed), reflows to the phone screen, stays crisp at any size. This is
mosh/ssh-shaped, not screen-sharing-shaped.

## Why the architecture already anticipates this

The pure-core discipline pays off directly. Reusable on iOS **unchanged**:

- `ZettyCore` model (`PaneTree`, `TabList`, `WorkspaceModel`, `SurfaceNode`).
- `ControlWire` / `ControlCLI` — the line-JSON protocol *is already the
  client-server protocol*. `status --json` is literally "here's the workspace
  tree to render on the phone."
- Keybinding engine, clone/session pure logic, `ZTheme` token values.

Session substrate already exists too: **zmx**. A phone "opening a pane" is
essentially a remote `zmx attach` — stream history + live output down,
keystrokes up. The pty stream is already preserved and replayable per pane.

## Reuse vs. rewrite boundary

| Reuse as-is | Rewrite for iOS | Build new |
|---|---|---|
| `ZettyCore` (models, `ControlWire`, keybindings, clone/session logic) | Entire App layer — it's **AppKit** (`AppDelegate`, `TerminalViewController`, `SidebarView`, `TabBarView`). iOS is UIKit/SwiftUI. | Network transport (Mac side: serve control + proxy zmx streams) |
| libghostty *(if iOS slices exist — see Gate 1)* | `ZettyGhostty` bridge — `SurfaceRegistry` hosts libghostty in an `NSView`; needs a `UIView` host | Client side: attach-over-network, reconnect handling |
| DESIGN.md tokens (`ZTheme` mostly pure values) | Touch interaction model — no `Ctrl+B` prefix on a phone; needs a soft input bar for splits/focus/copy-mode | Pairing / auth flow (which instance, which device) |

Honest framing: this is a **second app** that shares the pure core + terminal
engine, not a port of the existing one. The visible AppKit UI is ~all of the
app and none of it survives.

## The two gates (validate before designing anything else)

**Gate 1 — Does libghostty run on iOS?** Make-or-break, and unconfirmed.
In favor: cross-platform embedding is libghostty's reason to exist, its renderer
is Metal (iOS has it), and Ghostty-on-iOS demos exist. Against: the prebuilt
`libghostty-spm` almost certainly ships **macOS slices only** today. Spike: a
bare iOS app that embeds libghostty and renders one hardcoded pty stream. Pure
go/no-go — everything depends on it. (See `docs/ghostty-embedding-api.md`.)

**Gate 2 — Transport doesn't exist yet.** The control socket is a **local Unix
socket** and zmx is **local**; nothing crosses the network today. Spike: a
Mac-side bridge exposing `status --json` and proxying one `zmx attach` over a
WebSocket on the LAN / Tailscale; prove a laptop browser can render a live pane.
This also de-risks "connect between multiple devices" — that's just N clients on
the bridge.

Both spikes need **zero relay** (same LAN or Tailscale). Don't let the relay
question block proving the core idea works at all.

## Connectivity & relay (later tier)

"Relay" conflates two separable jobs — keep them separate:

1. **Rendezvous / signaling** (thin, cheap, you operate it): "phone, here's which
   Mac is running Zetty and how to reach it." Low-bandwidth, occasional. Hard to
   avoid if you want zero-config "works anywhere."
2. **Data plane** (fat, sensitive, latency-critical): carries the live pty
   stream. Do **not** route through a server you operate as the default path —
   infra tax, trust (terminal I/O = credentials/keystrokes), and added latency
   on an interactive shell.

Architecture that holds up (WebRTC / Tailscale shape):

```
thin rendezvous server (yours)  → pairing + signaling only
         ↓
attempt DIRECT p2p for the data (LAN, or NAT hole-punch)
         ↓ (only if that fails)
relay fallback for the data plane
         ↑
END-TO-END ENCRYPTED throughout — any relay is a blind pipe
```

Non-negotiables:

- **E2E encrypt the data plane.** Pairing establishes keys directly between the
  two devices; the relay (yours or self-hosted) never sees plaintext. For
  terminal I/O this is foundational, not polish.
- **Direct-first, relay-as-fallback.** A pure "everything through us" relay is
  the ~10–20% fallback tier, not the foundation.

Shortcut for v1: lean on **Tailscale** — NAT traversal + stable address +
WireGuard E2E + direct-with-relay-fallback, **zero infra for us**. Cost is user
friction ("install Tailscale") — fine for a dev-tool audience, punts the whole
relay build.

## Business model (proposed)

Paid app + **self-hostable relay** — the Tailscale shape (frictionless hosted
convenience you charge for; self-hostable for the principled minority). Fits a
dev audience that values the escape hatch. Three traps decide whether
self-hosting is real or fiction:

1. **The relay is a dumb, open, single-binary pipe from day one.** Ship
   `zetty-relay` (one binary / one container); the **hosted offering is just us
   running that same binary.** If our infra and a self-hoster's aren't the
   identical artifact, self-hosting rots into vaporware you can't retrofit.
   Forces E2E + a clean protocol as a side effect.
2. **The app fully works without ever touching our servers.** LAN + Tailscale +
   self-hosted relay all work with zero calls to our infra. Hosted relay is a
   *convenience upgrade*, never the on-switch — also protects users from our
   outages.
3. **"Spin their own" must be trivial** — one container, one config, stateless
   if possible (ephemeral pairing state, no user DB). If it needs a DB + three
   services, nobody self-hosts.

Packaging — decouple the two chargeable things:

| What | Pricing | Why |
|---|---|---|
| **The app** (Mac server + mobile client) | One-time, or "buy the Mac app, mobile included" | Durable revenue. Never gate the app *working* behind a sub. |
| **Hosted relay** | Optional recurring add-on | Ongoing infra cost to us → recurring is honest. Self-hosters skip it. |

Honest caution: **recurring relay revenue only exists for users whose phone and
Mac can't reach each other directly.** Many devs already run Tailscale or share
a LAN and will never need it. Durable revenue is the app purchase; hosted relay
is convenience margin on top.

App Store reality (iOS):

- Model is **allowed** — many apps connect to self-hosted / BYO servers (Blink,
  Prompt, self-hosted-* clients). "Connects to your own relay" won't be rejected.
- Apple's cut: 15–30% on the app and on any in-app relay subscription. Price with
  the haircut baked in, or sell the relay sub via web (more permissible
  post-2024, still fiddly).
- **Companion dodges the store economics**: anchor the purchase on the Mac app
  (distributed by us, outside any store cut) and ship the iOS client as a free
  companion to a paid desktop license.

## Sequencing

1. Gate 1 spike — libghostty on iOS (go/no-go).
2. Gate 2 spike — Mac-side bridge + `zmx attach` proxy over LAN/Tailscale;
   render a live pane in a laptop browser.
3. Only if both green: design the iOS client UI, then the pairing + E2E
   handshake against `ControlWire`, then the thin rendezvous server. A fat data
   relay is the last tier, if ever.

## Non-goals (for now)

- No relay/rendezvous infra until the two gates are green.
- No pixel/screen streaming — pty byte stream + on-device libghostty only.
- Not a port of the AppKit app; a new client sharing the pure core.
