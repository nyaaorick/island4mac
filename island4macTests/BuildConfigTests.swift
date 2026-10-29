import XCTest
@testable import island4mac

final class BuildConfigTests: XCTestCase {

    /// Tests run in the dev app (the Debug configuration), which keeps its files apart from the installed release's
    func testADevBuildKeepsItsFilesApart() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.nyaaorick.island4mac.dev")
        XCTAssertTrue(BuildConfig.isDevBuild)
        XCTAssertEqual(PluginStore.defaultFolder.deletingLastPathComponent().lastPathComponent, "island4mac Dev")
        XCTAssertEqual(PluginStore.defaultDataFolder.deletingLastPathComponent().lastPathComponent, "island4mac Dev")
    }
}
