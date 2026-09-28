import XCTest
@testable import MacDynamicIsland

final class SwipeTrackerTests: XCTestCase {

    func testALongVerticalSwipeFiresOnceInItsDirection() {
        var tracker = SwipeTracker()
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 0, dy: 10), "not far enough yet")
        XCTAssertEqual(tracker.add(dx: 0, dy: 20), .down)
        XCTAssertNil(tracker.add(dx: 0, dy: 40), "the rest of the same swipe does nothing")

        tracker.begin()
        XCTAssertEqual(tracker.add(dx: 0, dy: -30), .up, "a new swipe fires again")
    }

    func testAShortSwipeDoesNotFire() {
        var tracker = SwipeTracker()
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 0, dy: SwipeTracker.distance - 1))
    }

    func testASidewaysSwipeDoesNotFire() {
        var tracker = SwipeTracker()
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 60, dy: 30), "mostly horizontal")
        XCTAssertNil(tracker.add(dx: 60, dy: 5))
    }

    func testMovementBackAndForthCancelsOut() {
        var tracker = SwipeTracker()
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 0, dy: 20))
        XCTAssertNil(tracker.add(dx: 0, dy: -18))
        XCTAssertNil(tracker.add(dx: 0, dy: 20))
    }

    func testTheZoneIsTheTopCenterThirdOfTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let island = CGRect(x: 800, y: 1160, width: 200, height: 40)
        let zone = SwipeZone.rect(on: screen, covering: island)
        XCTAssertEqual(zone, CGRect(x: 600, y: 800, width: 600, height: 400))
        XCTAssertTrue(zone.contains(CGPoint(x: 900, y: 1199)), "on the notch")
        XCTAssertTrue(zone.contains(CGPoint(x: 650, y: 850)), "well below and beside it")
        XCTAssertFalse(zone.contains(CGPoint(x: 300, y: 1100)), "toward the left edge")
        XCTAssertFalse(zone.contains(CGPoint(x: 900, y: 500)), "the middle of the screen")
    }

    func testTheZoneFollowsTheDisplayItIsOn() {
        let external = CGRect(x: 1800, y: -200, width: 2400, height: 1350)
        let zone = SwipeZone.rect(on: external, covering: CGRect(x: 2900, y: 1110, width: 200, height: 40))
        XCTAssertTrue(zone.contains(CGPoint(x: 3000, y: 1000)))
        XCTAssertFalse(zone.contains(CGPoint(x: 900, y: 1100)), "on the other display")
    }

    func testAnIslandWiderThanTheZoneStillCountsInFull() {
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let wide = CGRect(x: 400, y: 1000, width: 1000, height: 200)
        XCTAssertTrue(SwipeZone.rect(on: screen, covering: wide).contains(CGPoint(x: 420, y: 1100)))
    }

    func testBeginDiscardsWhatWasAddedBefore() {
        var tracker = SwipeTracker()
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 0, dy: 20))
        tracker.begin()
        XCTAssertNil(tracker.add(dx: 0, dy: 20), "the earlier 20 points don't carry over")
    }
}
