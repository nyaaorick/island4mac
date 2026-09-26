import XCTest
@testable import Mac灵动岛

@MainActor
final class FullScreenVideoTests: XCTestCase {

    /// The built-in display with its notch, and an external display to its right, in AppKit's coordinates
    private let builtIn = DisplayArea(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32)
    private let external = DisplayArea(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), notchHeight: 0)

    func testAWindowFillingTheWholeDisplay() {
        XCTAssertEqual(external.coverage(by: external.frame), .whole, "a video in full screen")
        XCTAssertEqual(builtIn.coverage(by: builtIn.frame), .whole, "a player using the space beside the notch too")
        XCTAssertEqual(external.coverage(by: external.frame.insetBy(dx: 0.5, dy: 0.5)), .whole, "rounding doesn't matter")
    }

    func testFullScreenOnTheBuiltInDisplayStaysBelowTheNotch() {
        let belowNotch = CGRect(x: 0, y: 0, width: 1512, height: 982 - 32)
        XCTAssertEqual(builtIn.coverage(by: belowNotch), .belowNotch,
                       "in full screen, or zoomed with the Dock hidden: Accessibility tells which")
        XCTAssertEqual(external.coverage(by: belowNotch), .none, "on the other display")
    }

    func testWindowsThatLeaveTheMenuBarShowing() {
        XCTAssertEqual(external.coverage(by: CGRect(x: 1512, y: 0, width: 1920, height: 1080 - 24)), .none,
                       "zoomed, below the menu bar")
        XCTAssertEqual(external.coverage(by: CGRect(x: 1600, y: 100, width: 1200, height: 800)), .none, "an ordinary window")
        XCTAssertEqual(builtIn.coverage(by: CGRect(x: 0, y: 80, width: 1512, height: 982 - 32 - 80)), .none,
                       "zoomed above the Dock")
    }

    func testTheIslandIsNeverAVideo() {
        // The test host's own windows are the islands, floating above ordinary windows
        let own = ProcessInfo.processInfo.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        XCTAssertEqual(FullScreenVideo.displays(showing: [own], in: FullScreenVideo.displayAreas(), primaryHeight: primaryHeight), [])
        XCTAssertEqual(FullScreenVideo.displays(showing: [], in: FullScreenVideo.displayAreas(), primaryHeight: primaryHeight), [])
    }
}
