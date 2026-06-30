// SurfaceRegistry.swift — Task 2
//
// Maps each `Surface.id` (UUID) to a persistent `TerminalControlling` instance
// so that re-renders never recreate a live terminal.
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

// MARK: - SurfaceRegistry

/// Stores a `TerminalControlling` for every live `Surface`, keyed by
/// `Surface.id`.  Callers obtain the controller for a surface via
/// `controller(for:)` — if one already exists it is returned unchanged;
/// otherwise a new one is created via the factory and stored.
///
/// Call `prune(keeping:)` after each layout pass to tear down controllers
/// whose surfaces have been removed.
///
/// `SurfaceRegistry` is `@MainActor` because the default factory creates a
/// `TerminalController`, which is itself `@MainActor`.
@MainActor
public final class SurfaceRegistry {

    // MARK: - Storage

    private var controllers: [UUID: any TerminalControlling] = [:]

    // MARK: - Factory

    /// Closure used to create a new controller for a surface that has no
    /// entry yet.  Defaults to `TerminalController()` (the real ghostty
    /// implementation).  Override in tests to inject a mock.
    private let controllerFactory: @MainActor (Surface) -> any TerminalControlling

    // MARK: - Init

    public init(
        controllerFactory: @escaping @MainActor (Surface) -> any TerminalControlling = { _ in
            TerminalController()
        }
    ) {
        self.controllerFactory = controllerFactory
    }

    // MARK: - Public API

    /// Returns the persistent controller for `surface`, creating one if
    /// this is the first call for that `surface.id`.
    @discardableResult
    public func controller(for surface: Surface) -> any TerminalControlling {
        if let existing = controllers[surface.id] {
            return existing
        }
        let new = controllerFactory(surface)
        controllers[surface.id] = new
        return new
    }

    /// Removes every controller whose id is not in `ids`, allowing them to
    /// be deallocated.
    public func prune(keeping ids: Set<UUID>) {
        controllers = controllers.filter { ids.contains($0.key) }
    }

    /// The set of surface IDs that currently have a live controller.
    public var liveIDs: Set<UUID> {
        Set(controllers.keys)
    }
}
