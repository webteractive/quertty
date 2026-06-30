import Testing
@testable import QuerttyCore

@Test func seedsOneActiveProject() {
    let ws = WorkspaceModel()
    #expect(ws.projects.count == 1)
    #expect(ws.activeIndex == 0)
}

@Test func addProjectAppendsAndActivates() {
    let ws = WorkspaceModel()
    let p = ws.addProject(name: "web", rootPath: "/tmp/web")
    #expect(ws.projects.count == 2)
    #expect(ws.activeIndex == 1)
    #expect(ws.activeProject.id == p.id)
    #expect(ws.activeProject.rootPath == "/tmp/web")
}

@Test func eachProjectHasOwnTabList() {
    let ws = WorkspaceModel()
    let a = ws.activeProject.tabList
    _ = ws.addProject(name: "b", rootPath: "/tmp/b")
    let b = ws.activeProject.tabList
    #expect(a !== b)  // distinct TabList instances
}

@Test func removingProjectBeforeActiveStepsBack() {
    let ws = WorkspaceModel()
    _ = ws.addProject(name: "b", rootPath: "/b")
    _ = ws.addProject(name: "c", rootPath: "/c")   // 3 projects, active = 2
    ws.removeProject(at: 0)
    #expect(ws.projects.count == 2)
    #expect(ws.activeIndex == 1)
}

@Test func removingLastRemainingProjectIsNoOp() {
    let ws = WorkspaceModel()
    ws.removeProject(at: 0)
    #expect(ws.projects.count == 1)
}

@Test func togglePinFlips() {
    let ws = WorkspaceModel()
    #expect(ws.projects[0].isPinned == false)
    ws.togglePin(at: 0)
    #expect(ws.projects[0].isPinned == true)
}

@Test func workspaceSelectIgnoresOutOfRange() {
    let ws = WorkspaceModel()
    ws.select(index: 5)
    #expect(ws.activeIndex == 0)
}

@Test func removingActiveMiddleProjectLandsOnNext() {
    let ws = WorkspaceModel()
    _ = ws.addProject(name: "b", rootPath: "/b")
    _ = ws.addProject(name: "c", rootPath: "/c")   // 3 projects, active = 2
    ws.select(index: 1)                              // make the middle project active
    ws.removeProject(at: 1)                          // remove the active (non-last) project
    #expect(ws.projects.count == 2)
    #expect(ws.activeIndex == 1)                     // next project slid into place
}

@Test func removingActiveLastProjectClamps() {
    let ws = WorkspaceModel()
    _ = ws.addProject(name: "b", rootPath: "/b")     // 2 projects, active = 1 (last)
    ws.removeProject(at: 1)
    #expect(ws.projects.count == 1)
    #expect(ws.activeIndex == 0)
}

@Test func restoringClampsActiveIndex() {
    let trees = [ProjectRuntime(name: "a", rootPath: "/a"),
                 ProjectRuntime(name: "b", rootPath: "/b")]
    let high = WorkspaceModel(restoring: trees, activeIndex: 99)
    #expect(high?.activeIndex == 1)                  // clamped to last
    let low = WorkspaceModel(restoring: trees, activeIndex: -5)
    #expect(low?.activeIndex == 0)                   // clamped to first
    #expect(WorkspaceModel(restoring: []) == nil)    // nil on empty
}
