import Foundation

/// Pure precedence helper for tab display titles.
/// Determines which title source to use based on availability and precedence:
/// 1. Non-empty, trimmed `manualTitle`
/// 2. Non-empty last path component of `workingDir` (the pwd — the default)
/// 3. Non-empty, trimmed `focusedSurfaceTitle` (fallback when there is no pwd)
/// 4. Positional fallback: `"Tab \(index + 1)"`
public enum TabTitle {
    public static func display(
        manualTitle: String?,
        focusedSurfaceTitle: String?,
        workingDir: String?,
        index: Int
    ) -> String {
        // Try manualTitle
        if let title = manualTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }

        // Default to the pwd basename (skip empty/whitespace and the root "/").
        if let path = workingDir {
            let component = URL(fileURLWithPath: path).lastPathComponent
                .trimmingCharacters(in: .whitespaces)
            if !component.isEmpty, component != "/" {
                return component
            }
        }

        // Fall back to the terminal-reported title when there is no usable pwd.
        if let title = focusedSurfaceTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            return title
        }

        // Positional fallback
        return "Tab \(index + 1)"
    }
}
