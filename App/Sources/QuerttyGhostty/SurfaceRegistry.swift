// SurfaceRegistry.swift — Task 2 / Task 3
//
// Maps each `Surface.id` (UUID) to a persistent pair of (TerminalController,
// TerminalView) so that re-renders never recreate a live terminal.
//
// Session ownership: the PTY session lives inside `TerminalView`
// (AppTerminalView), specifically in its embedded `TerminalSurfaceCoordinator`
// which holds the `TerminalSurface` (real libghostty surface + PTY).
// `TerminalController` only owns the ghostty app/config lifecycle; it does NOT
// hold the PTY.  Therefore both the view AND the controller must be persisted
// — the registry stores a `TerminalViewPair` keyed by `Surface.id`.
//
// Design note — protocol seam:
//   `TerminalController` (from GhosttyTerminal) is @MainActor and calls
//   `ghostty_init` during `init`, which requires a display/PTY context.
//   Instantiating it in a headless test process would crash.  Rather than
//   force-wrapping the concrete type, `SurfaceRegistry` is parameterised over
//   the `TerminalControlling` protocol, so tests can inject a lightweight mock
//   via `controllerFactory`.  Production code uses the default factory, which
//   creates a real `TerminalController`.
//
//   Because `TerminalController` is @MainActor, `SurfaceRegistry` is also
//   @MainActor so that the default factory closure runs on the main actor and
//   Swift's strict concurrency checks are satisfied.

import AppKit
import Foundation
import GhosttyTerminal
import QuerttyCore

// MARK: - Protocol seam

/// The minimal interface `SurfaceRegistry` requires of a terminal controller.
///
/// `TerminalController` (from GhosttyTerminal) conforms to this protocol via
/// a retroactive conformance below, so callers that already hold a
/// `TerminalController` can use it anywhere a `TerminalControlling` is expected
/// without casting.
public protocol TerminalControlling: AnyObject {}

extension TerminalController: TerminalControlling {}

// MARK: - TerminalViewPair

/// A retained pair of controller + view for one logical surface.
///
/// The **view** is the persistent unit: it owns the `TerminalSurfaceCoordinator`
/// which holds the live `TerminalSurface` (PTY).  The controller is stored here
/// so callers that only need the controller (e.g. tests) can access it without
/// the view.
public struct TerminalViewPair {
    public let controller: any TerminalControlling
    /// The persistent `NSView` that renders this terminal (AppTerminalView).
    public let view: NSView
}

// MARK: - SurfaceRegistry

/// Stores a `TerminalViewPair` for every live `Surface`, keyed by
/// `Surface.id`.  Callers obtain the view for a surface via
/// `terminalView(for:)` — if one already exists it is returned unchanged;
/// otherwise a new one is created via the factories and stored.
///
/// The `controller(for:)` method is kept for backward-compatibility with
/// existing tests and callers that only need the controller.
///
/// Call `prune(keeping:)` after each layout pass to tear down pairs whose
/// surfaces have been removed.
///
/// `SurfaceRegistry` is `@MainActor` because the default factories create a
/// `TerminalController` and a `TerminalView`, which are themselves `@MainActor`.
@MainActor
public final class SurfaceRegistry {

    // MARK: - Storage

    private var pairs: [UUID: TerminalViewPair] = [:]

    // MARK: - Factories

    /// Closure used to create a new controller for a surface that has no
    /// entry yet.  Defaults to `TerminalController()` (the real ghostty
    /// implementation).  Override in tests to inject a mock.
    private let controllerFactory: @MainActor (Surface) -> any TerminalControlling

    /// Closure used to create a new `NSView` (AppTerminalView) for a surface.
    /// Receives the controller so it can be wired up immediately.
    /// Defaults to creating a properly-configured `TerminalView` with `.exec` backend.
    private let viewFactory: @MainActor (Surface, any TerminalControlling) -> NSView

    // MARK: - Init

    public init(
        controllerFactory: @escaping @MainActor (Surface) -> any TerminalControlling = { _ in
            TerminalController()
        },
        viewFactory: @escaping @MainActor (Surface, any TerminalControlling) -> NSView = { surface, ctrl in
            let v = TerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
            if let tc = ctrl as? TerminalController {
                v.controller = tc
            }
            v.configuration = TerminalSurfaceOptions(backend: .exec)
            v.translatesAutoresizingMaskIntoConstraints = false
            return v
        }
    ) {
        self.controllerFactory = controllerFactory
        self.viewFactory = viewFactory
    }

    // MARK: - Public API

    /// Returns the persistent controller for `surface`, creating a pair if
    /// this is the first call for that `surface.id`.
    @discardableResult
    public func controller(for surface: Surface) -> any TerminalControlling {
        pair(for: surface).controller
    }

    /// Returns the persistent `NSView` (AppTerminalView) for `surface`,
    /// creating a pair if this is the first call for that `surface.id`.
    ///
    /// The returned view must be embedded directly into the view hierarchy;
    /// it must not be recreated on subsequent calls — the PTY session lives
    /// inside it and must be preserved across re-renders.
    public func terminalView(for surface: Surface) -> NSView {
        pair(for: surface).view
    }

    /// Removes every pair whose id is not in `ids`, allowing them to be
    /// deallocated (which tears down the PTY and ghostty surface).
    public func prune(keeping ids: Set<UUID>) {
        pairs = pairs.filter { ids.contains($0.key) }
    }

    /// The set of surface IDs that currently have a live pair.
    public var liveIDs: Set<UUID> {
        Set(pairs.keys)
    }

    // MARK: - Private

    private func pair(for surface: Surface) -> TerminalViewPair {
        if let existing = pairs[surface.id] {
            return existing
        }
        let ctrl = controllerFactory(surface)
        let view = viewFactory(surface, ctrl)
        let pair = TerminalViewPair(controller: ctrl, view: view)
        pairs[surface.id] = pair
        return pair
    }
}
