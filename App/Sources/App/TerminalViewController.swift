import AppKit
import QuerttyCore
import QuerttyGhostty

// MARK: - TerminalViewController

/// Hosts a recursive split-pane terminal layout driven by a `PaneTree`,
/// with full tab support via `TabList`.
///
/// # Layout model
/// `paneTree.layout.root` is a `SurfaceNode` tree.  Each time the tree
/// changes, `rebuildSurfaceNodeView()` replaces the root content view with a
/// fresh `SurfaceNodeView`.  Unchanged leaf panes share their persistent
/// `TerminalView` from `registry`, so splits never kill a sibling session.
///
/// # Tab model
/// A `TabList` holds one `PaneTree` per tab.  The computed `paneTree`
/// property forwards to `tabList.activeTree`, so all `PaneActions`
/// methods operate on the active tab without modification.
///
/// # Registry pruning
/// After each rebuild the registry is pruned to the UNION of surface IDs across
/// ALL tabs.  Background tabs keep their live PTY sessions; only truly closed
/// surfaces are torn down.
///
/// # Session ownership
/// The live PTY lives inside `TerminalView` (AppTerminalView) via its
/// embedded `TerminalSurfaceCoordinator → TerminalSurface`.
/// `SurfaceRegistry` retains both; `prune(keeping:)` tears down removed panes.
final class TerminalViewController: NSViewController {

    // MARK: - State

    /// Shared registry — persists terminal views across re-renders and tab switches.
    private let registry = SurfaceRegistry()

    /// Tab manager.  One `PaneTree` per tab.
    private let tabList = TabList()

    /// The logical pane tree for the ACTIVE tab.  Mutate this, then call
    /// `rebuildSurfaceNodeView()`.  Declared `internal` so the `PaneActions`
    /// extension (same module) can write it.
    var paneTree: PaneTree {
        get { tabList.activeTree }
        set { tabList.activeTree = newValue }
    }

    /// The currently installed root content view (a `SurfaceNodeView`).
    private var rootContentView: SurfaceNodeView?

    /// The tab bar strip shown above the pane area.
    private var tabBarView: TabBarView?

