import Foundation

/// Watches a config file and fires `onChange` when it's modified on disk.
///
/// Uses a lightweight modification-date poll on the main run loop (1s) rather
/// than a DispatchSource vnode — it survives atomic saves (editors that
/// rename-replace the file) without re-arming, and stays on the main thread so
/// the callback can touch UI directly.
///
/// The app suppresses its own writes via `markSaved()` so persisting a runtime
/// change (scheme/appearance) doesn't bounce back as an external reload.
///
/// The poll timer lives on the main run loop, so `onChange` fires on the main
/// thread and can touch UI directly.
final class ConfigFileWatcher {

    private let url: URL
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastModified: Date?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        self.lastModified = modificationDate()
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Record the current mtime as the baseline — call right after the app
    /// writes the config itself, so the next poll doesn't see it as a change.
    func markSaved() {
        lastModified = modificationDate()
    }

    private func check() {
        let current = modificationDate()
        guard current != lastModified else { return }
        lastModified = current
        onChange()
    }

    private func modificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
