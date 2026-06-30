import AppKit

// MARK: - TabBarView

/// A horizontal strip of clickable segment buttons representing the open tabs.
///
/// Uses `NSSegmentedControl` in `.selectOne` mode so exactly one tab is always
/// selected.  Changes are reported back to the owner via the `onSelect` closure.
/// The tab *model* lives in `QuerttyCore.TabList`; this view only renders it.
@MainActor
final class TabBarView: NSView {

    // MARK: - Subviews

    private let segmented: NSSegmentedControl

    // MARK: - Callbacks

    /// Called with the tab index whenever the user clicks a segment.
    var onSelect: ((Int) -> Void)?

    /// Called when the user wants to add a new tab (+ button).
    var onNewTab: (() -> Void)?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        segmented = NSSegmentedControl()
        segmented.segmentStyle = .texturedSquare
        segmented.trackingMode = .selectOne
        segmented.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // "+" new-tab button
        let addButton = NSButton(title: "+", target: nil, action: nil)
        addButton.bezelStyle = .inline
        addButton.isBordered = false
        addButton.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        addButton.target = self
        addButton.action = #selector(addButtonClicked(_:))
        addButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(segmented)
        addSubview(addButton)

        segmented.target = self
        segmented.action = #selector(segmentChanged(_:))

        NSLayoutConstraint.activate([
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            segmented.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmented.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 2),
            segmented.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),

            addButton.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 6),
            addButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            addButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("not supported") }

    // MARK: - Update

    /// Rebuilds segments from `titles` and marks `selectedIndex` as selected.
    func update(titles: [String], selectedIndex: Int) {
        segmented.segmentCount = titles.count
        for (i, title) in titles.enumerated() {
            segmented.setLabel(title, forSegment: i)
            segmented.setWidth(0, forSegment: i)  // auto-width
        }
        if titles.indices.contains(selectedIndex) {
            segmented.selectedSegment = selectedIndex
        }
    }

    // MARK: - Actions

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let idx = sender.selectedSegment
        guard idx >= 0 else { return }
        onSelect?(idx)
    }

    @objc private func addButtonClicked(_: Any?) {
        onNewTab?()
    }
}
