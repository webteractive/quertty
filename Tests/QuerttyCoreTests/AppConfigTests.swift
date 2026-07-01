import Foundation
import Testing
@testable import QuerttyCore

@Test func configDefaultsWhenEmpty() {
    let c = AppConfig.parse("")
    #expect(c.appearance == .system)
    #expect(c.themeDark == "Midnight")
    #expect(c.themeLight == "Daylight")
}

@Test func configParsesAllKeys() {
    let text = """
    appearance = dark
    theme-dark = Twilight
    theme-light = Frost
    """
    let c = AppConfig.parse(text)
    #expect(c.appearance == .dark)
    #expect(c.themeDark == "Twilight")
    #expect(c.themeLight == "Frost")
}

@Test func configIgnoresCommentsAndBlankLines() {
    let text = """
    # a comment
    appearance = light   # inline comment kept out of the value

      theme-dark = Ember

    # trailing comment
    """
    let c = AppConfig.parse(text)
    #expect(c.appearance == .light)
    #expect(c.themeDark == "Ember")
    #expect(c.themeLight == "Daylight") // untouched → default
}

@Test func configKeysAreCaseInsensitiveAndTrimmed() {
    let text = "  APPEARANCE  =  Dark  \n THEME-DARK = Nocturne "
    let c = AppConfig.parse(text)
    #expect(c.appearance == .dark)
    #expect(c.themeDark == "Nocturne")
}

@Test func configUnknownKeysAndBadAppearanceIgnored() {
    let text = """
    appearance = neon
    font-size = 14
    theme-dark = Frost
    """
    let c = AppConfig.parse(text)
    #expect(c.appearance == .system)   // "neon" invalid → default
    #expect(c.themeDark == "Frost")    // valid key still applied
}

@Test func configStoreSeedsAndReloadsFromDisk() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("quertty-config-test-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("config")
    defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

    let store = ConfigStore(fileURL: tmp)
    // First load: file missing → defaults returned and default file seeded.
    let first = store.load()
    #expect(first == AppConfig())
    #expect(FileManager.default.fileExists(atPath: tmp.path))

    // The seeded file must itself parse back to the defaults.
    let seeded = AppConfig.parse(try String(contentsOf: tmp, encoding: .utf8))
    #expect(seeded == AppConfig())

    // A user edit is read back on the next load.
    try "appearance = light\ntheme-light = Paper".write(to: tmp, atomically: true, encoding: .utf8)
    #expect(store.load().appearance == .light)
}
