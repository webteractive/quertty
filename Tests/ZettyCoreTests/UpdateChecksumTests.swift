import XCTest
@testable import ZettyCore

final class UpdateChecksumTests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(UpdateChecksum.sha256Hex(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(UpdateChecksum.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMatchesIgnoresCaseAndWhitespace() {
        let data = Data("abc".utf8)
        XCTAssertTrue(UpdateChecksum.matches(data: data,
            publishedHex: "  BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD\n"))
        XCTAssertFalse(UpdateChecksum.matches(data: data, publishedHex: "deadbeef"))
        XCTAssertFalse(UpdateChecksum.matches(data: data, publishedHex: "   "))
    }
}