    /// KVO token for observing `window.firstResponder`.
    private var firstResponderObservation: NSKeyValueObservation?

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabBar()
        rebuildSurfaceNodeView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Give focus to whichever terminal the PaneTree considers focused.
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
        // Observe first-responder changes on the window to track which pane the
        // user clicks into.  `AppTerminalView.onFocusChange` is `internal` to
        // GhosttyTerminal, so KVO on `NSWindow.firstResponder` is the only
        // cross-module way to detect the transition.
        startObservingFirstResponder()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        firstResponderObservation = nil
    }

    // MARK: - Tab bar setup

    private func setupTabBar() {
        let tabBar = TabBarView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)

        tabBar.onSelect = { [weak self] index in
            self?.selectTab(at: index)
        }
        tabBar.onNewTab = { [weak self] in
            self?.newTab(nil)
        }

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        self.tabBarView = tabBar
        refreshTabBar()
    }

    /// Syncs the tab bar UI state with `tabList`.
    private func refreshTabBar() {
        let titles = tabList.trees.indices.map { tabList.title(at: $0) }
        tabBarView?.update(titles: titles, selectedIndex: tabList.activeIndex)
    }

    // MARK: - Tab actions (responder-chain targets)

    /// Open a new tab and focus its single fresh pane.  Key equivalent: ⌘T.
    @objc func newTab(_ sender: Any?) {
        tabList.newTab()
        refreshTabBar()
        rebuildSurfaceNodeView()
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    /// Close the active tab.  No-op if it is the only tab.  Key equivalent: ⇧⌘W.
    @objc func closeTab(_ sender: Any?) {
        tabList.closeTab(at: tabList.activeIndex)
        refreshTabBar()
        rebuildSurfaceNodeView()
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    /// Switch to the next tab, wrapping.  Key equivalent: ⌘}.
    @objc func selectNextTab(_ sender: Any?) {
        tabList.selectNext()
        refreshTabBar()
        rebuildSurfaceNodeView()
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    /// Switch to the previous tab, wrapping.  Key equivalent: ⌘{.
    @objc func selectPreviousTab(_ sender: Any?) {
        tabList.selectPrevious()
        refreshTabBar()
        rebuildSurfaceNodeView()
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    // MARK: - Private helper

    private func selectTab(at index: Int) {
        tabList.select(index: index)
        refreshTabBar()
        rebuildSurfaceNodeView()
        if let focused = focusedTerminalView() {
            view.window?.makeFirstResponder(focused)
        }
    }

    // MARK: - First-responder observation

    /// Starts (or restarts) KVO on `window.firstResponder`.
    ///
    /// When the first responder changes we walk its superview chain looking for
    /// a terminal view we recognise from the registry.  Finding one means the
    /// user clicked into that pane, so we update `paneTree.focusedSurfaceID`
    /// and redraw the focus highlights.
    private func startObservingFirstResponder() {
        guard let window = view.window else { return }
        firstResponderObservation = window.observe(
            \.firstResponder,
            options: [.new]
        ) { [weak self] _, _ in
            // observe is called on whatever thread AppKit uses; bounce to main.
            DispatchQueue.main.async {
                self?.handleFirstResponderChange()
            }
        }
    }

    private func handleFirstResponderChange() {
        guard let responder = view.window?.firstResponder as? NSView else { return }
        // Walk the superview chain of the new first responder to find which
        // registry view it belongs to (the terminal view itself, or a child of it).
        if let surfaceID = registry.surfaceID(containing: responder) {
            focusChanged(surfaceID: surfaceID)
        }
    }

    // MARK: - Tree rendering

    /// Replaces the root content view with a freshly-built `SurfaceNodeView`
    /// derived from `paneTree.layout.root`.
    ///
    /// After building, prunes the registry to the UNION of surface IDs across
    /// ALL tabs — background tabs keep their live PTY sessions alive.
    ///
    /// Declared `internal` so the `PaneActions` extension (same module) can call it.
    func rebuildSurfaceNodeView() {
        rootContentView?.removeFromSuperview()

        let newRoot = SurfaceNodeView(
            node: paneTree.layout.root,
            registry: registry,
            focusedSurfaceID: paneTree.focusedSurfaceID
        )
        newRoot.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newRoot)

        // Pin below the tab bar (28 pt), or to the top if there is no tab bar yet.
        let topGuide: NSLayoutYAxisAnchor
        if let tabBar = tabBarView {
            topGuide = tabBar.bottomAnchor
        } else {
            topGuide = view.topAnchor
        }

        NSLayoutConstraint.activate([
            newRoot.topAnchor.constraint(equalTo: topGuide),
            newRoot.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newRoot.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            newRoot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        rootContentView = newRoot

        // Prune to the union of all tabs' surfaces so background sessions survive.
        let allIDs = Set(tabList.trees.flatMap { $0.layout.surfaces.map(\.id) })
        registry.prune(keeping: allIDs)
    }

    // MARK: - Helpers

    /// Returns the `NSView` for the currently focused surface, if any.
    /// Declared `internal` so the `PaneActions` extension (same module) can call it.
    func focusedTerminalView() -> NSView? {
        guard let surface = paneTree.focusedSurface else { return nil }
        return registry.terminalView(for: surface)
    }

    // MARK: - Focus tracking

    /// Called whenever the KVO observer detects a first-responder change to a
    /// known terminal view.
    ///
    /// Updates `paneTree.focusedSurfaceID` and re-renders so the focus
    /// highlight moves to the newly focused leaf.
    private func focusChanged(surfaceID: UUID) {
        guard paneTree.focusedSurfaceID != surfaceID else { return }
        paneTree.focus(surfaceID)
        rebuildSurfaceNodeView()
        // No need to re-observe: the KVO target is the (unchanged) window, and
        // rebuildSurfaceNodeView only swaps the view hierarchy.
    }
}
