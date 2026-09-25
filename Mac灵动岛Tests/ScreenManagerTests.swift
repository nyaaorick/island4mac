import XCTest
@testable import Mac灵动岛

final class ScreenManagerTests: XCTestCase {

    private let builtIn: CGDirectDisplayID = 1
    private let external: CGDirectDisplayID = 2

    func testFollowsTheMouseOntoAnExternalDisplay() {
        // The built-in display has the notch, but the cursor is on the external one
        let display = ScreenManager.islandDisplay(
            followsMouse: true, mouseDisplay: external, currentDisplay: builtIn,
            chosenDisplay: nil, builtInDisplay: builtIn, mainDisplay: builtIn
        )
        XCTAssertEqual(display, external)
    }

    func testStaysPutWhenTheMouseIsOnNoDisplay() {
        let display = ScreenManager.islandDisplay(
            followsMouse: true, mouseDisplay: nil, currentDisplay: external,
            chosenDisplay: nil, builtInDisplay: builtIn, mainDisplay: builtIn
        )
        XCTAssertEqual(display, external)
    }

    func testStaysOnTheBuiltInDisplayWhenNotFollowingTheMouse() {
        let display = ScreenManager.islandDisplay(
            followsMouse: false, mouseDisplay: external, currentDisplay: external,
            chosenDisplay: nil, builtInDisplay: builtIn, mainDisplay: external
        )
        XCTAssertEqual(display, builtIn)
    }

    func testUsesTheMainDisplayWithTheLidClosed() {
        let display = ScreenManager.islandDisplay(
            followsMouse: false, mouseDisplay: nil, currentDisplay: nil,
            chosenDisplay: nil, builtInDisplay: nil, mainDisplay: external
        )
        XCTAssertEqual(display, external)
    }

    func testUsesTheChosenDisplayWhileItIsConnected() {
        let display = ScreenManager.islandDisplay(
            followsMouse: false, mouseDisplay: builtIn, currentDisplay: builtIn,
            chosenDisplay: external, builtInDisplay: builtIn, mainDisplay: builtIn
        )
        XCTAssertEqual(display, external)
        XCTAssertEqual(ScreenManager.islandDisplay(
            followsMouse: false, mouseDisplay: nil, currentDisplay: external,
            chosenDisplay: nil, builtInDisplay: builtIn, mainDisplay: external
        ), builtIn, "the chosen display unplugged: back on the built-in display")
    }

    func testFollowingTheMouseOverridesTheChosenDisplay() {
        let display = ScreenManager.islandDisplay(
            followsMouse: true, mouseDisplay: builtIn, currentDisplay: external,
            chosenDisplay: external, builtInDisplay: builtIn, mainDisplay: external
        )
        XCTAssertEqual(display, builtIn)
    }

    func testAllScreensPutsAnIslandOnEveryOtherDisplay() {
        XCTAssertEqual(ScreenManager.otherIslandDisplays(allScreens: true, displays: [builtIn, external], primary: external), [builtIn])
        XCTAssertEqual(ScreenManager.otherIslandDisplays(allScreens: false, displays: [builtIn, external], primary: external), [])
    }

    func testTheTopEdgeOfAScreenCountsAsOnIt() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        XCTAssertTrue(ScreenManager.frame(screen, contains: CGPoint(x: 735, y: 956)), "the cursor at the notch reports y == maxY")
        XCTAssertFalse(ScreenManager.frame(screen, contains: CGPoint(x: 735, y: 957)))
    }
}
