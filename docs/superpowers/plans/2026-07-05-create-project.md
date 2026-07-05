# Create Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`docs/plans/2026-07-05-create-project-design.md`](../../plans/2026-07-05-create-project-design.md) — source of truth for *what/why*. This plan is the *how/order*.

**Goal:** Add a "Create Project" action that makes a new folder on disk (optionally `git init`) and adds it as a project, reusing the existing add path; relabel the existing "Add Project" to "Add Existing Project…" and put both behind the sidebar "+" menu.

**Architecture:** A pure, unit-tested `NewProjectRequest` (name validation + `<parent>/<name>` composition) lives in `ZettyCore`. Filesystem side-effects (`mkdir`, `git init`) live in the app layer and funnel into the existing `addProjectFromURL`/`addProject(path:name:)`. A new `ControlCommand.newProject` mirrors `addProject` so the CLI and GUI share one app-side code path.

**Tech Stack:** Swift, AppKit (App target), swift-testing (`import Testing`) for `ZettyCore`, Tuist-generated Xcode project, libghostty via `SurfaceRegistry`.

## Global Constraints

- **Keep `ZettyCore` pure** — no AppKit, no filesystem side-effects in `Sources/ZettyCore/**`. `NewProjectRequest` uses only Foundation string/path APIs.
- **Never hardcode a color** — any new UI reads `ZTheme.current.<token>Color`.
- **Fonts follow content** — terminal-adjacent chrome uses `ZTheme.monoFont`; standard controls (the create panel's labels/fields) use the system font.
- **No debug `NSLog`/`print`** in committed code.
- **Commits require Glen's approval** — each "Commit" step means *stage + ask Glen before committing*.
- **New source file added** (`NewProjectRequest.swift` + its test) → run `mise exec -- tuist generate --no-open` before the first build that compiles it. If a bogus "Manifest not found …/AgentLogos" error appears, run `mise exec -- tuist clean` first.
- **Run `ZettyCore` tests** with `mise exec -- tuist test`. Build the app with `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`.
- **Keep selectors + CLI verbs stable:** the `@objc addProject(_:)` selector and the `add-project` CLI command keep their names — only user-facing labels change to "Add Existing Project…".
- **New menu shortcut:** "New Project…" = **⇧⌘N** (`n` + `[.command, .shift]`); `n`/⇧⌘N are free today. "Add Existing Project…" keeps **⌘O**.

---

### Task 1: `NewProjectRequest` (pure core)

**Files:**
- Create: `Sources/ZettyCore/Model/NewProjectRequest.swift`
- Test: `Tests/ZettyCoreTests/NewProjectRequestTests.swift`

**Interfaces:**
- Produces:
  - `public struct NewProjectRequest: Equatable, Sendable` with `init(parentPath: String, name: String)`, `var name: String` (trimmed), `func targetPath() throws -> String`, `static func validate(name: String) throws`.
  - `public enum NewProjectRequest.ValidationError: Error, Equatable, LocalizedError` — cases `emptyName`, `containsSeparator`, `reservedName`, `leadingDot`, each with an `errorDescription`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ZettyCoreTests/NewProjectRequestTests.swift
import Testing
import Foundation
@testable import ZettyCore

@Test func newProjectRejectsEmptyAndWhitespaceNames() {
    #expect(throws: NewProjectRequest.ValidationError.emptyName) {
        try NewProjectRequest.validate(name: "")
    }
    #expect(throws: NewProjectRequest.ValidationError.emptyName) {
        try NewProjectRequest.validate(name: "   ")
    }
}

@Test func newProjectRejectsSeparatorsAndReservedAndHidden() {
    #expect(throws: NewProjectRequest.ValidationError.containsSeparator) {
        try NewProjectRequest.validate(name: "a/b")
    }
    #expect(throws: NewProjectRequest.ValidationError.reservedName) {
        try NewProjectRequest.validate(name: ".")
    }
    #expect(throws: NewProjectRequest.ValidationError.reservedName) {
        try NewProjectRequest.validate(name: "..")
    }
    #expect(throws: NewProjectRequest.ValidationError.leadingDot) {
        try NewProjectRequest.validate(name: ".hidden")
    }
}

