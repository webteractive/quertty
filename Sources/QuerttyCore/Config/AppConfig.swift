import Foundation

// MARK: - AppearanceMode

/// How quertty chooses its color scheme.
///
/// - `system`: follow the macOS appearance — use `themeDark` when the OS is
///   dark, `themeLight` when it is light, and switch live when the user toggles.
/// - `dark`: always use `themeDark`.
/// - `light`: always use `themeLight`.
public enum AppearanceMode: String, Sendable, CaseIterable {
    case system
    case dark
    case light
}

// MARK: - AppConfig

/// User configuration, parsed from a ghostty-style plain-text file
/// (`key = value`, `#` comments). Unknown keys are ignored so the format can
/// grow without breaking older configs.
public struct AppConfig: Equatable, Sendable {

    public var appearance: AppearanceMode
    /// Scheme name used for the dark appearance (matched case-insensitively
    /// against the app's built-in scheme names).
    public var themeDark: String
    /// Scheme name used for the light appearance.
    public var themeLight: String

    public static let defaultThemeDark = "Midnight"
    public static let defaultThemeLight = "Daylight"

    public init(
        appearance: AppearanceMode = .system,
        themeDark: String = AppConfig.defaultThemeDark,
        themeLight: String = AppConfig.defaultThemeLight
    ) {
        self.appearance = appearance
        self.themeDark = themeDark
        self.themeLight = themeLight
    }

    // MARK: Parsing

    /// Parses ghostty-style config text.
    ///
    /// Rules: one `key = value` per line; text after `#` is a comment; blank
    /// lines are skipped; keys are case-insensitive; values are trimmed. A
    /// missing key keeps its default; an unrecognized `appearance` value keeps
    /// the default (`.system`); unknown keys are ignored.
    public static func parse(_ text: String) -> AppConfig {
        var config = AppConfig()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let eq = trimmed.firstIndex(of: "=") else { continue }

            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            switch key {
            case "appearance":
                if let mode = AppearanceMode(rawValue: value.lowercased()) {
                    config.appearance = mode
                }
            case "theme-dark":
                config.themeDark = value
            case "theme-light":
                config.themeLight = value
            default:
                break
            }
        }
        return config
    }

    // MARK: Default file

    /// The documented starter config written on first launch.
    public static let defaultFileContents = """
    # quertty configuration
    # Plain text, one `key = value` per line. Text after # is a comment.

    # Appearance mode: system | dark | light
    #   system -> follow the macOS appearance (uses theme-dark or theme-light)
    #   dark   -> always use theme-dark
    #   light  -> always use theme-light
    appearance = system

    # Color scheme for each appearance.
    # Built-in schemes: Midnight, Nocturne, Frost, Twilight, Ember, Daylight, Paper
    theme-dark  = Midnight
    theme-light = Daylight

    """
}
