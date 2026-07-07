import Foundation

/// Renders the detached POSIX-sh helper that performs the in-place bundle swap
/// after the app quits. Pure text generation; the App layer writes and launches
/// it. A running app can't overwrite itself, so this waits for the PID first.
public enum SelfUpdateScript {
    public static func render(
        pid: Int32, targetAppPath: String, stagedAppPath: String, workDir: String
    ) -> String {
        func q(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return """
        #!/bin/sh
        # Zetty self-update helper (generated). Waits for the app to quit, swaps
        # the bundle in place, strips quarantine, relaunches, and self-deletes.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(targetAppPath))
        ditto \(q(stagedAppPath)) \(q(targetAppPath))
        xattr -dr com.apple.quarantine \(q(targetAppPath)) 2>/dev/null || true
        rm -rf \(q(workDir))
        open \(q(targetAppPath))
        rm -- "$0"
        """
    }
}