@Test func newProjectComposesAndTrimsTargetPath() throws {
    let request = NewProjectRequest(parentPath: "/Users/x/code", name: "  my-proj  ")
    #expect(request.name == "my-proj")
    #expect(try request.targetPath() == "/Users/x/code/my-proj")
}

@Test func newProjectTargetPathThrowsOnInvalidName() {
    #expect(throws: NewProjectRequest.ValidationError.emptyName) {
        try NewProjectRequest(parentPath: "/Users/x", name: " ").targetPath()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: FAIL — `NewProjectRequest` is undefined (compile error). (First add the file via `tuist generate` if the test target won't compile the new test file; the failure to observe is the missing type.)

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ZettyCore/Model/NewProjectRequest.swift
import Foundation

/// Pure, filesystem-free validation + path composition for creating a new
/// project folder. The app/CLI layers perform the actual mkdir / git init.
public struct NewProjectRequest: Equatable, Sendable {
    public let parentPath: String
    public let rawName: String

    public init(parentPath: String, name: String) {
        self.parentPath = parentPath
        self.rawName = name
    }

    /// The folder name, trimmed of surrounding whitespace.
    public var name: String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case emptyName
        case containsSeparator
        case reservedName
        case leadingDot

        public var errorDescription: String? {
            switch self {
            case .emptyName:         return "Enter a folder name."
            case .containsSeparator: return "The name can’t contain “/”."
            case .reservedName:      return "“.” and “..” aren’t valid names."
            case .leadingDot:        return "The name can’t start with a dot."
            }
        }
    }

    /// Validates the trimmed name against the naming rules.
    public static func validate(name rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.emptyName }
        guard !name.contains("/") else { throw ValidationError.containsSeparator }
        guard name != "." && name != ".." else { throw ValidationError.reservedName }
        guard !name.hasPrefix(".") else { throw ValidationError.leadingDot }
    }

    /// The validated absolute target path `<parent>/<name>`.
    public func targetPath() throws -> String {
        try Self.validate(name: rawName)
        return (parentPath as NSString).appendingPathComponent(name)
    }
}
```

- [ ] **Step 4: Regenerate + run tests to verify they pass**

Run: `mise exec -- tuist generate --no-open && mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: PASS (all four `newProject*` tests green). If generate errors with "Manifest not found …/AgentLogos", run `mise exec -- tuist clean` first, then retry.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/Model/NewProjectRequest.swift Tests/ZettyCoreTests/NewProjectRequestTests.swift
git commit -m "feat(core): NewProjectRequest — pure name validation + path composition"
```

---

### Task 2: `newProject` control-protocol command

**Files:**
- Modify: `Sources/ZettyCore/CLI/ControlProtocol.swift` (enum case ~line 26, `CodingKeys` line 50, decode ~line 73, encode ~line 122)
- Test: `Tests/ZettyCoreTests/ControlProtocolTests.swift`

**Interfaces:**
- Consumes: `ControlWire.encodeLine` / `decodeRequest` (existing).
- Produces: `ControlRequest.newProject(path: String, name: String?, gitInit: Bool)` and the wire command string `"new-project"` with keys `path`, `name`, `gitInit`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/ZettyCoreTests/ControlProtocolTests.swift` (inside the existing round-trip `@Test func`, alongside the `addProject` assertions):

```swift
    #expect(try ControlWire.decodeRequest(ControlWire.encodeLine(
        ControlRequest.newProject(path: "/Users/x/new", name: "new", gitInit: true)))
        == .newProject(path: "/Users/x/new", name: "new", gitInit: true))
    // gitInit defaults to false when the key is absent.
    #expect(try ControlWire.decodeRequest(ControlWire.encodeLine(
        ControlRequest.newProject(path: "/Users/x/new", name: nil, gitInit: false)))
        == .newProject(path: "/Users/x/new", name: nil, gitInit: false))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: FAIL — `newProject` is not a member of `ControlRequest`.

- [ ] **Step 3: Write minimal implementation**

In `ControlProtocol.swift`, add the case after `removeProject` (~line 26):

```swift
    /// Create a new directory at `path` (which must NOT already exist) and add
    /// it as a project named `name` (nil → the last path component); `gitInit`
    /// runs `git init` in the new folder. The response is `.pane` with the
    /// first pane's short id.
    case newProject(path: String, name: String?, gitInit: Bool)
