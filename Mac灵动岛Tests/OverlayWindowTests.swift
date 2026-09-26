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

    /// The main island's panel: with "all screens" on there's one on every display
    private func islandPanel() throws -> NSWindow {
        OverlayWindowController.shared.mainPanel
    }

    private var visibleIslandPanels: [NSWindow] {
        NSApp.windows.filter { $0 is OverlayPanel && $0.isVisible }
    }

    func testAllScreensPutsAnIslandOnEveryDisplay() {
        let settings = SettingsDefaults.shared
        // The tests run inside the app, on its real settings
        let saved = settings.get(SettingsDefaults.showOnAllDisplays)
        defer {
            settings.set(SettingsDefaults.showOnAllDisplays, value: saved)
            runMainLoop(for: 0.2)
        }

        settings.set(SettingsDefaults.showOnAllDisplays, value: true)
        runMainLoop(for: 0.3)
        let displays = Set(visibleIslandPanels.compactMap { $0.screen?.displayID })
        XCTAssertEqual(visibleIslandPanels.count, NSScreen.screens.count)
        XCTAssertEqual(displays.count, NSScreen.screens.count, "one island on each display")

        settings.set(SettingsDefaults.showOnAllDisplays, value: false)
        runMainLoop(for: 0.3)
        XCTAssertEqual(visibleIslandPanels.count, 1, "back to the one island")
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

    func testWingsFitIntoTheRoomBesideTheNotch() {
        let notch = CGSize(width: 180, height: 32)
        let wing = NotchMetrics.wingWidth(for: notch)
        let margin = NotchMetrics.wingMargin
        func wings(_ left: CGFloat?, _ right: CGFloat?) -> IslandWings {
            NotchMetrics.liveActivityWings(leadingRoom: left, trailingRoom: right, notch: notch)
        }
        XCTAssertEqual(wings(nil, nil), IslandWings(leading: 2 * wing, trailing: 0),
                       "room unknown: both items left of the notch, clear of the status icons")
        XCTAssertEqual(wings(300, 300), IslandWings(leading: wing, trailing: wing), "room on both sides: one item each")
        XCTAssertEqual(wings(300, 28.5), IslandWings(leading: wing, trailing: 26), "a narrow gap before the status icons")
        XCTAssertEqual(wings(10, 20), IslandWings(leading: 0, trailing: 18), "Xcode: menus both sides, a sliver right of the notch")
        XCTAssertEqual(wings(10, 300), IslandWings(leading: 0, trailing: wing), "menus up to the notch: the status goes right")
        XCTAssertEqual(wings(300, 10), IslandWings(leading: 2 * wing, trailing: 0), "icons up to the notch: both go left")
        XCTAssertEqual(wings(wing + margin, 10), IslandWings(leading: wing, trailing: 0))
        XCTAssertEqual(wings(10, 10), .none, "no room anywhere: it stays inside the notch")

        let room = MenuBarSpace.room(beside: 645...825, obstacles: [0...40, 40...300, 594...618, 853...871, 877...913],
                                     displayWidth: 1470)
        XCTAssertEqual(room.leading, 27)
        XCTAssertEqual(room.trailing, 28)
        XCTAssertEqual(MenuBarSpace.room(beside: 645...825, obstacles: [40...620, 830...900], displayWidth: 1470).trailing, 5,
                       "menus that continue right of the notch count there")
        XCTAssertEqual(MenuBarSpace.room(beside: 645...825, obstacles: [], displayWidth: 1470).trailing, 645)

        // Folded-away icons stack on the chevron (853); the ones showing only touch their neighbours
        XCTAssertEqual(MenuBarSpace.visible([839...863, 839...863, 853...871, 877...913, 911...947]),
                       [853...871, 877...913, 911...947])
    }

    func testLiveActivityFitsIntoTheRoomBesideTheNotch() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        let notch = state.notchSize
        guard notch != .zero, let screen = panel.screen else { throw XCTSkip("needs a display with a notch") }
        let menuBar = MenuBarSpace.shared
        let wing = NotchMetrics.wingWidth(for: notch)
        let margin = NotchMetrics.wingMargin
        let notchMinX = (screen.frame.width - notch.width) / 2
        let notchMaxX = notchMinX + notch.width
        // A status icon in this display's menu bar, `gap` points right of the notch (global top-left coordinates)
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        func statusIcon(gap: CGFloat) -> CGRect {
            CGRect(x: screen.frame.minX + notchMaxX + gap, y: primaryHeight - screen.frame.maxY + 4, width: 24, height: 24)
        }
        collapseAndSettle(state)
        let compact = panel.frame

        AgentSessionStore.shared.apply(AgentHookEvent(kind: .userPromptSubmit, sessionID: "menus"))
        runMainLoop(for: 0.2)
        XCTAssertEqual(compact.minX - panel.frame.minX, 2 * wing, accuracy: 0.5, "room unknown: both items left of the notch")
        XCTAssertEqual(panel.frame.maxX, compact.maxX, accuracy: 0.5)

        menuBar.statusItemFrames = [statusIcon(gap: 28.5)]
        runMainLoop(for: settleTime)
        XCTAssertEqual(state.liveActivityWings, IslandWings(leading: wing, trailing: (28.5 - margin).rounded(.down)))
        XCTAssertEqual(compact.minX - panel.frame.minX, wing, accuracy: 0.5, "one item left of the notch")
        XCTAssertEqual(panel.frame.maxX - compact.maxX, (28.5 - margin).rounded(.down), accuracy: 0.5,
                       "and one right of it, up to the first status icon")

        menuBar.menuSpans = [0...40, 40...(notchMinX - 10)]
        runMainLoop(for: settleTime)
        XCTAssertEqual(state.liveActivityWings, IslandWings(leading: 0, trailing: (28.5 - margin).rounded(.down)),
                       "menus up to the notch: only the right wing")

        menuBar.statusItemFrames = [statusIcon(gap: 10)]
        runMainLoop(for: settleTime)
        assertEqual(panel.frame, compact, "no room on either side: it stays inside the notch")

        menuBar.menuSpans = nil
        menuBar.statusItemFrames = nil
        AgentSessionStore.shared.archive("menus")
        runMainLoop(for: settleTime)
        assertEqual(panel.frame, compact, "and it folds away once the session is gone")
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

    func testTheIslandIsWiderOnlyOnALargeExternalDisplay() {
        let notch = CGSize(width: 185, height: 32)
        XCTAssertTrue(NotchMetrics.isLargeDisplay(width: 1920, notch: .zero, isBuiltIn: false), "a 1080p monitor")
        XCTAssertTrue(NotchMetrics.isLargeDisplay(width: 2560, notch: .zero, isBuiltIn: false))
        XCTAssertFalse(NotchMetrics.isLargeDisplay(width: 1680, notch: .zero, isBuiltIn: false), "a smaller monitor")
        XCTAssertFalse(NotchMetrics.isLargeDisplay(width: 2056, notch: notch, isBuiltIn: true),
                       "the built-in display keeps its island, however much space it's set to show")
        XCTAssertFalse(NotchMetrics.isLargeDisplay(width: 2240, notch: .zero, isBuiltIn: true), "nor one without a notch")

        func width(expanded: Bool, section: AppState.IslandSection = .music, wings: IslandWings = .none, largeDisplay: Bool) -> CGFloat {
            NotchMetrics.islandSize(expanded: expanded, section: section, notch: .zero, wings: wings,
                                    largeDisplay: largeDisplay, nonNotchHeight: 32).width
        }
        // What a display without a notch gets while it shows now playing or an agent session
        let live = NotchMetrics.liveActivityWings(leadingRoom: nil, trailingRoom: nil, notch: .zero)
        XCTAssertFalse(live.isEmpty)
        XCTAssertEqual(width(expanded: false, largeDisplay: true), NotchMetrics.nonNotchWidth, "idle, the pill keeps its size")
        XCTAssertEqual(width(expanded: false, wings: live, largeDisplay: true), NotchMetrics.largeDisplayLiveActivityWidth,
                       "now playing, it widens for the whole title and lyric line")
        XCTAssertEqual(width(expanded: false, wings: live, largeDisplay: false), NotchMetrics.nonNotchWidth)
        for section in AppState.IslandSection.allCases {
            XCTAssertEqual(width(expanded: true, section: section, largeDisplay: true), NotchMetrics.largeDisplayExpandedWidth,
                           "every tab opens as wide, so the tab bar never moves")
            XCTAssertEqual(width(expanded: true, section: section, largeDisplay: false), NotchMetrics.expandedWidth)
        }
        XCTAssertEqual(NotchMetrics.canvasSize(notch: .zero, largeDisplay: true).width,
                       NotchMetrics.largeDisplayExpandedWidth + 2 * NotchMetrics.overshootMargin, "the canvas holds the wider island")
    }

    func testTheIslandOpensAsWideAsItsDisplayAllows() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        collapseAndSettle(state)
        let screen = try XCTUnwrap(panel.screen)
        XCTAssertEqual(state.isOnLargeDisplay, screen.isLargeDisplay)
        if screen.hasNotch {
            XCTAssertFalse(state.isOnLargeDisplay, "the island under the notch stays as it is")
        }

        state.activateOverlay()
        let open = state.isOnLargeDisplay ? NotchMetrics.largeDisplayExpandedWidth : NotchMetrics.expandedWidth
        XCTAssertEqual(panel.frame.width, open + 2 * NotchMetrics.overshootMargin, accuracy: 0.5)

        collapseAndSettle(state)
    }

    func testTheLiveActivityPillWidensOnALargeDisplay() throws {
        let state = OverlayWindowController.shared.getAppState()
        let panel = try islandPanel()
        guard state.isOnLargeDisplay, let screen = panel.screen else { throw XCTSkip("needs the island on a large external display") }
        collapseAndSettle(state)
        XCTAssertEqual(panel.frame.width, NotchMetrics.nonNotchWidth, accuracy: 0.5, "idle, the pill keeps its size")

        AgentSessionStore.shared.apply(AgentHookEvent(kind: .userPromptSubmit, sessionID: "wide-pill"))
        runMainLoop(for: 0.2)
        XCTAssertEqual(panel.frame.width, NotchMetrics.largeDisplayLiveActivityWidth, accuracy: 0.5, "a session at work widens it")
        XCTAssertEqual(panel.frame.midX, screen.frame.midX, accuracy: 0.5, "and it stays centered")

        AgentSessionStore.shared.archive("wide-pill")
        runMainLoop(for: settleTime)
        XCTAssertEqual(panel.frame.width, NotchMetrics.nonNotchWidth, accuracy: 0.5, "it narrows again once the session is gone")
    }
}
