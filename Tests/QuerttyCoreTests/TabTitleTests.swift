import Testing
import Foundation
@testable import QuerttyCore

@Test func tabTitlePrefersManual() {
    #expect(TabTitle.display(manualTitle: "mine", focusedSurfaceTitle: "vim", workingDir: "/x", index: 0) == "mine")
}

@Test func tabTitleDefaultsToWorkingDirBasename() {
    // pwd is the default, taking precedence over the terminal-reported title.
    #expect(TabTitle.display(manualTitle: nil, focusedSurfaceTitle: "vim", workingDir: "/x/y", index: 0) == "y")
}

@Test func tabTitleUsesFocusedTitleWhenNoWorkingDir() {
    #expect(TabTitle.display(manualTitle: nil, focusedSurfaceTitle: "vim", workingDir: nil, index: 0) == "vim")
    // "/" has no usable basename, so it also falls through to the title.
    #expect(TabTitle.display(manualTitle: nil, focusedSurfaceTitle: "vim", workingDir: "/", index: 0) == "vim")
}

@Test func tabTitleFallsBackToWorkingDirBasename() {
    #expect(TabTitle.display(manualTitle: nil, focusedSurfaceTitle: "  ", workingDir: "/Users/me/web", index: 0) == "web")
}

@Test func tabTitleFallsBackToPositional() {
    #expect(TabTitle.display(manualTitle: " ", focusedSurfaceTitle: nil as String?, workingDir: nil as String?, index: 2) == "Tab 3")
}

@Test func tabTitleRootDirFallsBackToPositional() {
    // "/" has no meaningful basename -> should fall through to positional.
    #expect(TabTitle.display(manualTitle: nil, focusedSurfaceTitle: nil, workingDir: "/", index: 0) == "Tab 1")
}

@Test func paneTreeManualTitleDefaultsNilAndIsCodable() throws {
    var t = PaneTree(layout: Layout(root: .leaf(Surface(workingDir: "/x"))))
    #expect(t.manualTitle == nil)
    t.manualTitle = "named"
    let data = try JSONEncoder().encode(t)
    let back = try JSONDecoder().decode(PaneTree.self, from: data)
    #expect(back.manualTitle == "named")
}