```

Add `gitInit` to `CodingKeys` (line 50):

```swift
        case command, target, text, enter, keys, project, wholeTab, killSessions, vertical, lines, path, name, gitInit
```

Add to `init(from:)` after the `add-project` case (~line 71):

```swift
        case "new-project":
            self = .newProject(
                path: try container.decode(String.self, forKey: .path),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                gitInit: try container.decodeIfPresent(Bool.self, forKey: .gitInit) ?? false
            )
```

Add to `encode(to:)` after the `addProject` case (~line 119):

```swift
        case .newProject(let path, let name, let gitInit):
            try container.encode("new-project", forKey: .command)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(gitInit, forKey: .gitInit)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: PASS. The compiler's exhaustive `switch` in `encode(to:)` also guarantees the new case is handled.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/CLI/ControlProtocol.swift Tests/ZettyCoreTests/ControlProtocolTests.swift
git commit -m "feat(core): newProject control-protocol command"
```

---

### Task 3: `zetty new-project` CLI command

**Files:**
- Modify: `Sources/ZettyCore/CLI/ControlCLI.swift` (`usage` ~line 26, `recognizes` line 66, `run` switch ~line 91, new `runNewProject` after `runAddProject` ~line 248)
- Test: `Tests/ZettyCoreTests/NewProjectRequestTests.swift` (append CLI arg-parse tests here — no separate CLI test file exists)

**Interfaces:**
- Consumes: `ControlRequest.newProject` (Task 2), `expectPane`, `failure` (existing private helpers).
- Produces: `ControlCLI.run(["new-project", …])` behavior; `ControlCLI.recognizes` includes `"new-project"`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ZettyCoreTests/NewProjectRequestTests.swift`:

```swift
@Test func cliRecognizesNewProject() {
    #expect(ControlCLI.recognizes(["new-project"]))
}

@Test func cliNewProjectRequiresPath() {
    // Missing path fails BEFORE any socket round-trip → exit 1.
    #expect(ControlCLI.run(["new-project"]) == 1)
}

@Test func cliNewProjectHelpExitsZero() {
    // --help prints usage and returns 0 before any socket round-trip.
    #expect(ControlCLI.run(["new-project", "--help"]) == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: FAIL — `cliRecognizesNewProject` fails (`recognizes` returns false) / `run` treats `new-project` as unknown (returns 1 via the default branch, but `--help` test returns 1 not 0).

- [ ] **Step 3: Write minimal implementation**

In `recognizes` (line 66), add `"new-project"` to the array:

```swift
        return ["status", "ls", "send", "capture", "new-tab", "add-project", "new-project",
                "remove-project", "split", "break", "focus", "close", "reload", "quit",
                "help", "--help", "-h"].contains(first)
```

In the `run` switch, add after the `add-project` case (~line 92):

```swift
        case "new-project":
            return runNewProject(arguments)
```

Add `runNewProject` immediately after `runAddProject` (~line 248):

```swift
    private static func runNewProject(_ arguments: [String]) -> Int32 {
        var name: String?
        var gitInit = false
        var pathParts: [String] = []
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--name":
                index += 1
                guard index < arguments.count else { return failure("--name needs a value") }
                name = arguments[index]
            case "--git":
                gitInit = true
            case "--help", "-h":
                print(usage)
                return 0
            default:
                pathParts.append(arguments[index])
            }
            index += 1
        }
        // Positional path — joined so unquoted paths with spaces still work.
        let raw = pathParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return failure("new-project needs a directory path to create")
        }
        // Resolve here: relative paths are relative to the CLI's cwd, not the app's.
        let expanded = (raw as NSString).expandingTildeInPath
        let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return expectPane(.newProject(path: absolute, name: name, gitInit: gitInit))
    }
