import Testing
import Foundation
@testable import ZettyCore

private func sampleTemplate() -> LayoutTemplate {
    LayoutTemplate(schemaVersion: 1, tabs: [
        TemplateTab(root: .split(
            direction: .horizontal, ratio: 0.6,
            first: .pane(workingDir: ".", command: "claude"),
            second: .split(
                direction: .vertical, ratio: 0.5,
                first: .pane(workingDir: "api", command: "npm run dev"),
                second: .pane(workingDir: "logs", command: nil)))),
        TemplateTab(root: .pane(workingDir: "docs", command: nil)),
    ])
}

@Test func layoutTemplateRoundTripsThroughJSON() throws {
    let template = sampleTemplate()
    let data = try JSONEncoder().encode(template)
    let decoded = try JSONDecoder().decode(LayoutTemplate.self, from: data)
    #expect(decoded == template)
}

@Test func templateNodeUsesReadableTypeDiscriminator() throws {
    let data = try JSONEncoder().encode(TemplateNode.pane(workingDir: ".", command: "ls"))
    let json = String(data: data, encoding: .utf8)!
    #expect(json.contains(#""type":"pane""#))
}

@Test func applyBuildsAbsoluteCwdsAndReturnsCommands() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-tpl-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(
        atPath: "\(root)/api", withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let template = sampleTemplate()
    let built = template.tabList(rootPath: root)
    #expect(built != nil)
    guard let (tabList, commands) = built else { return }

    #expect(tabList.trees.count == 2)
    let firstTabSurfaces = tabList.trees[0].layout.surfaces
    #expect(firstTabSurfaces.count == 3)
    #expect(firstTabSurfaces[0].workingDir == root)                 // "." → root
    #expect(firstTabSurfaces[1].workingDir == "\(root)/api")        // exists → kept
    #expect(firstTabSurfaces[2].workingDir == root)                 // "logs" missing → root fallback

    // Commands keyed by the NEW surface ids; nil-command panes absent.
    #expect(commands[firstTabSurfaces[0].id] == "claude")
    #expect(commands[firstTabSurfaces[1].id] == "npm run dev")
    #expect(commands[firstTabSurfaces[2].id] == nil)

    // Geometry preserved.
    guard case .split(let direction, let ratio, _, _) = tabList.trees[0].layout.root else {
        Issue.record("expected split root"); return
    }
    #expect(direction == .horizontal)
    #expect(ratio == 0.6)

    // Surfaces record their command for later re-capture.
    #expect(firstTabSurfaces[0].command == "claude")
}

@Test func applyReturnsNilForEmptyTemplate() {
    #expect(LayoutTemplate(schemaVersion: 1, tabs: []).tabList(rootPath: "/tmp") == nil)
}

@Test func captureMakesCwdsRelativeAndRoundTrips() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-cap-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(
        atPath: "\(root)/api", withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: root) }

    let template = sampleTemplate()
    guard let (tabList, _) = template.tabList(rootPath: root) else {
        Issue.record("apply failed"); return
    }
    let captured = LayoutTemplate.capture(from: tabList, rootPath: root)
    #expect(captured.tabs.count == 2)
    guard case .split(_, _, let first, _) = captured.tabs[0].root,
          case .pane(let dir, let command) = first else {
        Issue.record("expected split with pane"); return
    }
    #expect(dir == ".")                 // root-relative again
    #expect(command == "claude")

    // Out-of-root cwd stays absolute rather than being faked relative.
    let foreign = TabList(defaultWorkingDir: "/usr/local")
    let capturedForeign = LayoutTemplate.capture(from: foreign, rootPath: root)
    guard case .pane(let foreignDir, _) = capturedForeign.tabs[0].root else {
        Issue.record("expected pane"); return
    }
    #expect(foreignDir == "/usr/local")
}
