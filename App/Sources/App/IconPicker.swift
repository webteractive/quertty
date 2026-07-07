import AppKit

/// Shared rendering + classification for a project's chosen icon. The stored
/// icon string is either an SF Symbol name (ASCII) or an emoji (non-ASCII);
/// SF Symbols are template images tinted by the project/agent color, while
/// emoji are colored glyphs drawn as-is (no tint).
enum ProjectIcon {

    /// An icon string is an emoji when it carries any non-ASCII scalar —
    /// SF Symbol names are always ASCII identifiers.
    static func isEmoji(_ icon: String) -> Bool {
        icon.contains { !$0.isASCII }
    }

    /// Renders an emoji into a non-template (colored) image sized to fit the
    /// given point size. Non-template so `contentTintColor` leaves it alone.
    static func emojiImage(_ emoji: String, pointSize: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: pointSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let text = emoji as NSString
        let bounds = text.size(withAttributes: attrs)
        let size = NSSize(width: ceil(bounds.width), height: ceil(bounds.height))
        let image = NSImage(size: size)
        image.lockFocus()
        text.draw(at: .zero, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

/// An "Icon | Emoji" kind selector next to a preview button. The button opens
/// a grid popover for whichever kind is selected — SF Symbols or emoji — and
/// switching kinds reopens the matching grid. Purely a value editor: read
/// `selectedIcon` on save.
final class IconPickerControl: NSStackView {

    /// Curated SF Symbols offered as project icons. Names that aren't
    /// available on the running macOS are filtered out when the grid builds.
    static let symbolChoices: [String] = [
        "folder", "doc.text", "terminal", "chevron.left.forwardslash.chevron.right",
        "curlybraces", "hammer", "wrench.and.screwdriver", "gearshape", "cpu",
        "memorychip", "server.rack", "network", "cloud", "externaldrive", "lock",
        "key", "ant", "ladybug", "flask", "chart.bar", "chart.line.uptrend.xyaxis",
        "bolt", "sparkles", "wand.and.stars", "paintbrush", "paintpalette", "cube",
        "shippingbox", "book", "bookmark", "tag", "flag", "star", "heart", "leaf",
        "globe", "house", "building.2", "gamecontroller", "music.note", "camera",
        "brain",
    ]

    private(set) var selectedIcon: String?

    private enum Kind: Int { case icon = 0, emoji = 1 }

    private let kindControl = NSSegmentedControl(
        labels: ["Icon", "Emoji"], trackingMode: .selectOne, target: nil, action: nil)
    // Icon kind: preview button opens the SF Symbols grid popover.
    private let previewButton = NSButton()
    private var popover: NSPopover?
    // Emoji kind: a small field displays / receives the emoji (also the
    // insertion target for the native macOS emoji picker) + a Pick… button.
    private let customField = NSTextField()
    private let pickButton = NSButton()

    init(selected: String?) {
        selectedIcon = selected
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 8
        alignment = .centerY

        kindControl.selectedSegment = (selected.map(ProjectIcon.isEmoji) == true)
            ? Kind.emoji.rawValue : Kind.icon.rawValue
        kindControl.target = self
        kindControl.action = #selector(kindChanged)

        previewButton.bezelStyle = .rounded
        previewButton.imagePosition = .imageOnly
        previewButton.target = self
        previewButton.action = #selector(togglePopover)
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        previewButton.widthAnchor.constraint(equalToConstant: 48).isActive = true

        customField.placeholderString = "😀"
        customField.font = .systemFont(ofSize: 15)
        customField.alignment = .center
        customField.delegate = self
        customField.translatesAutoresizingMaskIntoConstraints = false
        customField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        pickButton.title = "Pick…"
        pickButton.bezelStyle = .rounded
        pickButton.font = ZTheme.chromeFont(size: 12)
        pickButton.target = self
        pickButton.action = #selector(openNativeEmojiPicker)

        addArrangedSubview(kindControl)
        addArrangedSubview(previewButton)
        addArrangedSubview(customField)
        addArrangedSubview(pickButton)
        updateKindVisibility()
        refreshPreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var kind: Kind { Kind(rawValue: kindControl.selectedSegment) ?? .icon }

    /// Icon kind uses the preview button + grid popover; emoji kind uses the
    /// field + native picker. Only one set of controls shows at a time.
    private func updateKindVisibility() {
        let isEmoji = kind == .emoji
        previewButton.isHidden = isEmoji
        customField.isHidden = !isEmoji
        pickButton.isHidden = !isEmoji
    }

    // MARK: - Preview

    /// Mirrors the current selection onto the visible control for its kind.
    private func refreshPreview() {
        customField.stringValue = (selectedIcon.map(ProjectIcon.isEmoji) == true) ? selectedIcon! : ""
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let icon = selectedIcon, !ProjectIcon.isEmoji(icon),
           let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: icon) {
            previewButton.image = symbol.withSymbolConfiguration(config)
        } else {
            previewButton.image = NSImage(systemSymbolName: "diamond", accessibilityDescription: "Default")?
                .withSymbolConfiguration(config)
        }
        previewButton.title = ""
        previewButton.imagePosition = .imageOnly
    }

    // MARK: - Kind switching

    @objc private func kindChanged() {
        updateKindVisibility()
        refreshPreview()
        popover?.close()
    }

    /// Opens macOS's native emoji picker, inserting into the emoji field.
    @objc private func openNativeEmojiPicker() {
        window?.makeFirstResponder(customField)
        NSApp.orderFrontCharacterPalette(customField)
    }

    // MARK: - Symbol grid popover

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.close()
        } else {
            showSymbolPopover()
        }
    }

    private func showSymbolPopover() {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = ZTheme.current.appearance
        popover.contentViewController = makeSymbolPopoverController()
        popover.show(relativeTo: previewButton.bounds, of: previewButton, preferredEdge: .maxY)
        self.popover = popover
    }

    /// The SF Symbols grid (plus a Default clear).
    private func makeSymbolPopoverController() -> NSViewController {
        let controller = NSViewController()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        root.addArrangedSubview(makeDefaultButton())
        root.addArrangedSubview(makeGrid(items: availableSymbols(), isEmoji: false))

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = ZTheme.current.bg1Color.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        controller.view = container
        return controller
    }

    /// SF Symbols that actually resolve on this macOS — an unavailable name
    /// would render blank, so drop it.
    private func availableSymbols() -> [String] {
        Self.symbolChoices.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    }

    private func makeDefaultButton() -> NSButton {
        let button = NSButton(title: "Default (diamond)", target: self, action: #selector(clearSelection))
        button.bezelStyle = .inline
        button.font = ZTheme.chromeFont(size: 12)
        button.contentTintColor = ZTheme.current.fg2Color
        return button
    }

    /// A wrapping grid of icon cells, 8 per row.
    private func makeGrid(items: [String], isEmoji: Bool) -> NSView {
        let columns = 8
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 4

        var row: NSStackView?
        for (index, item) in items.enumerated() {
            if index % columns == 0 {
                let newRow = NSStackView()
                newRow.orientation = .horizontal
                newRow.spacing = 4
                column.addArrangedSubview(newRow)
                row = newRow
            }
            row?.addArrangedSubview(makeCell(item, isEmoji: isEmoji))
        }
        return column
    }

    private func makeCell(_ item: String, isEmoji: Bool) -> NSButton {
        let cell = IconCellButton(icon: item, isEmoji: isEmoji, isSelected: item == selectedIcon)
        cell.target = self
        cell.action = #selector(cellClicked(_:))
        return cell
    }

    // MARK: - Actions

    @objc private func cellClicked(_ sender: IconCellButton) {
        selectedIcon = sender.icon
        refreshPreview()
        popover?.close()
    }

    @objc private func clearSelection() {
        selectedIcon = nil
        refreshPreview()
        popover?.close()
    }

    /// Adopts what landed in the emoji field — the first emoji grapheme the
    /// user picked/typed/pasted, or Default when they clear it. Doesn't
    /// rewrite the field mid-edit (that would fight the cursor).
    private func adoptCustomText() {
        let text = customField.stringValue
        if let first = text.first(where: { String($0).contains { !$0.isASCII } }) {
            selectedIcon = String(first)
        } else if text.isEmpty {
            selectedIcon = nil
        }
    }
}

extension IconPickerControl: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        adoptCustomText()
    }
}

/// A single square icon cell in the picker grid. Selected cells fill with the
/// `bg3` selection surface (never accent, per the design rules).
private final class IconCellButton: NSButton {
    let icon: String

    init(icon: String, isEmoji: Bool, isSelected: Bool) {
        self.icon = icon
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = isSelected
            ? ZTheme.current.bg3Color.cgColor : NSColor.clear.cgColor
        toolTip = isEmoji ? nil : icon
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        if isEmoji {
            title = icon
            font = .systemFont(ofSize: 17)
            imagePosition = .noImage
        } else {
            title = ""
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            image = NSImage(systemSymbolName: icon, accessibilityDescription: icon)?
                .withSymbolConfiguration(config)
            contentTintColor = ZTheme.current.fg2Color
            imagePosition = .imageOnly
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
