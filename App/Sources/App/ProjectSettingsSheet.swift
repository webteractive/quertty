import AppKit
import ZettyCore

/// The per-project settings sheet (sidebar → Project Settings…). Programmatic
/// AppKit styled with ZTheme, following SettingsWindowController's idiom.
/// Purely an editor: reads a `ProjectSettings`, hands the edited copy to
/// `onSave` — persistence and re-application live in AppDelegate.
final class ProjectSettingsSheet: NSObject {

    /// Curated SF Symbols offered as project icons (plus "Default").
    static let iconChoices: [String] = [
        "folder", "terminal", "hammer", "wrench.and.screwdriver", "globe",
        "server.rack", "shippingbox", "book", "flask", "bolt",
    ]

    /// Keeps the active sheet (controls + closures) alive until it ends.
    private static var active: ProjectSettingsSheet?

    private let panel: NSWindow
    private let hostWindow: NSWindow
    private let onSave: (ProjectSettings) -> Void

    private let nameField: NSTextField
    private var swatchButtons: [NSButton] = []
    private var selectedColorID: String?
    private let iconPopup: NSPopUpButton
    private let preserveControl: NSSegmentedControl
    private let notifyControl: NSSegmentedControl

    static func present(
        for projectName: String,
        current: ProjectSettings,
        fallbackName: String,
        on window: NSWindow,
        onSave: @escaping (ProjectSettings) -> Void
    ) {
        let sheet = ProjectSettingsSheet(
            projectName: projectName, current: current,
            fallbackName: fallbackName, window: window, onSave: onSave)
        active = sheet
        window.beginSheet(sheet.panel)
    }

    private init(
        projectName: String,
        current: ProjectSettings,
        fallbackName: String,
        window: NSWindow,
        onSave: @escaping (ProjectSettings) -> Void
    ) {
        self.hostWindow = window
        self.onSave = onSave

        panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 0),
            styleMask: [.titled],
            backing: .buffered, defer: false)
        panel.title = "Project Settings — \(projectName)"
        panel.appearance = ZTheme.current.appearance
        panel.backgroundColor = ZTheme.current.bg1Color

        nameField = NSTextField(string: current.name ?? "")
        nameField.placeholderString = fallbackName
        nameField.font = ZTheme.monoFont(size: 13)

        selectedColorID = current.color

        iconPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        iconPopup.addItem(withTitle: "Default")
        for symbol in Self.iconChoices {
            iconPopup.addItem(withTitle: symbol)
            iconPopup.lastItem?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        }
        if let icon = current.icon, let index = Self.iconChoices.firstIndex(of: icon) {
            iconPopup.selectItem(at: index + 1)
        }

        func triState(_ value: Bool?) -> NSSegmentedControl {
            let control = NSSegmentedControl(
                labels: ["Follow Global", "On", "Off"],
                trackingMode: .selectOne, target: nil, action: nil)
            control.selectedSegment = value == nil ? 0 : (value == true ? 1 : 2)
            return control
        }
        preserveControl = triState(current.preserveSessionsOverride)
        notifyControl = triState(current.notificationsOverride)

        super.init()
        buildLayout()
    }

    private func buildLayout() {
        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 6
        let noneSwatch = makeSwatch(color: nil, tooltip: "Default")
        swatchButtons.append(noneSwatch)
        colorRow.addArrangedSubview(noneSwatch)
        for entry in ZTheme.projectPalette {
            // Appearance-reactive: show the variant the sidebar will use.
            let swatch = makeSwatch(color: ZTheme.projectColor(id: entry.id), tooltip: entry.id)
            swatchButtons.append(swatch)
            colorRow.addArrangedSubview(swatch)
        }
        refreshSwatchSelection()

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = ZTheme.monoFont(size: 13, weight: .medium)
            field.textColor = ZTheme.current.fgColor
            return field
        }
        func row(_ title: String, _ control: NSView) -> NSStackView {
            let stack = NSStackView(views: [label(title), NSView(), control])
            stack.orientation = .horizontal
            return stack
        }

        let content = NSStackView(views: [
            row("Name", nameField),
            row("Color", colorRow),
            row("Icon", iconPopup),
            row("Preserve Sessions", preserveControl),
            row("Notifications", notifyControl),
        ])
        content.orientation = .vertical
        content.spacing = 12
        content.alignment = .leading
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        for case let stack as NSStackView in content.views {
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal

        let root = NSStackView(views: [content, buttons])
        root.orientation = .vertical
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        panel.contentView = root
        panel.setContentSize(root.fittingSize)
        panel.initialFirstResponder = nameField
    }

    private func makeSwatch(color: NSColor?, tooltip: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(swatchClicked(_:)))
        button.isBordered = false
        button.wantsLayer = true
        button.toolTip = tooltip
        button.layer?.cornerRadius = 9
        button.layer?.borderColor = ZTheme.current.fgColor.cgColor
        button.layer?.backgroundColor = color?.cgColor ?? ZTheme.current.bg3Color.cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    private func refreshSwatchSelection() {
        for (index, button) in swatchButtons.enumerated() {
            let id: String? = index == 0 ? nil : ZTheme.projectPalette[index - 1].id
            button.layer?.borderWidth = (id == selectedColorID) ? 2 : 0
        }
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        guard let index = swatchButtons.firstIndex(of: sender) else { return }
        selectedColorID = index == 0 ? nil : ZTheme.projectPalette[index - 1].id
        refreshSwatchSelection()
    }

    private func triStateValue(_ control: NSSegmentedControl) -> Bool? {
        switch control.selectedSegment {
        case 1: true
        case 2: false
        default: nil
        }
    }

    @objc private func saveClicked() {
        var edited = ProjectSettings()
        let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        edited.name = trimmed.isEmpty ? nil : trimmed
        edited.color = selectedColorID
        edited.icon = iconPopup.indexOfSelectedItem > 0
            ? Self.iconChoices[iconPopup.indexOfSelectedItem - 1] : nil
        edited.preserveSessionsOverride = triStateValue(preserveControl)
        edited.notificationsOverride = triStateValue(notifyControl)
        hostWindow.endSheet(panel)
        Self.active = nil
        onSave(edited)
    }

    @objc private func cancelClicked() {
        hostWindow.endSheet(panel)
        Self.active = nil
    }
}
