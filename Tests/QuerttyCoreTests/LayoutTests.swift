import Testing
import Foundation
@testable import QuerttyCore

private func surface(_ n: Int) -> Surface {
    Surface(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!,
            workingDir: "/tmp")
}

@Test func singleLeafHasOneSurface() {
    let layout = Layout(root: .leaf(surface(1)))
    #expect(layout.surfaces.map(\.id) == [surface(1).id])
}

@Test func splitReplacesLeafWithBinarySplit() {
    var layout = Layout(root: .leaf(surface(1)))
    let ok = layout.split(surfaceID: surface(1).id, direction: .vertical, newSurface: surface(2))
    #expect(ok)
    #expect(layout.surfaces.map(\.id) == [surface(1).id, surface(2).id])
    guard case let .split(direction, ratio, first, second) = layout.root else {
        Issue.record("root should be a split"); return
    }
    #expect(direction == .vertical)
    #expect(ratio == 0.5)
    #expect(first == .leaf(surface(1)))
    #expect(second == .leaf(surface(2)))
}

@Test func splitUnknownSurfaceReturnsFalse() {
    var layout = Layout(root: .leaf(surface(1)))
    #expect(layout.split(surfaceID: surface(9).id, direction: .horizontal, newSurface: surface(2)) == false)
}

@Test func closeCollapsesParentToSibling() {
    var layout = Layout(root: .leaf(surface(1)))
    _ = layout.split(surfaceID: surface(1).id, direction: .horizontal, newSurface: surface(2))
    let ok = layout.close(surfaceID: surface(1).id)
    #expect(ok)
    #expect(layout.root == .leaf(surface(2)))
}

@Test func closingTheOnlySurfaceFails() {
    var layout = Layout(root: .leaf(surface(1)))
    #expect(layout.close(surfaceID: surface(1).id) == false)
    #expect(layout.root == .leaf(surface(1)))
}
