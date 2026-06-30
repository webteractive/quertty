import AppKit
import QuerttyCore
import QuerttyGhostty

// MARK: - SurfaceNodeView

/// Recursively renders a `SurfaceNode` tree as nested `NSSplitView`s.
///
/// - For `.leaf(surface)`: embeds the registry's persistent `TerminalView`
///   for that surface.  The view is never recreated across re-renders; the
///   registry guarantees identity, preserving the live PTY session.
///
/// - For `.split(direction, ratio, first, second)`: creates an `NSSplitView`
///   (`isVertical = direction == .vertical`), adds the two recursively-built
///   child views, and sets the divider position from `ratio` after layout.
///
/// Usage: build a new root `SurfaceNodeView` from `paneTree.layout.root`
/// whenever the tree changes.  Unchanged leaves share their persistent view
/// objects from the registry, so sibling terminals are unaffected by splits.
@MainActor
final class SurfaceNodeView: NSView {

    // MARK: - Init

    /// Build the view hierarchy for `node` using `registry`.
    init(node: SurfaceNode, registry: SurfaceRegistry) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildContent(node: node, registry: registry)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not supported") }

    // MARK: - Private

    private func buildContent(node: SurfaceNode, registry: SurfaceRegistry) {
        switch node {

        case .leaf(let surface):
            let terminalView = registry.terminalView(for: surface)
            terminalView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(terminalView)
            NSLayoutConstraint.activate([
                terminalView.topAnchor.constraint(equalTo: topAnchor),
                terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
                terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
                terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

        case .split(let direction, let ratio, let first, let second):
            let splitView = RatioSplitView(
                direction: direction,
                ratio: ratio,
                first: first,
                second: second,
                registry: registry
            )
            splitView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(splitView)
            NSLayoutConstraint.activate([
                splitView.topAnchor.constraint(equalTo: topAnchor),
                splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
                splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
                splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }
}

// MARK: - RatioSplitView

/// An `NSSplitView` that respects a `ratio` (0…1) for its single divider.
///
/// Because `setPosition(_:ofDividerAt:)` is only meaningful after the split
/// view has a non-zero frame, the ratio is applied in `layout()` on the first
/// pass where the bounds are non-empty.  Subsequent layout calls leave the
/// divider alone so user drags are preserved.
@MainActor
private final class RatioSplitView: NSSplitView {

    private let ratio: Double
    private var didSetInitialPosition = false

    init(
        direction: SplitDirection,
        ratio: Double,
        first: SurfaceNode,
        second: SurfaceNode,
        registry: SurfaceRegistry
    ) {
        self.ratio = ratio
        super.init(frame: .zero)
        isVertical = (direction == .vertical)
        dividerStyle = .thin

        let firstView = SurfaceNodeView(node: first, registry: registry)
        let secondView = SurfaceNodeView(node: second, registry: registry)
        addArrangedSubview(firstView)
        addArrangedSubview(secondView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        applyInitialRatioIfNeeded()
    }

    private func applyInitialRatioIfNeeded() {
        guard !didSetInitialPosition else { return }
        let dimension = isVertical ? bounds.width : bounds.height
        guard dimension > 0 else { return }
        didSetInitialPosition = true
        let position = dimension * ratio
        setPosition(position, ofDividerAt: 0)
    }
}