```

In `usage`, add after the `add-project` block (~line 29):

```
      zetty new-project <path> [--name <name>] [--git]
                                              create a new directory and add it
                                              as a project (--git runs git init);
                                              prints its first pane's id on stdout
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise exec -- tuist test --test-targets ZettyCoreTests`
Expected: PASS (three `cli*` tests green). Note: the missing-path/`--help` paths return before the socket, so no running app is required.

- [ ] **Step 5: Commit**

```bash
git add Sources/ZettyCore/CLI/ControlCLI.swift Tests/ZettyCoreTests/NewProjectRequestTests.swift
git commit -m "feat(cli): zetty new-project command"
```

---

### Task 4: App-side folder creation + socket handler (end-to-end CLI)

**Files:**
- Modify: `App/Sources/App/TerminalViewController.swift` (add `GitInitOutcome`, `createProjectDirectory`, `runGitInit`, `newProject(path:name:gitInit:)` near the existing `addProject(path:name:)` ~line 1188 and the NSOpenPanel section ~line 1663)
- Modify: `App/Sources/App/AppDelegate.swift` (socket switch, after the `.addProject` case ~line 882)

**Interfaces:**
- Consumes: `NewProjectRequest` (Task 1), `ControlRequest.newProject` (Task 2), existing `addProject(path:name:)` and `addProjectFromURL(_:name:)`.
- Produces:
  - `enum GitInitOutcome { case notRequested, succeeded, failed(String) }` (app layer).
  - `func createProjectDirectory(atPath path: String, gitInit: Bool) -> Result<GitInitOutcome, ControlError>` — creates the dir (hard-fails if it already exists or mkdir fails); runs `git init` when requested, reporting a soft outcome.
  - `func newProject(path: String, name: String?, gitInit: Bool) -> Result<String, ControlError>` — used by the socket handler; creates the folder then calls `addProject(path:name:)`, returning the pane id.

- [ ] **Step 1: Add the app-side folder creator + newProject handler**

In `TerminalViewController.swift`, near `addProject(path:name:)` (after line 1205), add:

```swift
    // MARK: - Create Project (new folder on disk)

    enum GitInitOutcome: Equatable {
        case notRequested
        case succeeded
        case failed(String)
    }

    /// Creates a new directory at `path` (which must not already exist) and,
    /// when `gitInit` is set, runs `git init` in it. Directory creation is a
    /// hard failure; a failed `git init` is soft (the folder still exists).
    func createProjectDirectory(atPath path: String, gitInit: Bool) -> Result<GitInitOutcome, ControlError> {
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        if FileManager.default.fileExists(atPath: target) {
            return .failure(.protocolError("a file or folder already exists at \(target)"))
        }
        do {
            try FileManager.default.createDirectory(
                atPath: target, withIntermediateDirectories: false)
        } catch {
            return .failure(.protocolError("could not create \(target): \(error.localizedDescription)"))
        }
        guard gitInit else { return .success(.notRequested) }
        if let message = runGitInit(atPath: target) {
            return .success(.failed(message))
        }
        return .success(.succeeded)
    }

    /// Runs `git init` in `path`; returns an error message on failure, nil on success.
    private func runGitInit(atPath path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.isEmpty ? "git init exited \(process.terminationStatus)" : text
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Creates a new project folder then adds it (CLI `new-project`). Returns
    /// the first pane's short id. A failed `git init` is non-fatal: the project
    /// is still created and its pane id returned.
    func newProject(path: String, name: String?, gitInit: Bool) -> Result<String, ControlError> {
        switch createProjectDirectory(atPath: path, gitInit: gitInit) {
        case .failure(let error):
            return .failure(error)
        case .success:
            return addProject(path: path, name: name)
        }
    }
```

- [ ] **Step 2: Wire the socket handler**

In `AppDelegate.swift`, add after the `.addProject` case (~line 882):

```swift
        case .newProject(let path, let name, let gitInit):
            switch tvc.newProject(path: path, name: name, gitInit: gitInit) {
            case .success(let pane): return .pane(pane)
            case .failure(let error): return .error(error.localizedDescription)
            }
```

- [ ] **Step 3: Build**

Run: `mise exec -- tuist generate --no-open && xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. (The `.newProject` addition makes the `AppDelegate` socket `switch` exhaustive again — a missing case would fail the build.)

- [ ] **Step 4: Verify end-to-end via the CLI (live app)**

Install/run the freshly built app (per the repo's install ritual), then:

```bash
DIR="/tmp/zetty-create-$(date +%s)"
zetty new-project "$DIR" --name "CreateTest" --git   # prints a pane id
zetty status | grep -A3 CreateTest                    # project is listed
ls -a "$DIR"                                           # shows .git
# cleanup
zetty remove-project CreateTest
rm -rf "$DIR"
```

Expected: `new-project` prints an 8-hex pane id (exit 0); the project appears in `status`; `.git` exists in the new folder. Also confirm the guard: `zetty new-project "$DIR"` a second time (before cleanup) prints `Zetty: a file or folder already exists at …` and exits 1.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/App/TerminalViewController.swift App/Sources/App/AppDelegate.swift
git commit -m "feat(app): create-project folder + git init, wired to new-project socket command"
```

---

### Task 5: Sidebar "+" menu + Create Project panel + rename

**Files:**
- Modify: `App/Sources/App/SidebarView.swift` (add `onNewProject` callback ~line 97; change `addButtonClicked` ~line 517 to pop a menu; tooltip ~line 297)
- Modify: `App/Sources/App/TerminalViewController.swift` (sidebar wiring `sidebar.onAddProject` ~line 474; add `sidebar.onNewProject`; add `createProject(_:)` action + `presentNewProjectPanel()`; add `NSOpenSavePanelDelegate` conformance)

**Interfaces:**
- Consumes: `createProjectDirectory` / `addProjectFromURL` (Task 4), `NewProjectRequest` (Task 1).
- Produces: `SidebarView.onNewProject: (() -> Void)?`; `TerminalViewController.createProject(_:)` (`@objc`).

- [ ] **Step 1: Add the sidebar callback + "+" menu**

In `SidebarView.swift`, after `var onAddProject` (line 97):

```swift
    /// Called when the user chooses "New Project…" from the "+" menu.
    var onNewProject: (() -> Void)?
```

Replace `addButtonClicked` (lines 517–519) with a popup menu:

```swift
    @objc private func addButtonClicked(_ sender: Any?) {
        let menu = NSMenu()
        let newItem = NSMenuItem(
            title: "New Project\u{2026}",
            action: #selector(newProjectMenuClicked(_:)), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)
        let addItem = NSMenuItem(
            title: "Add Existing Project\u{2026}",
            action: #selector(addExistingProjectMenuClicked(_:)), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        let anchor = (sender as? NSView) ?? topAddButton
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: anchor.bounds.height + 4),
                   in: anchor)
    }

    @objc private func newProjectMenuClicked(_: Any?) {
        onNewProject?()
    }

    @objc private func addExistingProjectMenuClicked(_: Any?) {
        onAddProject?()
    }
```

Update the tooltip (line 297) from `"Add project"` to `"Add or create a project"`.

- [ ] **Step 2: Add the Create Project panel + wire the callback**

In `TerminalViewController.swift`, after the sidebar's `onAddProject` wiring (~line 474), add:

```swift
        sidebar.onNewProject = { [weak self] in
            self?.presentNewProjectPanel()
        }
```

Add the action + panel near `presentAddProjectPanel()` (~line 1641). The two accessory controls are stored transiently so the panel delegate can read them:

```swift
    // MARK: - Create Project via NSOpenPanel (+ accessory)

    private var newProjectNameField: NSTextField?
    private var newProjectGitCheckbox: NSButton?

    @objc func createProject(_ sender: Any?) {
        presentNewProjectPanel()
    }

    private func presentNewProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Create"
        panel.message = "Choose where to create the new project folder"

        // Accessory: a Name field + "Initialize git repository" checkbox.
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 62))
        let label = NSTextField(labelWithString: "Name:")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = ZTheme.current.fg2Color
        label.translatesAutoresizingMaskIntoConstraints = false
        let field = NSTextField()
        field.placeholderString = "new-project"
        field.translatesAutoresizingMaskIntoConstraints = false
        let gitCheck = NSButton(checkboxWithTitle: "Initialize git repository", target: nil, action: nil)
        gitCheck.state = .off
        gitCheck.contentTintColor = ZTheme.current.fg2Color
        gitCheck.translatesAutoresizingMaskIntoConstraints = false
        accessory.addSubview(label)
        accessory.addSubview(field)
        accessory.addSubview(gitCheck)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 8),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: accessory.trailingAnchor, constant: -16),
            gitCheck.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            gitCheck.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
        ])
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        panel.delegate = self
        newProjectNameField = field
        newProjectGitCheckbox = gitCheck

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            defer {
                self.newProjectNameField = nil
                self.newProjectGitCheckbox = nil
            }
            guard response == .OK, let parent = panel.url else { return }
            let gitInit = gitCheck.state == .on
            // Delegate validation guarantees a valid, non-existing target here.
            guard let target = try? NewProjectRequest(parentPath: parent.path,
                                                      name: field.stringValue).targetPath() else { return }
            self.performCreateProject(atPath: target, gitInit: gitInit)
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func performCreateProject(atPath target: String, gitInit: Bool) {
        switch createProjectDirectory(atPath: target, gitInit: gitInit) {
        case .failure(let error):
            presentCreateProjectError(error.localizedDescription)
        case .success(let outcome):
            addProjectFromURL(URL(fileURLWithPath: target))
            if case .failed(let message) = outcome {
                presentCreateProjectWarning(
                    "The project was created, but git init failed:\n\(message)")
            }
        }
    }

    private func presentCreateProjectError(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t create the project"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if let window = view.window { alert.beginSheetModal(for: window, completionHandler: nil) }
        else { alert.runModal() }
    }

    private func presentCreateProjectWarning(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Project created"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        if let window = view.window { alert.beginSheetModal(for: window, completionHandler: nil) }
        else { alert.runModal() }
    }
