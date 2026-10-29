import XCTest
@testable import island4mac

@MainActor
final class HotKeyMonitorTests: XCTestCase {

    private let space: UInt16 = 49
    private let v: UInt16 = 9

    func testTheHotkeys() {
        XCTAssertEqual(HotKeyMonitor.hotkey(keyCode: space, modifiers: [.command, .shift]), .toggle)
        XCTAssertEqual(HotKeyMonitor.hotkey(keyCode: space, modifiers: [.command, .option]), .forceClose)
        XCTAssertEqual(HotKeyMonitor.hotkey(keyCode: v, modifiers: [.command, .option]), .clipboard)
    }

    func testTheModifiersHaveToMatchExactly() {
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: v, modifiers: [.command, .option, .shift]), "⇧⌥⌘V is Paste and Match Style")
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: space, modifiers: [.command, .option, .shift]), "not both Space hotkeys at once")
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: space, modifiers: [.command]), "⌘Space is Spotlight")
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: v, modifiers: [.command]), "⌘V is Paste")
        XCTAssertEqual(HotKeyMonitor.hotkey(keyCode: v, modifiers: [.command, .option, .capsLock]), .clipboard,
                       "Caps Lock doesn't count")
    }

    func testCommonShortcutsDontTouchTheIsland() {
        // ⌥⌘L is Downloads in Safari, Chrome and Finder, and ⌥⌘M minimizes every window; both used to hide the island
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: 37, modifiers: [.command, .option]))
        XCTAssertNil(HotKeyMonitor.hotkey(keyCode: 46, modifiers: [.command, .option]))
    }
}
