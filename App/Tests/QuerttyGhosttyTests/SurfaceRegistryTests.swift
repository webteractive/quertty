// SurfaceRegistryTests.swift — Task 2
//
// Verifies SurfaceRegistry bookkeeping via the TerminalControlling protocol
// seam, so no real ghostty PTY/display is needed during unit tests.

import XCTest
import QuerttyCore
@testable import QuerttyGhostty

// MARK: - Mock

/// A lightweight stand-in that satisfies `TerminalControlling` without
/// touching libghostty.
final class MockTerminalController: TerminalControlling {}

// MARK: - Tests

/// `@MainActor` because `SurfaceRegistry` is `@MainActor` (its default
/// factory creates `TerminalController`, which requires the main actor).
@MainActor
final class SurfaceRegistryTests: XCTestCase {

    func testReusesControllerForSameSurfaceID() {
        let reg = SurfaceRegistry(
            controllerFactory: { _ in MockTerminalController() }
        )
        let s = Surface(workingDir: "/tmp")
        let a = reg.controller(for: s)
        let b = reg.controller(for: s)
        XCTAssertTrue(
            ObjectIdentifier(a as AnyObject) == ObjectIdentifier(b as AnyObject),
            "registry must return the same instance on second call"
        )
        XCTAssertEqual(reg.liveIDs, [s.id])
    }

    func testPruneTearsDownAbsentSurfaces() {
        let reg = SurfaceRegistry(
            controllerFactory: { _ in MockTerminalController() }
        )
        let s1 = Surface(workingDir: "/tmp")
        let s2 = Surface(workingDir: "/tmp")
        _ = reg.controller(for: s1)
        _ = reg.controller(for: s2)
        reg.prune(keeping: [s1.id])
        XCTAssertEqual(reg.liveIDs, [s1.id])
    }

    func testNewSurfaceAfterPruneGetsNewController() {
        let reg = SurfaceRegistry(
            controllerFactory: { _ in MockTerminalController() }
        )
        let s = Surface(workingDir: "/tmp")
        let first = reg.controller(for: s)
        reg.prune(keeping: [])
        // After pruning the registry is empty, so the next call creates a new one.
        let second = reg.controller(for: s)
        XCTAssertFalse(
            ObjectIdentifier(first as AnyObject) == ObjectIdentifier(second as AnyObject),
            "pruned entry must not be reused"
        )
    }
}
