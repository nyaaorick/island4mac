import XCTest
@testable import MacDynamicIsland

final class UpdateClientTests: XCTestCase {

    func testVersionsCompareByNumber() {
        XCTAssertTrue(UpdateClient.isVersion("1.10.0", newerThan: "1.9.3"))
        XCTAssertTrue(UpdateClient.isVersion("v1.2.0", newerThan: "1.1.9"))
        XCTAssertTrue(UpdateClient.isVersion("2", newerThan: "1.99"))
        XCTAssertFalse(UpdateClient.isVersion("1.2", newerThan: "1.2.0"))
        // Never offer a downgrade, or something that isn't a version
        XCTAssertFalse(UpdateClient.isVersion("1.1.0", newerThan: "1.2.0"))
        XCTAssertFalse(UpdateClient.isVersion("1.3.0-beta", newerThan: "1.2.0"))
        XCTAssertFalse(UpdateClient.isVersion("1.3.0", newerThan: "dev"))
    }

    func testAReleaseReadsFromGitHubsAnswer() throws {
        let json = #"""
        {"tag_name":"v1.2.0","html_url":"https://github.com/nyaaorick/island4mac/releases/tag/v1.2.0","assets":[
          {"name":"notes.txt","browser_download_url":"https://github.com/nyaaorick/island4mac/releases/download/v1.2.0/notes.txt"},
          {"name":"island4mac.dmg","browser_download_url":"https://github.com/nyaaorick/island4mac/releases/download/v1.2.0/island4mac.dmg"}]}
        """#
        XCTAssertEqual(try UpdateClient.release(from: Data(json.utf8)), UpdateClient.Release(
            version: "1.2.0",
            download: URL(string: "https://github.com/nyaaorick/island4mac/releases/download/v1.2.0/island4mac.dmg")!,
            page: URL(string: "https://github.com/nyaaorick/island4mac/releases/tag/v1.2.0")!))
    }

    func testAReleaseWithoutAnHTTPSDMGIsNone() throws {
        let noDMG = #"{"tag_name":"v1.2.0","html_url":"https://github.com/x/y","assets":[]}"#
        XCTAssertNil(try UpdateClient.release(from: Data(noDMG.utf8)))
        let http = #"{"tag_name":"v1.2.0","html_url":"https://github.com/x/y","assets":[{"name":"a.dmg","browser_download_url":"http://example.com/a.dmg"}]}"#
        XCTAssertNil(try UpdateClient.release(from: Data(http.utf8)))
    }
}
