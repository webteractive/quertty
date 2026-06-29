// LinkSmokeTests.swift — Task 5 smoke test
//
// Verifies that:
//   1. The QuerttyGhostty module links (import succeeds).
//   2. `ghostty_init(0, nil)` returns 0 and sets `Ghostty.isInitialized`.
//
// Uses Swift Testing (@Test / #expect), available natively in Xcode 16+.

import Testing
@testable import QuerttyGhostty

@Test func runtimeInitializesWithoutThrowing() throws {
    try Ghostty.initializeRuntime()
    #expect(Ghostty.isInitialized)
}

@Test func doubleInitIsIdempotent() throws {
    try Ghostty.initializeRuntime()
    try Ghostty.initializeRuntime()  // second call should be a no-op
    #expect(Ghostty.isInitialized)
}
