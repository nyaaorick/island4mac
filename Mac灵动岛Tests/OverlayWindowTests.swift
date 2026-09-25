import XCTest
@testable import Mac灵动岛

/// The island animates entirely in SwiftUI on a fixed-size canvas; the panel is only resized
/// around it. These tests pin down that choreography.
@MainActor
final class OverlayWindowTests: XCTestCase {

    /// Longer than OverlayWindowController's settle delay for the close spring
    private let settleTime: TimeInterval = 0.8

    /// Keep the main run loop turning so the panel's delayed shrink can run
    private func runMainLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func islandPanel() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0 is OverlayPanel }, "the test host should have created the island panel")
    }

    /// Screen rect of the SwiftUI canvas, the panel's only subview
    private func canvasOnScreen(_ panel: NSWindow) throws -> NSRect {
        let canvas = try XCTUnwrap(panel.contentView?.subviews.first)
        return panel.convertToScreen(canvas.convert(canvas.bounds, to: nil))
    }

    private func assertEqual(_ a: NSRect, _ b: NSRect, _ message: String, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 0.5, message, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 0.5, message, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 0.5, message, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 0.5, message, line: line)
    }

    private func collapseAndSettle(_ state: AppState) {
        state.deactivateOverlay()
        runMainLoop(for: settleTime)
    }

    func testPanelGrowsBeforeOpeningAndShrinksAfterClosing() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        collapseAndSettle(state)
        let compact = panel.frame
        let canvas = try canvasOnScreen(panel)

        state.activateOverlay()
        // Already grown when SwiftUI renders the first frame of the open spring
        let open = panel.frame
        XCTAssertGreaterThan(open.width, compact.width)
        XCTAssertGreaterThan(open.height, compact.height)
        XCTAssertEqual(open.maxY, compact.maxY, accuracy: 0.5, "the island hangs from the top edge")
        XCTAssertEqual(open.midX, compact.midX, accuracy: 0.5, "the island stays centered")
        assertEqual(try canvasOnScreen(panel), canvas, "resizing the panel must not move the SwiftUI canvas")

        state.deactivateOverlay()
        assertEqual(panel.frame, open, "the panel keeps its size while the close spring runs")

        runMainLoop(for: settleTime)
        assertEqual(panel.frame, compact, "the panel shrinks back once the island has settled")
        assertEqual(try canvasOnScreen(panel), canvas, "shrinking the panel must not move the SwiftUI canvas")
    }

    func testReopeningWhileClosingCancelsTheShrink() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        collapseAndSettle(state)

        state.activateOverlay()
        let open = panel.frame
        state.deactivateOverlay()
        runMainLoop(for: 0.2)
        state.activateOverlay()

        runMainLoop(for: settleTime)
        assertEqual(panel.frame, open, "a pending shrink must not fire after the island reopened")

        collapseAndSettle(state)
    }

    func testCollapsedActivityGrowsOnlyToTheLeft() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        guard state.notchSize != .zero else { throw XCTSkip("needs a display with a notch") }
        collapseAndSettle(state)
        let compact = panel.frame
        let canvas = try canvasOnScreen(panel)

        AgentSessionStore.shared.apply(AgentHookEvent(kind: .userPromptSubmit, sessionID: "grows-left"))
        runMainLoop(for: 0.2)
        let live = panel.frame
        XCTAssertLessThan(live.minX, compact.minX, "the live activity grows left of the notch")
        XCTAssertEqual(live.maxX, compact.maxX, accuracy: 0.5, "nothing covers the menu bar icons right of the notch")
        assertEqual(try canvasOnScreen(panel), canvas, "an uneven panel must not move the SwiftUI canvas")

        AgentSessionStore.shared.archive("grows-left")
        runMainLoop(for: settleTime)
        assertEqual(panel.frame, compact, "the panel shrinks back once the activity is gone")
    }

    func testPausedMusicShowsOnlyWhileThePointerIsOnTheNotch() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        guard state.notchSize != .zero else { throw XCTSkip("needs a display with a notch") }
        let music = MusicManager.shared
        collapseAndSettle(state)
        let compact = panel.frame

        music.songTitle = "Test Song"
        music.isPlaying = true
        runMainLoop(for: 0.2)
        XCTAssertLessThan(panel.frame.minX, compact.minX, "playing: the artwork shows beside the notch")

        music.isPlaying = false
        runMainLoop(for: 1 + settleTime)
        assertEqual(panel.frame, compact, "paused: it folds away")

        state.isPeekingNotch = true
        runMainLoop(for: 0.2)
        XCTAssertLessThan(panel.frame.minX, compact.minX, "the pointer on the notch brings it back")

        state.isPeekingNotch = false
        runMainLoop(for: settleTime)
        assertEqual(panel.frame, compact, "and it folds away again when the pointer leaves")

        music.songTitle = ""
        runMainLoop(for: 0.2)
    }

    func testEachTabOpensToItsOwnSize() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        state.currentSection = .music
        collapseAndSettle(state)
        let canvas = try canvasOnScreen(panel)

        state.activateOverlay()
        let music = panel.frame

        state.currentSection = .clipboard
        // Already grown when SwiftUI renders the first frame of the larger tab
        let clipboard = panel.frame
        XCTAssertGreaterThan(clipboard.height, music.height, "the music tab is shorter than the clipboard tab")
        XCTAssertEqual(clipboard.width, music.width, accuracy: 0.5, "every tab is as wide, so the tab bar never moves")
        XCTAssertEqual(clipboard.maxY, music.maxY, accuracy: 0.5, "the island hangs from the top edge")
        XCTAssertEqual(clipboard.midX, music.midX, accuracy: 0.5, "the island stays centered")

        state.currentSection = .files
        XCTAssertGreaterThan(panel.frame.height, clipboard.height, "the files tab is the tallest")

        state.currentSection = .music
        runMainLoop(for: settleTime)
        assertEqual(panel.frame, music, "the panel shrinks back to the music tab once the island has settled")
        assertEqual(try canvasOnScreen(panel), canvas, "switching tabs must not move the SwiftUI canvas")

        collapseAndSettle(state)
    }
}
