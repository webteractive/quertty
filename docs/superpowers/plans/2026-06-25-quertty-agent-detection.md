# quertty AI Agent Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the AI-agent detection engine in `QuerttyCore` — a pluggable agent registry, OS-abstracted foreground-process presence detection, and a deterministic per-session status state machine (running / idle / needs-attention) — all pure Swift and headlessly testable, with no libghostty dependency.

**Architecture:** Everything lives in `QuerttyCore` (pure Swift + Foundation, plus Darwin for the macOS probe behind `#if canImport(Darwin)`). Presence detection is split into a `ForegroundProcessProbe` protocol (mockable in tests) and a Darwin implementation. The status logic is a **pure reducer** `AgentStateMachine.reduce(previous:input:descriptor:)` that takes an explicit `now` timestamp — no wall-clock calls — so every transition is deterministic in tests. Hook-reported status (arriving later via the CLI/socket plan) is an input to the reducer and takes precedence over activity heuristics.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing (via the `apple/swift-testing` package, already wired), Foundation, Darwin (`libproc`) behind `#if canImport(Darwin)`.

## Global Constraints

- **Layer rule:** all code lives in `QuerttyCore` and imports only Swift + Foundation (+ Darwin behind `#if canImport(Darwin)` for the probe). NO UI frameworks, NO libghostty.
- **Determinism:** status logic must NOT call `Date()`/`Date.now`/`DispatchTime.now()`. Time enters only as an explicit `now: TimeInterval` parameter, so tests are reproducible.
- **Agent roster (v1):** `claude`, `codex`, `opencode`, `aider`, `gemini`, `hermes`. Adding an agent must be a data change to the registry, not new code paths.
- **Status states:** exactly `running`, `idle`, `needsAttention`. Presence (which agent) is separate from status (what it's doing); a session with no detected agent has `kind == nil` and `status == nil`.
- **Graceful degradation:** for an agent whose descriptor has `honorsHooks == false`, never emit `needsAttention` from heuristics alone — only `running`/`idle` from activity. `needsAttention` requires an explicit hook event.
- **Testing:** Swift Testing (`import Testing`/`@Test`/`#expect`). A benign `@Test` deprecation warning is the known, accepted Command-Line-Tools artifact — not a defect.
- **Commits:** frequent, one per task minimum. Do not push without the owner's say-so. Use `git -c commit.gpgsign=false commit` if signing errors.

---

### Task 1: AgentKind + AgentDescriptor + AgentRegistry

**Files:**
- Create: `Sources/QuerttyCore/Agents/AgentKind.swift`
- Create: `Sources/QuerttyCore/Agents/AgentDescriptor.swift`
- Create: `Sources/QuerttyCore/Agents/AgentRegistry.swift`
- Create: `Tests/QuerttyCoreTests/AgentRegistryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum AgentKind: String, Codable, Sendable, CaseIterable { case claude, codex, opencode, aider, gemini, hermes }`
  - `struct AgentDescriptor: Sendable, Equatable` — `kind: AgentKind`, `displayName: String`, `binaryNames: [String]`, `honorsHooks: Bool`, `idleAfter: TimeInterval`.
  - `enum AgentRegistry` — `static let all: [AgentDescriptor]`; `static func match(command: String) -> AgentDescriptor?` (resolves a foreground command — possibly a full path like `/opt/homebrew/bin/claude` — to a descriptor by matching the last path component against `binaryNames`, case-insensitively).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/QuerttyCoreTests/AgentRegistryTests.swift
import Testing
@testable import QuerttyCore

@Test func registryCoversAllSixAgents() {
    #expect(Set(AgentRegistry.all.map(\.kind)) == Set(AgentKind.allCases))
}

@Test func matchesBareCommandName() {
    #expect(AgentRegistry.match(command: "claude")?.kind == .claude)
}

@Test func matchesFullPathByLastComponent() {
    #expect(AgentRegistry.match(command: "/opt/homebrew/bin/codex")?.kind == .codex)
}

@Test func matchIsCaseInsensitive() {
    #expect(AgentRegistry.match(command: "OpenCode")?.kind == .opencode)
}

@Test func unknownCommandReturnsNil() {
    #expect(AgentRegistry.match(command: "/bin/zsh") == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentRegistryTests`
Expected: FAIL — `AgentKind`/`AgentRegistry` not found.

- [ ] **Step 3: Implement AgentKind**

```swift
// Sources/QuerttyCore/Agents/AgentKind.swift
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
    case opencode
    case aider
    case gemini
    case hermes
}
```

- [ ] **Step 4: Implement AgentDescriptor**

```swift
// Sources/QuerttyCore/Agents/AgentDescriptor.swift
import Foundation

public struct AgentDescriptor: Sendable, Equatable {
    public let kind: AgentKind
    public let displayName: String
    public let binaryNames: [String]
    public let honorsHooks: Bool
    public let idleAfter: TimeInterval

    public init(
        kind: AgentKind,
        displayName: String,
        binaryNames: [String],
        honorsHooks: Bool,
        idleAfter: TimeInterval
    ) {
        self.kind = kind
        self.displayName = displayName
        self.binaryNames = binaryNames
        self.honorsHooks = honorsHooks
        self.idleAfter = idleAfter
    }
}
```

- [ ] **Step 5: Implement AgentRegistry**

```swift
// Sources/QuerttyCore/Agents/AgentRegistry.swift
import Foundation

public enum AgentRegistry {
    public static let all: [AgentDescriptor] = [
        AgentDescriptor(kind: .claude,   displayName: "Claude Code", binaryNames: ["claude"],   honorsHooks: true,  idleAfter: 5),
        AgentDescriptor(kind: .codex,    displayName: "Codex",       binaryNames: ["codex"],    honorsHooks: false, idleAfter: 5),
        AgentDescriptor(kind: .opencode, displayName: "opencode",    binaryNames: ["opencode"], honorsHooks: false, idleAfter: 5),
        AgentDescriptor(kind: .aider,    displayName: "Aider",       binaryNames: ["aider"],    honorsHooks: false, idleAfter: 5),
        AgentDescriptor(kind: .gemini,   displayName: "Gemini",      binaryNames: ["gemini"],   honorsHooks: false, idleAfter: 5),
        AgentDescriptor(kind: .hermes,   displayName: "hermes",      binaryNames: ["hermes"],   honorsHooks: false, idleAfter: 5),
    ]

    /// Resolves a foreground command (bare name or full path) to a descriptor by
    /// matching the last path component against `binaryNames`, case-insensitively.
    public static func match(command: String) -> AgentDescriptor? {
        let leaf = (command as NSString).lastPathComponent.lowercased()
        guard !leaf.isEmpty else { return nil }
        return all.first { $0.binaryNames.contains { $0.lowercased() == leaf } }
    }
}
```

> `honorsHooks` is `true` only for `claude` in v1 (Claude Code has a documented hook system). The rest are presence-only until their hook support is confirmed — this encodes the graceful-degradation constraint as data.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter AgentRegistryTests`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add Sources/QuerttyCore/Agents Tests/QuerttyCoreTests/AgentRegistryTests.swift
git -c commit.gpgsign=false commit -m "feat(agents): AgentKind, AgentDescriptor, and the v1 AgentRegistry"
```

---

### Task 2: Status state machine (deterministic reducer)

**Files:**
- Create: `Sources/QuerttyCore/Agents/AgentStatus.swift`
- Create: `Sources/QuerttyCore/Agents/AgentStateMachine.swift`
- Create: `Tests/QuerttyCoreTests/AgentStateMachineTests.swift`

**Interfaces:**
- Consumes: `AgentKind`, `AgentDescriptor` (Task 1).
- Produces:
  - `enum AgentStatus: String, Codable, Sendable { case running, idle, needsAttention }`
  - `enum HookEvent: String, Sendable, Equatable { case running, idle, needsAttention }`
  - `struct AgentState: Sendable, Equatable { var kind: AgentKind?; var status: AgentStatus? }` (with a memberwise `init` defaulting both to `nil`).
  - `struct AgentObservation: Sendable { var descriptor: AgentDescriptor?; var lastOutputAt: TimeInterval?; var hookEvent: HookEvent?; var now: TimeInterval }`
  - `enum AgentStateMachine { static func reduce(previous: AgentState, observation: AgentObservation) -> AgentState }`

**Reducer rules (exact):**
1. If `observation.descriptor == nil` → return `AgentState(kind: nil, status: nil)` (no agent present; clears everything).
2. Else `kind = descriptor.kind`. Determine status:
   a. If `hookEvent != nil` → status = the matching `AgentStatus` (running/idle/needsAttention). (Explicit hook wins.)
   b. Else if `previous.status == .needsAttention` AND there is no fresh output since it was raised → status stays `.needsAttention` (sticky). "Fresh output" = `lastOutputAt != nil && lastOutputAt! >= previous-attention threshold`; model simply: stickiness clears when `lastOutputAt` indicates activity within `recentWindow` of `now`.
   c. Else derive from activity: if `lastOutputAt != nil && now - lastOutputAt! <= recentWindow` → `.running`; else if `lastOutputAt == nil || now - lastOutputAt! >= descriptor.idleAfter` → `.idle`; otherwise keep `previous.status ?? .idle`.
3. Graceful degradation: if `descriptor.honorsHooks == false` AND `hookEvent == nil`, status may only be `.running` or `.idle` — never `.needsAttention` (so clear any sticky attention for non-hook agents).

`recentWindow` is a constant `0.75` seconds.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/QuerttyCoreTests/AgentStateMachineTests.swift
import Testing
@testable import QuerttyCore

private let claude = AgentRegistry.all.first { $0.kind == .claude }!   // honorsHooks: true, idleAfter: 5
private let codex  = AgentRegistry.all.first { $0.kind == .codex }!    // honorsHooks: false, idleAfter: 5

private func reduce(
    prev: AgentState = .init(),
    descriptor: AgentDescriptor?,
    lastOutputAt: TimeInterval? = nil,
    hook: HookEvent? = nil,
    now: TimeInterval
) -> AgentState {
    AgentStateMachine.reduce(
        previous: prev,
        observation: AgentObservation(descriptor: descriptor, lastOutputAt: lastOutputAt, hookEvent: hook, now: now)
    )
}

@Test func noDescriptorClearsState() {
    let prev = AgentState(kind: .claude, status: .running)
    let s = reduce(prev: prev, descriptor: nil, now: 100)
    #expect(s == AgentState(kind: nil, status: nil))
}

@Test func recentOutputIsRunning() {
    let s = reduce(descriptor: codex, lastOutputAt: 99.5, now: 100)  // 0.5s ago <= 0.75 window
    #expect(s == AgentState(kind: .codex, status: .running))
}

@Test func silenceBeyondIdleAfterIsIdle() {
    let s = reduce(descriptor: codex, lastOutputAt: 90, now: 100)    // 10s ago >= idleAfter 5
    #expect(s == AgentState(kind: .codex, status: .idle))
}

@Test func hookEventWinsOverActivity() {
    let s = reduce(descriptor: claude, lastOutputAt: 99.9, hook: .needsAttention, now: 100)
    #expect(s == AgentState(kind: .claude, status: .needsAttention))
}

@Test func nonHookAgentNeverGetsAttentionFromHeuristics() {
    // codex.honorsHooks == false; prior needsAttention must not stick without a hook.
    let prev = AgentState(kind: .codex, status: .needsAttention)
    let s = reduce(prev: prev, descriptor: codex, lastOutputAt: 90, now: 100)
    #expect(s.status == .idle)
}

@Test func attentionIsStickyForHookAgentUntilFreshOutput() {
    let prev = AgentState(kind: .claude, status: .needsAttention)
    // No fresh output (last output 10s ago): stays needsAttention.
    let held = reduce(prev: prev, descriptor: claude, lastOutputAt: 90, now: 100)
    #expect(held.status == .needsAttention)
    // Fresh output within window clears stickiness → running.
    let cleared = reduce(prev: prev, descriptor: claude, lastOutputAt: 99.9, now: 100)
    #expect(cleared.status == .running)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentStateMachineTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement AgentStatus + supporting types**

```swift
// Sources/QuerttyCore/Agents/AgentStatus.swift
import Foundation

public enum AgentStatus: String, Codable, Sendable {
    case running
    case idle
    case needsAttention
}

public enum HookEvent: String, Sendable, Equatable {
    case running
    case idle
    case needsAttention
}

public struct AgentState: Sendable, Equatable {
    public var kind: AgentKind?
    public var status: AgentStatus?

    public init(kind: AgentKind? = nil, status: AgentStatus? = nil) {
        self.kind = kind
        self.status = status
    }
}

public struct AgentObservation: Sendable {
    public var descriptor: AgentDescriptor?
    public var lastOutputAt: TimeInterval?
    public var hookEvent: HookEvent?
    public var now: TimeInterval

    public init(descriptor: AgentDescriptor?, lastOutputAt: TimeInterval?, hookEvent: HookEvent?, now: TimeInterval) {
        self.descriptor = descriptor
        self.lastOutputAt = lastOutputAt
        self.hookEvent = hookEvent
        self.now = now
    }
}
```

- [ ] **Step 4: Implement the reducer**

```swift
// Sources/QuerttyCore/Agents/AgentStateMachine.swift
import Foundation

public enum AgentStateMachine {
    /// Output more recent than this many seconds counts as active ("running").
    static let recentWindow: TimeInterval = 0.75

    public static func reduce(previous: AgentState, observation o: AgentObservation) -> AgentState {
        // Rule 1: no agent present clears everything.
        guard let descriptor = o.descriptor else {
            return AgentState(kind: nil, status: nil)
        }
        let kind = descriptor.kind

        // Rule 2a: an explicit hook event wins.
        if let hook = o.hookEvent {
            return AgentState(kind: kind, status: hook.asStatus)
        }

        let hasRecentOutput: Bool = {
            guard let last = o.lastOutputAt else { return false }
            return o.now - last <= recentWindow
        }()
        let isSilentBeyondIdle: Bool = {
            guard let last = o.lastOutputAt else { return true }
            return o.now - last >= descriptor.idleAfter
        }()

        // Rule 3: non-hook agents can never be needsAttention from heuristics.
        if descriptor.honorsHooks {
            // Rule 2b: attention is sticky until fresh output arrives.
            if previous.status == .needsAttention, !hasRecentOutput {
                return AgentState(kind: kind, status: .needsAttention)
            }
        }

        // Rule 2c: derive from activity.
        let status: AgentStatus
        if hasRecentOutput {
            status = .running
        } else if isSilentBeyondIdle {
            status = .idle
        } else {
            // Between recentWindow and idleAfter: hold previous non-attention status, default idle.
            let prior = previous.status
            status = (prior == .running || prior == .idle) ? prior! : .idle
        }
        return AgentState(kind: kind, status: status)
    }
}

private extension HookEvent {
    var asStatus: AgentStatus {
        switch self {
        case .running: return .running
        case .idle: return .idle
        case .needsAttention: return .needsAttention
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AgentStateMachineTests`
Expected: PASS, 6 tests.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS (foundation + Task 1 + Task 2 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/QuerttyCore/Agents Tests/QuerttyCoreTests/AgentStateMachineTests.swift
git -c commit.gpgsign=false commit -m "feat(agents): deterministic status state machine (running/idle/needsAttention)"
```

---

### Task 3: Foreground-process probe (protocol + Darwin impl + coordinator)

**Files:**
- Create: `Sources/QuerttyCore/Agents/ForegroundProcessProbe.swift`
- Create: `Sources/QuerttyCore/Agents/DarwinForegroundProcessProbe.swift`
- Create: `Sources/QuerttyCore/Agents/AgentDetector.swift`
- Create: `Tests/QuerttyCoreTests/AgentDetectorTests.swift`

**Interfaces:**
- Consumes: `AgentRegistry` (Task 1), `AgentState`/`AgentObservation`/`AgentStateMachine`/`HookEvent` (Task 2).
- Produces:
  - `protocol ForegroundProcessProbe: Sendable { func foregroundCommand(forPTY fd: Int32) -> String? }`
  - `struct DarwinForegroundProcessProbe: ForegroundProcessProbe` (real macOS impl behind `#if canImport(Darwin)`; uses `tcgetpgrp` + `proc_pidpath`).
  - `final class AgentDetector` — holds a `ForegroundProcessProbe` and per-session `AgentState`; method `update(session: UUID, ptyFD: Int32, lastOutputAt: TimeInterval?, hookEvent: HookEvent?, now: TimeInterval) -> AgentState` that probes the command, matches a descriptor, runs the reducer, stores and returns the new state. `func state(for session: UUID) -> AgentState`.

> The Darwin probe cannot be unit-tested headlessly (it needs a live PTY); it is kept tiny. All detector logic is tested via a mock probe.

- [ ] **Step 1: Write the failing tests (using a mock probe)**

```swift
// Tests/QuerttyCoreTests/AgentDetectorTests.swift
import Testing
import Foundation
@testable import QuerttyCore

private struct MockProbe: ForegroundProcessProbe {
    let command: String?
    func foregroundCommand(forPTY fd: Int32) -> String? { command }
}

private let s1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

@Test func detectorReportsPresenceFromProbe() {
    let detector = AgentDetector(probe: MockProbe(command: "/usr/bin/claude"))
    let state = detector.update(session: s1, ptyFD: 3, lastOutputAt: 99.9, hookEvent: nil, now: 100)
    #expect(state.kind == .claude)
    #expect(state.status == .running)
}

@Test func detectorClearsWhenNoAgentForeground() {
    let detector = AgentDetector(probe: MockProbe(command: "/bin/zsh"))
    let state = detector.update(session: s1, ptyFD: 3, lastOutputAt: 99.9, hookEvent: nil, now: 100)
    #expect(state.kind == nil)
    #expect(state.status == nil)
}

@Test func detectorRemembersPerSessionStateForStickiness() {
    let detector = AgentDetector(probe: MockProbe(command: "claude"))
    _ = detector.update(session: s1, ptyFD: 3, lastOutputAt: 50, hookEvent: .needsAttention, now: 60)
    #expect(detector.state(for: s1).status == .needsAttention)
    // No fresh output → attention sticks (claude honorsHooks).
    let held = detector.update(session: s1, ptyFD: 3, lastOutputAt: 50, hookEvent: nil, now: 100)
    #expect(held.status == .needsAttention)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentDetectorTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement the probe protocol**

```swift
// Sources/QuerttyCore/Agents/ForegroundProcessProbe.swift
public protocol ForegroundProcessProbe: Sendable {
    /// The command (path or name) of the foreground process-group leader on the
    /// given PTY file descriptor, or nil if it can't be determined.
    func foregroundCommand(forPTY fd: Int32) -> String?
}
```

- [ ] **Step 4: Implement the Darwin probe**

```swift
// Sources/QuerttyCore/Agents/DarwinForegroundProcessProbe.swift
#if canImport(Darwin)
import Darwin

public struct DarwinForegroundProcessProbe: ForegroundProcessProbe {
    public init() {}

    public func foregroundCommand(forPTY fd: Int32) -> String? {
        let pgid = tcgetpgrp(fd)
        guard pgid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
        let len = proc_pidpath(pgid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }
}
#endif
```

- [ ] **Step 5: Implement the detector**

```swift
// Sources/QuerttyCore/Agents/AgentDetector.swift
import Foundation

public final class AgentDetector {
    private let probe: ForegroundProcessProbe
    private var states: [UUID: AgentState] = [:]

    public init(probe: ForegroundProcessProbe) {
        self.probe = probe
    }

    public func state(for session: UUID) -> AgentState {
        states[session] ?? AgentState()
    }

    @discardableResult
    public func update(
        session: UUID,
        ptyFD: Int32,
        lastOutputAt: TimeInterval?,
        hookEvent: HookEvent?,
        now: TimeInterval
    ) -> AgentState {
        let command = probe.foregroundCommand(forPTY: ptyFD)
        let descriptor = command.flatMap(AgentRegistry.match(command:))
        let observation = AgentObservation(
            descriptor: descriptor,
            lastOutputAt: lastOutputAt,
            hookEvent: hookEvent,
            now: now
        )
        let next = AgentStateMachine.reduce(previous: state(for: session), observation: observation)
        states[session] = next
        return next
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter AgentDetectorTests`
Expected: PASS, 3 tests.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: PASS (all suites green).

- [ ] **Step 8: Commit**

```bash
git add Sources/QuerttyCore/Agents Tests/QuerttyCoreTests/AgentDetectorTests.swift
git -c commit.gpgsign=false commit -m "feat(agents): ForegroundProcessProbe protocol + Darwin impl + AgentDetector coordinator"
```

---

## Self-Review

**Spec coverage:**
- Pluggable agent registry (6 agents, data-driven) → Task 1. ✓
- Presence detection via foreground process group, OS-abstracted + mockable → Task 3. ✓
- Deterministic status state machine (running/idle/needsAttention) with injected time → Task 2. ✓
- Hook precedence + graceful degradation (no heuristic attention for non-hook agents) → Task 2 (rules 2a, 3) with tests. ✓
- Per-session state retention for stickiness → Task 3 (`AgentDetector.states`). ✓
- **Deferred (other plans):** the PTY output-activity timestamp source and the polling/scheduling loop that calls `AgentDetector.update` (belongs to the app/PTY-supervision layer); the hook-event ingestion transport (the CLI/socket plan feeds `HookEvent`); the sidebar badge UX + project roll-up (UI plan).

**Placeholder scan:** No placeholders. The Darwin probe is the only OS-coupled code and is intentionally untested headlessly (documented); all logic is exercised through the mock probe and the pure reducer.

**Type consistency:** `AgentKind`, `AgentDescriptor` (`kind`/`displayName`/`binaryNames`/`honorsHooks`/`idleAfter`), `AgentRegistry.match(command:)`, `AgentStatus`, `HookEvent`, `AgentState(kind:status:)`, `AgentObservation(descriptor:lastOutputAt:hookEvent:now:)`, `AgentStateMachine.reduce(previous:observation:)`, `ForegroundProcessProbe.foregroundCommand(forPTY:)`, `AgentDetector.update(session:ptyFD:lastOutputAt:hookEvent:now:)`/`state(for:)` — consistent across tasks and tests. ✓
