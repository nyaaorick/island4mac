import XCTest
@testable import Mac灵动岛

@MainActor
final class HotKeyManagerTests: XCTestCase {

    private let space: UInt16 = 49
    private let v: UInt16 = 9

    func testTheHotkeys() {
        XCTAssertEqual(HotKeyManager.hotkey(keyCode: space, modifiers: [.command, .shift]), .toggle)
        XCTAssertEqual(HotKeyManager.hotkey(keyCode: space, modifiers: [.command, .option]), .forceClose)
        XCTAssertEqual(HotKeyManager.hotkey(keyCode: v, modifiers: [.command, .option]), .clipboard)
    }

    func testTheModifiersHaveToMatchExactly() {
        XCTAssertNil(HotKeyManager.hotkey(keyCode: v, modifiers: [.command, .option, .shift]), "⇧⌥⌘V is Paste and Match Style")
        XCTAssertNil(HotKeyManager.hotkey(keyCode: space, modifiers: [.command, .option, .shift]), "not both Space hotkeys at once")
        XCTAssertNil(HotKeyManager.hotkey(keyCode: space, modifiers: [.command]), "⌘Space is Spotlight")
        XCTAssertNil(HotKeyManager.hotkey(keyCode: v, modifiers: [.command]), "⌘V is Paste")
        XCTAssertEqual(HotKeyManager.hotkey(keyCode: v, modifiers: [.command, .option, .capsLock]), .clipboard,
                       "Caps Lock doesn't count")
    }

    func testCommonShortcutsDontTouchTheIsland() {
        // ⌥⌘L is Downloads in Safari, Chrome and Finder, and ⌥⌘M minimizes every window; both used to hide the island
        XCTAssertNil(HotKeyManager.hotkey(keyCode: 37, modifiers: [.command, .option]))
        XCTAssertNil(HotKeyManager.hotkey(keyCode: 46, modifiers: [.command, .option]))
    }
}
