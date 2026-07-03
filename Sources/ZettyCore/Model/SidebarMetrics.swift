import Foundation

/// Sidebar sizing rules shared by the app layer and persistence: the sidebar
/// is user-resizable between `minWidth` and `maxWidth`, defaulting to
/// `defaultWidth`. Restored/edited values are clamped so a stale or
/// hand-edited workspace file can't produce a broken layout.
public enum SidebarMetrics {
    public static let minWidth: Double = 180
    public static let maxWidth: Double = 420
    public static let defaultWidth: Double = 244

    public static func clampWidth(_ width: Double) -> Double {
        min(max(width, minWidth), maxWidth)
    }
}
