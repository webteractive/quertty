import Testing
import Foundation
@testable import ZettyCore

private func tempRoot() throws -> String {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-pf-\(UUID().uuidString)").path
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    return root
}

@Test func projectFileRoundTripsThroughRepoFile() throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }

    let file = ProjectFile(
        layoutTemplate: LayoutTemplate(tabs: [TemplateTab(root: .pane(workingDir: ".", command: "make dev"))]),
        startupCommand: "make dev",
        envNames: ["API_KEY", "DB_URL"])
    try ProjectFileIO.save(file, projectRoot: root)

    #expect(FileManager.default.fileExists(atPath: "\(root)/.zetty/project.json"))
    #expect(ProjectFileIO.load(projectRoot: root) == file)
}

@Test func projectFileLoadToleratesMissingAndCorrupt() throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }

    #expect(ProjectFileIO.load(projectRoot: root) == nil)   // missing → nil

    try FileManager.default.createDirectory(atPath: "\(root)/.zetty", withIntermediateDirectories: true)
    try "not json".write(toFile: "\(root)/.zetty/project.json", atomically: true, encoding: .utf8)
    #expect(ProjectFileIO.load(projectRoot: root) == nil)   // corrupt → nil, never throws
}

@Test func projectFileIgnoresHandEditedEnvValues() throws {
    let root = try tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    try FileManager.default.createDirectory(atPath: "\(root)/.zetty", withIntermediateDirectories: true)

    // A hand-edited values map must be ignored on read AND absent after a
    // re-save — the type has no field for it, by construction.
    let json = #"{"schemaVersion":1,"envNames":["API_KEY"],"env":{"API_KEY":"secret"}}"#
    try json.write(toFile: "\(root)/.zetty/project.json", atomically: true, encoding: .utf8)

    let loaded = ProjectFileIO.load(projectRoot: root)
    #expect(loaded?.envNames == ["API_KEY"])

    try ProjectFileIO.save(loaded!, projectRoot: root)
    let rewritten = try String(contentsOfFile: "\(root)/.zetty/project.json", encoding: .utf8)
    #expect(!rewritten.contains("secret"))
}

@Test func layoutTemplateStoreRoundTripsAndToleratesCorrupt() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("zetty-lts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = LayoutTemplateStore(directory: dir)

    #expect(store.load() == nil)                            // missing → nil

    let template = LayoutTemplate(tabs: [TemplateTab(root: .pane(workingDir: ".", command: nil))])
    try store.save(template)
    #expect(store.load() == template)

    try "broken".write(to: dir.appendingPathComponent("layout-template.json"),
                       atomically: true, encoding: .utf8)
    #expect(store.load() == nil)                            // corrupt → nil
}
