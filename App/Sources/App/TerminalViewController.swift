import AppKit
import GhosttyTerminal

// MARK: - TerminalViewController

/// Phase 0 spike: one full-window libghostty terminal pane.
///
/// Uses the package's high-level `TerminalView` (= `AppTerminalView` on
/// macOS) with the `.exec` backend, which spawns the user's `$SHELL` in a
/// real PTY — no ShellCraftKit sandbox shell.
///
/// Lifecycle note: `TerminalController` calls `ghostty_init(0, nil)`
/// internally via its own `initializeRuntimeIfNeeded()` guard, so
/// `Ghostty.initializeRuntime()` is intentionally not called here.
final class TerminalViewController: NSViewController {

    // MARK: - Subviews

    private lazy var terminalView: TerminalView = {
        let v = TerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        return v
    }()

    // MARK: - Terminal objects

    /// Shared controller — manages the ghostty app lifecycle, config, and
    /// surface creation. Calling `TerminalController()` triggers
    /// `initializeRuntimeIfNeeded()` which calls `ghostty_init` exactly once
    /// across the process.
    private lazy var controller: TerminalController = TerminalController()

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTerminalView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Hand keyboard focus to the terminal once the window is on screen.
        view.window?.makeFirstResponder(terminalView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        terminalView.fitToSize()
    }

    // MARK: - Setup

    private func setupTerminalView() {
        terminalView.delegate = self
        terminalView.setAccessibilityElement(true)
        terminalView.setAccessibilityIdentifier("quertty.terminal.surface")
        terminalView.setAccessibilityLabel("Terminal Surface")

        // .exec backend: libghostty spawns $SHELL in a real PTY (not sandboxed).
        terminalView.configuration = TerminalSurfaceOptions(backend: .exec)
        terminalView.controller = controller
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - TerminalSurfaceViewDelegate

extension TerminalViewController:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceResizeDelegate,
    TerminalSurfaceCloseDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        view.window?.title = title.isEmpty ? "quertty" : title
    }

    func terminalDidResize(columns _: Int, rows _: Int) {}

    func terminalDidClose(processAlive _: Bool) {
        view.window?.close()
    }
}
