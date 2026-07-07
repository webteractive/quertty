import XCTest
@testable import ZettyCore

final class UpdateAssetsTests: XCTestCase {
    private func asset(_ name: String) -> ReleaseAsset {
        ReleaseAsset(name: name, downloadURL: URL(string: "https://example.com/\(name)")!)
    }

    func testSelectsDMGAndChecksum() {
        let assets = [asset("notes.txt"), asset("Zetty-0.1.11.dmg"), asset("Zetty-0.1.11.dmg.sha256")]
        let picked = UpdateAssets.select(from: assets)
        XCTAssertEqual(picked.dmg?.lastPathComponent, "Zetty-0.1.11.dmg")
        XCTAssertEqual(picked.checksum?.lastPathComponent, "Zetty-0.1.11.dmg.sha256")
    }

    func testChecksumNotMistakenForDMG() {
        // ".dmg.sha256" must not be picked as the dmg.
        let picked = UpdateAssets.select(from: [asset("Zetty-0.1.11.dmg.sha256")])
        XCTAssertNil(picked.dmg)
        XCTAssertEqual(picked.checksum?.lastPathComponent, "Zetty-0.1.11.dmg.sha256")
    }

    func testMissingAssets() {
        let picked = UpdateAssets.select(from: [asset("readme.md")])
        XCTAssertNil(picked.dmg)
        XCTAssertNil(picked.checksum)
    }
}
