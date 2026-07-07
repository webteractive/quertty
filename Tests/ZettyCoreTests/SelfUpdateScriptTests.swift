import XCTest
@testable import ZettyCore

final class SelfUpdateScriptTests: XCTestCase {
    func testRendersQuotedPathsAndPID() {
        let script = SelfUpdateScript.render(
            pid: 4242,
            targetAppPath: "/Applications/zetty.app",
            stagedAppPath: "/tmp/z work/zetty.app",
            workDir: "/tmp/z work")
        XCTAssertTrue(script.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(script.contains("kill -0 4242"))
        XCTAssertTrue(script.contains("ditto '/tmp/z work/zetty.app' '/Applications/zetty.app'"))
        XCTAssertTrue(script.contains("rm -rf '/Applications/zetty.app'"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine '/Applications/zetty.app'"))
        XCTAssertTrue(script.contains("open '/Applications/zetty.app'"))
        XCTAssertTrue(script.contains(#"rm -- "$0""#))
    }

    func testEscapesSingleQuotesInPaths() {
        let script = SelfUpdateScript.render(
            pid: 1, targetAppPath: "/x/it's.app", stagedAppPath: "/s/a.app", workDir: "/s")
        XCTAssertTrue(script.contains(#"'/x/it'\''s.app'"#))
    }
}
