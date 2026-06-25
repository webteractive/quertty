// Tests/QuerttyCoreTests/SmokeTests.swift
import XCTest
@testable import QuerttyCore

final class SmokeTests: XCTestCase {
    func testModuleHasVersion() {
        XCTAssertEqual(QuerttyCore.version, "0.0.1")
    }
}
