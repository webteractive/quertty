import AppKit
import QuerttyCore
import QuerttyGhostty

// MARK: - TerminalViewController

/// Hosts a recursive split-pane terminal layout driven by a `PaneTree`.
///
/// # Layout model
/// `paneTree.layout.root` is a `SurfaceNode` tree.  Each time the tree
/// changes, `rebuildSurfaceNodeView()` replaces the root content view with a
/// fresh `SurfaceNodeView`.  Unchanged leaf panes share their persistent
/// `TerminalView` from `registry`, so splits never kill a sibling session.
///
/// # Session ownership
/// The live PTY lives inside `TerminalView` (AppTerminalView) via its
/// embedded `TerminalSurfaceCoordinator → TerminalSurface`.
/// `TerminalController` only owns the ghostty app/config lifecycle.
/// `SurfaceRegistry` retains both; `prune(keeping:)` tears down removed panes.
///
/// # Default window
/// Seeds the tree with a single leaf — one terminal, matching Phase 0 behaviour.
///
/// # Debug split
/// To visually verify two-pane rendering without running the app, set
/// `debugTwoPane = true` below.  Revert before shipping.
final class TerminalViewController: NSViewController {

    // MARK: - Debug flag (REVERT before committing)
    //
    // Set to `true` temporarily to seed a two-leaf vertical split so the
    // build proves the split path compiles.  The default (false) gives the
    // normal single-pane window.
    private static let debugTwoPane: Bool = false

    // MARK: - State

    /// Shared registry — persists terminal views across re-renders.
    private let registry = SurfaceRegistry()

    /// The logical pane tree.  Mutate this, then call `rebuildSurfaceNodeView()`.
    private var paneTree: PaneTree = {
        let surface = Surface(workingDir: NSHomeDirectory())
        let layout = Layout(root: .leaf(surface))
        var tree = PaneTree(layout: layout, focusedSurfaceID: surface.id)

        // DEBUG: temporary two-pane seed — revert to single-leaf before shipping.
        if TerminalViewController.debugTwoPane {
            let second = Surface(workingDir: NSHomeDirectory())
            tree.splitFocused(direction: .vertical, newSurface: second)
        }

        return tree
    }()

    /// The currently installed root content view (a `SurfaceNodeView`).
    private var rootContentView: SurfaceNodeView?

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildSurfaceNodeView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Give focus to whichever terminal the PaneTree considers focused.
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    // MARK: - Tree rendering

    /// Replaces the root content view with a freshly-built `SurfaceNodeView`
    /// derived from `paneTree.layout.root`.
    ///
    /// After building, prunes the registry to release controllers/views for
    /// any surfaces that are no longer in the tree.
    private func rebuildSurfaceNodeView() {
        rootContentView?.removeFromSuperview()

        let newRoot = SurfaceNodeView(node: paneTree.layout.root, registry: registry)
        newRoot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newRoot)
        NSLayoutConstraint.activate([
            newRoot.topAnchor.constraint(equalTo: view.topAnchor),
            newRoot.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newRoot.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newRoot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        rootContentView = newRoot

        let liveIDs = Set(paneTree.layout.surfaces.map(\.id))
        registry.prune(keeping: liveIDs)
    }

    // MARK: - Helpers

    /// Returns the `NSView` for the currently focused surface, if any.
    private func focusedTerminalView() -> NSView? {
        guard let surface = paneTree.focusedSurface else { return nil }
        return registry.terminalView(for: surface)
    }
}
