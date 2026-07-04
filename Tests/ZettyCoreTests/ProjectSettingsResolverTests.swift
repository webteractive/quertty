import Testing
@testable import ZettyCore

@Test func resolverFallsBackToGlobalsWhenUnset() {
    let global = AppConfig(preserveSessions: true, notifySound: true,
                           notifyBadge: false, notifySystem: true)
    let r = ProjectSettingsResolver.resolve(nil, fallbackName: "zetty", global: global)
    #expect(r.name == "zetty")
    #expect(r.colorID == nil)
    #expect(r.icon == nil)
    #expect(r.preserveSessions == true)
    #expect(r.notifySound == true)
    #expect(r.notifyBadge == false)   // follows each global channel individually
    #expect(r.notifySystem == true)
}

@Test func resolverAppliesNameOverrideUnlessBlank() {
    let global = AppConfig()
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(name: "API Server"), fallbackName: "api", global: global).name == "API Server")
    // Blank/whitespace override falls back — a cleared field means "no override".
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(name: "  "), fallbackName: "api", global: global).name == "api")
}

@Test func resolverPreserveSessionsTriState() {
    let globalOn = AppConfig(preserveSessions: true)
    let globalOff = AppConfig(preserveSessions: false)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(preserveSessionsOverride: false), fallbackName: "x", global: globalOn).preserveSessions == false)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(preserveSessionsOverride: true), fallbackName: "x", global: globalOff).preserveSessions == true)
    #expect(ProjectSettingsResolver.resolve(
        ProjectSettings(), fallbackName: "x", global: globalOn).preserveSessions == true)
}

@Test func resolverNotificationsTriState() {
    let global = AppConfig(notifySound: true, notifyBadge: false, notifySystem: true)
    // Off suppresses all three regardless of globals.
    let off = ProjectSettingsResolver.resolve(
        ProjectSettings(notificationsOverride: false), fallbackName: "x", global: global)
    #expect(off.notifySound == false && off.notifyBadge == false && off.notifySystem == false)
    // On forces all three regardless of globals.
    let on = ProjectSettingsResolver.resolve(
        ProjectSettings(notificationsOverride: true), fallbackName: "x", global: global)
    #expect(on.notifySound == true && on.notifyBadge == true && on.notifySystem == true)
    // nil follows each channel.
    let follow = ProjectSettingsResolver.resolve(
        ProjectSettings(), fallbackName: "x", global: global)
    #expect(follow.notifySound == true && follow.notifyBadge == false && follow.notifySystem == true)
}

@Test func resolverPassesAppearanceAndThemeOverridesThrough() {
    let unset = ProjectSettingsResolver.resolve(nil, fallbackName: "x", global: AppConfig())
    #expect(unset.appearanceOverride == nil)
    #expect(unset.themeDarkOverride == nil)
    #expect(unset.themeLightOverride == nil)
    let set = ProjectSettingsResolver.resolve(
        ProjectSettings(appearanceOverride: "light", themeDarkOverride: "Ember",
                        themeLightOverride: "Sakura"),
        fallbackName: "x", global: AppConfig())
    #expect(set.appearanceOverride == "light")
    #expect(set.themeDarkOverride == "Ember")
    #expect(set.themeLightOverride == "Sakura")
}

@Test func resolverReturnsEmptyEnvWhenUnsetAndMapWhenSet() {
    #expect(ProjectSettingsResolver.resolve(nil, fallbackName: "x", global: AppConfig()).env == [:])
    let resolved = ProjectSettingsResolver.resolve(
        ProjectSettings(env: ["A": "1"]), fallbackName: "x", global: AppConfig())
    #expect(resolved.env == ["A": "1"])
}
