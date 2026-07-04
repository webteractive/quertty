# Scrollback Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reattached zmx-preserved panes come back with their full scrollback history after quit/relaunch.

**Architecture:** libghostty spawns each pane's command and owns the PTY, so replayed history must arrive as ordinary command output. A generated wrapper script (`~/.zetty/scrollback-restore.sh`) replays `zmx history <session> --vt` into the surface, then `exec`s `zmx attach`. Script contents and command-building are pure in `ZettyCore`; the app layer writes the script idempotently and threads its path into the existing `sessionCommandProvider`. A new reserved config key `restore-scrollback` (default `true`) is the escape hatch.

**Tech Stack:** Swift 6 (swift-testing `@Test`/`#expect`), Tuist-generated Xcode project, zmx 0.6.

**Spec:** `docs/plans/2026-07-04-scrollback-restore-design.md`

## Global Constraints

- `ZettyCore` stays pure — no AppKit imports (Foundation is fine).
- No debug `NSLog`/`print` committed.
- **Commits require Glen's explicit OK — ask once before the first commit; if declined, complete all work and leave commits to him.** Never add `Co-Authored-By` or session links to commit messages. Never push.
- Sources are listed explicitly in the Tuist project: **after adding a new file, run `mise exec -- tuist generate --no-open`** (run `mise exec -- tuist clean` first if generate fails with a bogus "Manifest not found at …/AgentLogos" error).
- Fast test loop for the pure core: `swift test` from the repo root (SPM). Full suite/app build go through Tuist/xcodebuild.
- The user's config key truthy set is `["true", "yes", "on", "1"]` — match `preserve-sessions` exactly.

---

### Task 1: `restore-scrollback` config key

**Files:**
- Modify: `Sources/ZettyCore/Config/AppConfig.swift`
- Test: `Tests/ZettyCoreTests/SessionPersistenceTests.swift` (config keys for session preservation are tested here, next to the `preserve-sessions` test at line ~62)

