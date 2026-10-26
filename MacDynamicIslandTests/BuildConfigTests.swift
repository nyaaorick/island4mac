import XCTest
@testable import MacDynamicIsland

final class BuildConfigTests: XCTestCase {

    /// Tests run in the dev app (the Debug configuration), which keeps its files apart from the installed release's
    func testADevBuildKeepsItsFilesApart() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.macdynamicisland.app.dev")
        XCTAssertTrue(BuildConfig.isDevBuild)
        XCTAssertEqual(PluginStore.defaultFolder.deletingLastPathComponent().lastPathComponent, "MacDynamicIsland Dev")
        XCTAssertEqual(PluginStore.defaultDataFolder.deletingLastPathComponent().lastPathComponent, "MacDynamicIsland Dev")
    }
}