```

Add the panel-validation delegate conformance (a new extension at the end of the file). It rejects invalid names / existing targets when the user clicks Create, keeping the panel open with a message:

```swift
extension TerminalViewController: NSOpenSavePanelDelegate {
    public func panel(_ sender: Any, validateURL url: URL) throws {
        guard let field = newProjectNameField else { return }
        let request = NewProjectRequest(parentPath: url.path, name: field.stringValue)
        do {
            let target = try request.targetPath()
            if FileManager.default.fileExists(atPath: target) {
                throw NSError(domain: "Zetty", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "A folder named “\(request.name)” already exists here.",
                ])
            }
        } catch let error as NewProjectRequest.ValidationError {
            throw NSError(domain: "Zetty", code: 2, userInfo: [
                NSLocalizedDescriptionKey: error.errorDescription ?? "Invalid name.",
            ])
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `mise exec -- tuist generate --no-open && xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify live (GUI — Glen or headless where possible)**

Install/run the build. Click the sidebar "+": a menu shows **New Project…** and **Add Existing Project…**. New Project… opens a panel with a Name field + "Initialize git repository" checkbox and a **Create** button. Confirm:
- Empty name → clicking Create keeps the panel open with "Enter a folder name."
- A name matching an existing folder in the chosen parent → "A folder named X already exists here."
- A valid new name → folder is created, project added, pane spawns; with the checkbox on, `.git` exists.
GUI verification here respects the session's TCC limits — drive via the CLI where the GUI can't be automated, or have Glen click through.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/App/SidebarView.swift App/Sources/App/TerminalViewController.swift
git commit -m "feat(app): sidebar + menu — New Project / Add Existing Project + create panel"
```

---

### Task 6: Project menu + palette entries + labels

**Files:**
- Modify: `App/Sources/App/AppDelegate.swift` (Project menu ~lines 1213–1220: add "New Project…", relabel "Add Project…")
- Modify: `App/Sources/App/TerminalViewController.swift` (palette entries ~line 1079: add "New Project…", relabel "Add Project…")

**Interfaces:**
- Consumes: `TerminalViewController.createProject(_:)` (Task 5), existing `addProject(_:)`.

- [ ] **Step 1: Add the Project-menu item + relabel**

In `AppDelegate.swift`, replace the "Add Project…" block (lines 1213–1220) with a "New Project…" item (⇧⌘N) followed by the relabeled "Add Existing Project…" (⌘O):

```swift
        // "New Project…"  ⇧⌘N — create a new folder and add it
        let newProject = NSMenuItem(
            title: "New Project\u{2026}",
            action: #selector(TerminalViewController.createProject(_:)),
            keyEquivalent: "n"
        )
        newProject.keyEquivalentModifierMask = [.command, .shift]
        projectMenu.addItem(newProject)

        // "Add Existing Project…"  ⌘O — pick an existing directory
        let addProject = NSMenuItem(
            title: "Add Existing Project\u{2026}",
            action: #selector(TerminalViewController.addProject(_:)),
            keyEquivalent: "o"
        )
        addProject.keyEquivalentModifierMask = [.command]
        projectMenu.addItem(addProject)
```

- [ ] **Step 2: Add the palette entries + relabel**

In `TerminalViewController.swift`, replace the single "Add Project…" palette line (line 1079) with two entries:

```swift
            PaletteCommand(glyph: "＋", label: "New Project…", kbd: "⇧⌘N") { [weak self] in self?.createProject(nil) },
            PaletteCommand(glyph: "＋", label: "Add Existing Project…", kbd: "⌘O") { [weak self] in self?.addProject(nil) },
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project zetty.xcodeproj -scheme zetty -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`. (No new files → no `tuist generate` needed.)

- [ ] **Step 4: Verify live**

Install/run. Project menu shows **New Project…** (⇧⌘N) and **Add Existing Project…** (⌘O); ⇧⌘N opens the create panel; ⌘O opens the existing-directory picker. The command palette lists both entries and each opens the right dialog.

- [ ] **Step 5: Commit**

```bash
git add App/Sources/App/AppDelegate.swift App/Sources/App/TerminalViewController.swift
git commit -m "feat(app): Project menu + palette — New Project (⇧⌘N) + relabel Add Existing"
```

---

## Self-Review

**Spec coverage:**
- Pick-parent-then-name → Task 5 (NSOpenPanel picks parent, accessory name field; `NewProjectRequest` composes `<parent>/<name>`). ✓
- Sidebar "+" menu (New / Add Existing) → Task 5. ✓
- Rename "Add Project" → "Add Existing Project…" (labels only; selector + CLI verb unchanged) → Tasks 5 (sidebar) + 6 (menu, palette). ✓
- Optional git-init checkbox, default off → Tasks 4 (mkdir + git init) + 5 (checkbox). ✓
- CLI `new-project <path> [--name] [--git]` → Tasks 2 (protocol) + 3 (CLI) + 4 (handler). ✓
- Errors: empty/invalid name, already-exists, mkdir-fail (hard), git-init-fail (soft) → Task 1 (validation) + Task 4 (`createProjectDirectory` outcomes) + Task 5 (panel delegate + alerts). ✓
- Layout template on create → reuses `addProjectFromURL`/`addProject(path:name:)` which already apply it (Task 4/5), no special handling. ✓
- Tests: `NewProjectRequest` matrix (Task 1), protocol round-trip (Task 2), CLI recognize/usage (Task 3), live e2e (Task 4). ✓

**Deviation from spec (deliberate):** the design's "CLI prints a git-init warning to stderr but exits 0" is simplified — over the socket the response is just the pane id, so a soft git-init failure on the CLI path is non-fatal and silent (folder still created, exit 0). The GUI path surfaces the git warning via an alert. This avoids widening the response protocol for a rare, non-fatal case. If the CLI warning is wanted later, add a `.paneWithWarning` response variant.

**Type consistency:** `NewProjectRequest` (`validate(name:)`, `targetPath()`, `ValidationError`), `ControlRequest.newProject(path:name:gitInit:)`, `GitInitOutcome` (`.notRequested/.succeeded/.failed`), `createProjectDirectory(atPath:gitInit:) -> Result<GitInitOutcome, ControlError>`, `newProject(path:name:gitInit:) -> Result<String, ControlError>`, `createProject(_:)` action — names match across all tasks.

**Placeholder scan:** no TBD/TODO; every code step shows full code; every command has an expected result.