**Interfaces:**
- Produces: `AppConfig.restoreScrollback: Bool` (public var, default `true`), parsed from `restore-scrollback = <bool>`, rendered by `rendered()`, present in `defaultFileContents`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ZettyCoreTests/SessionPersistenceTests.swift`, after `configParsesPreserveSessions` (~line 70):

```swift
@Test func configParsesRestoreScrollback() {
    #expect(AppConfig.parse("restore-scrollback = false").restoreScrollback == false)
    #expect(AppConfig.parse("restore-scrollback = true").restoreScrollback == true)
    #expect(AppConfig.parse("").restoreScrollback == true)   // default on
    // Reserved: must not leak into the ghostty passthrough.
    #expect(AppConfig.parse("restore-scrollback = false").ghostty.isEmpty)
    // Round-trips through rendered().
    let config = AppConfig(restoreScrollback: false)
    #expect(AppConfig.parse(config.rendered()) == config)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter configParsesRestoreScrollback`
Expected: FAIL — compile error, `AppConfig` has no member `restoreScrollback`.

- [ ] **Step 3: Implement the key in AppConfig**

In `Sources/ZettyCore/Config/AppConfig.swift`:

(a) Property, directly after the `preserveSessions` property (line ~56):

```swift
    /// When true (default), relaunch-reattached preserved panes replay their
    /// full zmx scrollback history into the surface before attaching. Only
    /// meaningful when `preserveSessions` is on and zmx is installed.
    public var restoreScrollback: Bool
```

(b) Init parameter after `preserveSessions: Bool = false,` (line ~86) and assignment after `self.preserveSessions = preserveSessions` (line ~99):

```swift
        restoreScrollback: Bool = true,
```
```swift
        self.restoreScrollback = restoreScrollback
```

(c) Parse case after `case "preserve-sessions":` (line ~147):

```swift
            case "restore-scrollback":
                config.restoreScrollback = ["true", "yes", "on", "1"].contains(value.lowercased())
```

(d) In `rendered()`, extend the preserve-sessions block (line ~229) to:

```swift
        # Keep terminal sessions alive across app quit/relaunch (requires zmx).
        preserve-sessions = \(preserveSessions)

        # Replay preserved panes' scrollback history when relaunch reattaches
        # them (only meaningful with preserve-sessions = true).
        restore-scrollback = \(restoreScrollback)
```

(e) In `defaultFileContents`, extend the preserve-sessions block (line ~295) to:

```swift
    # Keep terminal sessions alive across app quit/relaunch. Requires zmx
    # (brew install neurosnap/tap/zmx); also toggleable in Settings (⌘,).
    preserve-sessions = false

    # Replay preserved panes' scrollback history when relaunch reattaches
    # them (only meaningful with preserve-sessions = true).
    restore-scrollback = true
```

(f) Update the `parse` doc comment (line ~118) that enumerates reserved keys so it reads `… \`preserve-sessions\`, and \`restore-scrollback\` are Zetty's own keys.`

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all PASS (full run, because every existing `rendered()` round-trip test now exercises the new line).

- [ ] **Step 5: Commit (after Glen's OK per Global Constraints)**

```bash
git add Sources/ZettyCore/Config/AppConfig.swift Tests/ZettyCoreTests/SessionPersistenceTests.swift
git commit -m "feat(config): add restore-scrollback key (default on)"
```

---

### Task 2: Restore script contents + attach-command variant

**Files:**
- Modify: `Sources/ZettyCore/Session/SessionPersistence.swift`
- Test: `Tests/ZettyCoreTests/SessionPersistenceTests.swift`

**Interfaces:**
- Consumes: `SessionPersistence.sessionName(for:)` (existing).
- Produces: `SessionPersistence.restoreScriptContents: String` (static let) and `SessionPersistence.attachCommand(zmxPath: String, surfaceID: UUID, restoreScriptPath: String? = nil) -> String`. The default `nil` keeps the existing call site and `attachCommandUsesZmxPathAndName` test compiling unchanged.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ZettyCoreTests/SessionPersistenceTests.swift`, after `attachCommandUsesZmxPathAndName`:

```swift
@Test func attachCommandWithRestoreScriptWrapsAttach() {
    let cmd = SessionPersistence.attachCommand(
        zmxPath: "/opt/homebrew/bin/zmx",
        surfaceID: idA,
        restoreScriptPath: "/Users/g/.zetty/scrollback-restore.sh")
    // Plain space-separated tokens — ghostty's `command` parser can't be
    // relied on for quote grouping, so nothing here may need quoting.
    #expect(cmd == "/bin/sh /Users/g/.zetty/scrollback-restore.sh /opt/homebrew/bin/zmx zetty-abcdef01")
}

@Test func restoreScriptReplaysHistoryThenExecsAttach() {
    let script = SessionPersistence.restoreScriptContents
    #expect(script.hasPrefix("#!/bin/sh"))
    // ZMX_SESSION inherited from a zmx-backed terminal makes `zmx attach`
    // kill that session — the script must strip it for both invocations.
    #expect(script.contains("unset ZMX_SESSION"))
    let history = script.range(of: "\"$1\" history \"$2\" --vt 2>/dev/null")
    let attach = script.range(of: "exec \"$1\" attach \"$2\"")
    #expect(history != nil)
    #expect(attach != nil)
    if let history, let attach {
        #expect(history.lowerBound < attach.lowerBound)   // replay BEFORE attach
    }
}

@Test func restoreScriptInvokesHistoryThenAttachWithoutZmxSession() throws {
    // Behavioral check with a stub zmx: history first, then attach, both with
    // the session name, both with ZMX_SESSION stripped even when inherited.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-restore-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let scriptURL = dir.appendingPathComponent("scrollback-restore.sh")
    try SessionPersistence.restoreScriptContents.write(to: scriptURL, atomically: true, encoding: .utf8)

    let logURL = dir.appendingPathComponent("calls.log")
    let stubURL = dir.appendingPathComponent("zmx")
    try """
    #!/bin/sh
    echo "$1 $2 ${ZMX_SESSION:-none}" >> "\(logURL.path)"
    """.write(to: stubURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubURL.path)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [scriptURL.path, stubURL.path, "zetty-test1234"]
    var env = ProcessInfo.processInfo.environment
    env["ZMX_SESSION"] = "inherited-parent-session"
    process.environment = env
    try process.run()
    process.waitUntilExit()

    let calls = try String(contentsOf: logURL, encoding: .utf8)
    #expect(calls == "history zetty-test1234 none\nattach zetty-test1234 none\n")
    #expect(process.terminationStatus == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter restoreScript`
Expected: FAIL — compile error, no member `restoreScriptContents` / no 3-argument `attachCommand`.

- [ ] **Step 3: Implement in SessionPersistence**

In `Sources/ZettyCore/Session/SessionPersistence.swift`, replace `attachCommand` (lines 25–34) with:

```swift
    /// Contents of the generated scrollback-restore wrapper
    /// (`~/.zetty/scrollback-restore.sh`; the app layer writes it). Replays
    /// the session's full scrollback (`zmx history --vt`, attributes intact)
    /// into the surface as ordinary output, then execs the attach so no
    /// extra shell lingers. `unset ZMX_SESSION` covers the inherited-session
    /// hazard (see `attachCommand`) for both zmx invocations. A missing
    /// session (new pane) prints nothing — stderr is suppressed — and attach
    /// creates it as before.
    public static let restoreScriptContents = """
    #!/bin/sh
    # Zetty scrollback restore (generated; do not edit — rewritten on launch).
    # $1 = zmx path, $2 = session name.
    unset ZMX_SESSION
    "$1" history "$2" --vt 2>/dev/null
    exec "$1" attach "$2"
    """

    /// The ghostty `command` value that runs the pane inside its zmx session.
    /// zmx attach creates the session (running the user's shell) if missing.
    ///
    /// With a `restoreScriptPath`, the pane instead runs the wrapper script,
    /// which replays the session's scrollback history before attaching. The
    /// invocation is plain space-separated tokens — ghostty's `command`
    /// parser can't be relied on for quote grouping, so nothing may need
    /// quoting (paths with spaces are already unsupported by the bare form).
    ///
    /// ZMX_SESSION is unset first (by `env -u` here, by the script there):
    /// when Zetty itself was launched from a zmx-backed terminal (e.g.
    /// Supacode), every pane inherits that variable, and `zmx attach` run
    /// "inside" a session kills it instead of attaching the target (or
    /// errors out if it's already gone).
    public static func attachCommand(
        zmxPath: String,
        surfaceID: UUID,
        restoreScriptPath: String? = nil
    ) -> String {
        let session = sessionName(for: surfaceID)
        guard let script = restoreScriptPath else {
            return "/usr/bin/env -u ZMX_SESSION \(zmxPath) attach \(session)"
        }
        return "/bin/sh \(script) \(zmxPath) \(session)"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all PASS, including the untouched `attachCommandUsesZmxPathAndName` (default `nil` path).

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add Sources/ZettyCore/Session/SessionPersistence.swift Tests/ZettyCoreTests/SessionPersistenceTests.swift
git commit -m "feat(core): scrollback-restore wrapper script + attach-command variant"
```

---

### Task 3: App layer — script installer + wiring

**Files:**
- Create: `App/Sources/App/ScrollbackRestore.swift`
- Modify: `App/Sources/App/AppDelegate.swift:398-407` (`applySessionPreservation`)

**Interfaces:**
- Consumes: `SessionPersistence.restoreScriptContents`, `SessionPersistence.attachCommand(zmxPath:surfaceID:restoreScriptPath:)` (Task 2), `appConfig.restoreScrollback` (Task 1).
- Produces: `ScrollbackRestore.ensureScript() -> String?` — idempotently writes the wrapper to `~/.zetty/scrollback-restore.sh`, returns its path, `nil` on write failure (caller falls back to bare attach).

- [ ] **Step 1: Create the installer**

Create `App/Sources/App/ScrollbackRestore.swift`:

```swift
import Foundation
import ZettyCore

/// Writes the scrollback-restore wrapper script (contents owned by
/// `SessionPersistence.restoreScriptContents`) to
/// `~/.zetty/scrollback-restore.sh` — same generated-helper pattern as the
/// agent hook script in `~/.zetty/hooks/`.
enum ScrollbackRestore {

    static var scriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zetty/scrollback-restore.sh")
    }

    /// Ensures the script exists with the current contents (rewrites on
    /// content drift, e.g. after an app update). Returns its path, or nil
    /// when writing fails — the caller then falls back to the bare attach
    /// command, so the pane still preserves; only the replay is lost.
    static func ensureScript() -> String? {
        let url = scriptURL
        let contents = SessionPersistence.restoreScriptContents
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == contents {
            return url.path
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Thread it through applySessionPreservation**

In `App/Sources/App/AppDelegate.swift`, replace the enabled branch (lines ~400-404):

```swift
        if appConfig.preserveSessions, let zmx = zmxPath {
            let restoreScript = appConfig.restoreScrollback ? ScrollbackRestore.ensureScript() : nil
            tvc.sessionCommandProvider = { id in
                SessionPersistence.attachCommand(
                    zmxPath: zmx, surfaceID: id, restoreScriptPath: restoreScript)
            }
        } else {
```

Also extend the method's doc comment first line to mention the wrapper, e.g. append: `When restore-scrollback is on, panes launch through the scrollback-restore wrapper script instead (replays zmx history, then attaches).`

- [ ] **Step 3: Regenerate the project and build**

```bash
mise exec -- tuist clean
mise exec -- tuist generate --no-open
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **` (confirm the string appears — a deleted xcodeproj from a failed generate can silently reuse a stale build).

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: all PASS.

- [ ] **Step 5: Commit (after Glen's OK)**

```bash
git add App/Sources/App/ScrollbackRestore.swift App/Sources/App/AppDelegate.swift
git commit -m "feat: restore preserved panes' scrollback on relaunch"
```

---

### Task 4: Documentation

**Files:**
- Modify: `README.md` (config table ~line 184; session-persistence feature bullet ~line 27; enable steps ~line 211)
- Modify: `AGENTS.md` (preserve-sessions section, lines 86–105)
- Modify: `CLAUDE.md` (Configuration section, `preserve-sessions` bullet)

**Interfaces:** none (prose only). Key facts to state everywhere: key name `restore-scrollback`, default `true`, only meaningful with `preserve-sessions = true`, mechanism = wrapper script `~/.zetty/scrollback-restore.sh` replaying `zmx history --vt` before attach.

- [ ] **Step 1: README**

In the config-keys table, after the `preserve-sessions` row:

```markdown
| `restore-scrollback` | `true` | Replay preserved panes' scrollback history on relaunch (with `preserve-sessions`) |
```

In the Session persistence feature description, append one sentence: `Relaunch-reattached panes also replay their full scrollback history (colors intact), so scrolling up works as if the app never quit; set restore-scrollback = false to disable.`

- [ ] **Step 2: AGENTS.md**

In the `preserve-sessions` section (after the repaint-nudge bullet, ~line 102), add a bullet:

```markdown
  - **Scrollback restore** — `restore-scrollback` (default true): reattaching
    panes launch through a generated wrapper (`~/.zetty/scrollback-restore.sh`,
    contents in `SessionPersistence.restoreScriptContents`, written idempotently
    by `ScrollbackRestore.ensureScript()`) that replays `zmx history <session>
    --vt` into the surface before exec'ing the attach — full scrollback with
    attributes survives quit/relaunch. Plain-token invocation (`/bin/sh <script>
    <zmx> <session>`) because ghostty's `command` parser can't be relied on for
    quote grouping. Write failure falls back to the bare attach.
```

- [ ] **Step 3: CLAUDE.md**

In the Configuration section's `preserve-sessions` bullet, append: `Companion key restore-scrollback (default true) replays zmx history into reattached panes via a generated wrapper script so scrollback survives relaunch.`

- [ ] **Step 4: Commit (after Glen's OK)**

```bash
git add README.md AGENTS.md CLAUDE.md
git commit -m "docs: document restore-scrollback"
```

---

### Task 5: Build, install, end-to-end verification

**Files:** none (verification only).

**Interfaces:** consumes the installed app + `zetty` CLI.

- [ ] **Step 1: Rebuild and install to /Applications**

The user runs the /Applications copy — after the final commit, rebuild and install (per project practice):

```bash
mise exec -- tuist generate --no-open
xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build
ditto <DerivedData build products path>/zetty.app /Applications/Zetty.app
```

Verify the installed build identity matches HEAD: `defaults read /Applications/Zetty.app/Contents/Info.plist ZettyBuildCommit` equals `git rev-parse --short HEAD`.

- [ ] **Step 2: Pre-flight sanity (no app restart needed)**

```bash
zmx history "$(zmx list --short | head -1)" --vt | head -c 200
```

Expected: real VT data (escape sequences visible) from a live session. The wrapper script itself is written by the app on next launch/config-apply — its behavior is already covered by the stub-zmx unit test in Task 2, so no manual script run is needed here.

- [ ] **Step 3: Live end-to-end (coordinate with Glen — he is dogfooding Zetty right now)**

**Ask Glen before quitting his running app.** Then: generate distinctive scrollback in a pane (e.g. `seq 1 500`), quit Zetty (sessions preserved), relaunch from /Applications, and have Glen scroll up in that pane.

Pass criteria: the pre-quit history (all 500 lines, colors/attributes on colored output) is present above the live screen; a pane with `restore-scrollback = false` set + config reload + relaunch shows the old behavior (empty scrollback); brand-new panes open normally.

- [ ] **Step 4: Record the outcome**

If the attach repaint visibly duplicates the final screenful in scrollback (the spec's known cosmetic unknown), note it in the spec doc as observed behavior and file it as a follow-up — not a blocker.
