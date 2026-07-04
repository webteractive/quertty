# Scrollback restore for preserved sessions — design (2026-07-04)

**Status:** approved · **Owner:** glen@more.dev
**Roadmap:** PRD Phase 3 "full scrollback restore"
(`docs/plans/2026-06-25-quertty-prd.md` §9).

## Problem

With `preserve-sessions = true`, panes survive quit/relaunch inside zmx
sessions — but `zmx attach` replays only the current screen. A relaunched pane
comes back with empty scrollback above the fold, so "quit and pick up where
you left off" loses the history.

The data already exists: zmx keeps a full per-session scrollback log, and
`zmx history <name> --vt` emits it with escape sequences (colors/attributes)
intact. The `zetty capture` CLI already uses the plain-text variant. The gap
is purely that nothing replays the log into the surface on reattach.

## Decisions

- **Scope: zmx-preserved panes only.** Without zmx there is no surviving
  history, and libghostty's embedding API offers no way to dump its scrollback
  at quit. Non-preserved panes are unchanged.
- **Full-history replay, no cap.** ghostty's own `scrollback-limit` bounds
  retained memory and its parser is fast. Add a tail cap later only if
  dogfooding shows slow attaches.
- **On by default, with an escape hatch.** New reserved config key
  `restore-scrollback = true|false` (default `true`) — a kill switch in case
  replay misbehaves with some TUI or a giant log.

## Approach (chosen: shell-wrapper replay via generated script)

libghostty spawns the pane command and owns the PTY, so replayed history must
arrive as ordinary command output. The pane command reaches libghostty as its
`command` config value, whose argument-quoting behavior we can't rely on
(prebuilt xcframework, parser unknown) — so instead of an inline
`sh -c '<compound command>'` (which needs quote grouping), Zetty generates a
tiny wrapper script at `~/.zetty/scrollback-restore.sh` and invokes it with
plain space-separated tokens:

```
/bin/sh ~/.zetty/scrollback-restore.sh <zmxPath> zetty-<id>
```

The script (contents owned by `ZettyCore`, written idempotently by the app
layer, same pattern as the hook helper in `~/.zetty/hooks/`):

```sh
#!/bin/sh
# Zetty scrollback restore (generated; do not edit — rewritten on launch).
# $1 = zmx path, $2 = session name.
unset ZMX_SESSION
"$1" history "$2" --vt 2>/dev/null
exec "$1" attach "$2"
```

- `unset ZMX_SESSION` replaces the `env -u` wrapper for both zmx invocations
  (the existing inherited-session hazard; see AGENTS.md).
- History streams into the surface first, populating ghostty scrollback with
  attributes intact (`--vt`), then `exec` replaces the shell with the attach —
  no extra process lingers.
- New panes are unaffected in practice: no session yet → history prints
  nothing (stderr suppressed), attach creates the session as before.
- If the script can't be written (disk error), the pane falls back to the
  bare attach command — preserved session works, scrollback just isn't
  restored.
- The existing reattach resize-nudge and title-persistence behavior stay as-is.

### Alternatives rejected

- **App-side injection** — the embedding API only writes to PTY *input*
  (keystrokes, wrong direction); feeding output would require patching
  GhosttyKit and maintaining a fork. Fallback only if replay ordering proves
  uncontrollable.
- **Snapshot at quit, replay at launch** — duplicates data zmx already holds,
  adds a stale-snapshot window while Zetty is closed, and still needs the same
  replay mechanism.

## Components

- **`ZettyCore/Session/SessionPersistence.swift`** — gains
  `restoreScriptContents` (the script text above) and
  `attachCommand(zmxPath:surfaceID:restoreScriptPath:)`; a non-nil script path
  emits the wrapper invocation, nil keeps the current bare attach.
- **`ZettyCore/Config/AppConfig.swift`** — parse `restore-scrollback`
  (default `true`, same truthy-value set as `preserve-sessions`), serialize it
  back, include it in the seeded default config with a comment.
- **`App/Sources/App/ScrollbackRestore.swift`** (new) — idempotently writes
  `restoreScriptContents` to `~/.zetty/scrollback-restore.sh` and returns its
  path (nil on write failure → bare-attach fallback).
- **`App/Sources/App/AppDelegate.swift`** — `applySessionPreservation`
  installs the script when `appConfig.restoreScrollback` is true and threads
  the path into the `sessionCommandProvider` closure. The key only has effect
  when `preserve-sessions = true` and zmx is installed.
- **Docs** — README, AGENTS.md, and CLAUDE.md config sections gain the key.

## Error handling / edge cases

- **Missing session** (first launch of a pane): `zmx history` fails; stderr is
  suppressed, replay is a silent no-op, attach creates the session.
- **Giant logs**: accepted by decision (full replay). ghostty's
  `scrollback-limit` bounds retained memory.
- **Alt-screen TUIs**: history replay ends in whatever mode the log ended;
  attach's screen replay then repaints current reality, and the existing
  repaint nudge covers TUI redraws.
- **Known cosmetic unknown**: whether attach's screen replay duplicates the
  final screenful in scrollback or overwrites in place. The implementation
  plan starts with a manual spike to observe this; if duplication is ugly,
  mitigation is a follow-up, not a blocker.

## Testing

- **Unit (`ZettyCore`)**: `attachCommand` with restore on/off — exact string,
  quoting, `env -u` placement; `AppConfig` parse/serialize round-trip for
  `restore-scrollback`; default-on when the key is absent.
- **Manual acceptance**: quit Zetty with a scrolled pane, relaunch, scroll up —
  history present, colors intact. Set `restore-scrollback = false`, reload
  config (⇧⌘,), relaunch — old behavior (empty scrollback). New pane with
  restore enabled behaves identically to today.
