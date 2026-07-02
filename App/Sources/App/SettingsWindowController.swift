import AppKit
import QuerttyCore

/// A small themed Settings window. Currently hosts the **Agent Status Hooks**
/// section — a toggle per harness that installs/uninstalls quertty's status hook.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let installer: HookInstaller
    private var switches: [(harness: Harness, control: NSSwitch)] = []
    private let configURL = ConfigStore().fileURL

    init(installer: HookInstaller) {
        self.installer = installer
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.appearance = QTheme.current.appearance
        window.backgroundColor = QTheme.current.bg1Color
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Refreshes toggle states from disk each time the window is shown.
    func refresh() {
        for (harness, control) in switches {
            control.state = installer.isInstalled(harness) ? .on : .off
        }
    }

    // MARK: - Content

    private func buildContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = QTheme.current.bg1Color.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20),
        ])

        // Configuration section.
        stack.addArrangedSubview(sectionHeader("Configuration"))
        stack.addArrangedSubview(caption(abbreviatedConfigPath()))
        let openButton = NSButton(title: "Open in Editor", target: self, action: #selector(openConfig(_:)))
        openButton.bezelStyle = .rounded
        stack.addArrangedSubview(openButton)

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(sectionHeader("Agent Status Hooks"))
        stack.addArrangedSubview(caption(
            "Install a hook so the harness reports agent status to quertty. "
            + "Status shows as sidebar dots — green running, yellow needs-attention, dim idle."
        ))

        for harness in Harness.allCases {
            let (row, control) = harnessRow(harness)
            switches.append((harness, control))
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.addArrangedSubview(caption("Restart the agent after enabling for the hook to take effect."))
        refresh()
        return root
    }

    private func harnessRow(_ harness: Harness) -> (NSView, NSSwitch) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: harness.displayName)
        name.font = QTheme.monoFont(size: 13, weight: .medium)
        name.textColor = QTheme.current.fgColor
        name.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(switchToggled(_:))
        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(name)
        row.addSubview(toggle)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 28),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return (row, toggle)
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = QTheme.current.fgColor
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = QTheme.current.fg3Color
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        return label
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }

    private func abbreviatedConfigPath() -> String {
        let home = NSHomeDirectory()
        let path = configURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Actions

    /// Opens the config in Zed if installed, else the system default editor.
    @objc private func openConfig(_ sender: Any?) {
        ConfigStore(fileURL: configURL).writeDefaultIfMissing()
        if let zed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed") {
            NSWorkspace.shared.open([configURL], withApplicationAt: zed, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(configURL)
        }
    }

    @objc private func switchToggled(_ sender: NSSwitch) {
        guard let harness = switches.first(where: { $0.control === sender })?.harness else { return }
        let outcome = sender.state == .on ? installer.install(harness) : installer.uninstall(harness)
        switch outcome {
        case .installed, .uninstalled, .alreadyInstalled:
            break   // the switch already reflects the new state
        case let .conflict(snippet):
            sender.state = .off
            presentAlert(title: "\(harness.displayName): manual step needed",
                         message: "A hooks: block already exists in your config, so add these entries yourself:\n\n\(snippet)")
        case let .failed(message):
            sender.state = (sender.state == .on) ? .off : .on   // revert
            presentAlert(title: "\(harness.displayName) hook change failed", message: message, warning: true)
        }
    }

    private func presentAlert(title: String, message: String, warning: Bool = false) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if warning { alert.alertStyle = .warning }
        if let window { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}
