import XCTest
@testable import island4mac

@MainActor
final class ClipboardStoreTests: XCTestCase {

    /// A store in a throwaway folder, so tests never touch the real history
    private func makeStore(settings: ClipboardStore.Settings = ClipboardStore.Settings()) -> ClipboardStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardStoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return ClipboardStore(folder: folder, settings: settings)
    }

    private func addText(_ text: String, to store: ClipboardStore) {
        store.addItem(content: text, type: .text, sourceBundleID: nil, sourceAppName: nil, imageData: nil)
    }

    private func addImage(_ bytes: [UInt8], to store: ClipboardStore) {
        // ClipboardMonitor stores every image with the same placeholder content
        store.addItem(content: "[Image]", type: .image, sourceBundleID: nil, sourceAppName: nil, imageData: Data(bytes))
    }

    func testRepeatedTextIsStoredOnce() {
        let store = makeStore()
        addText("hello", to: store)
        addText("hello", to: store)
        XCTAssertEqual(store.items.map(\.content), ["hello"])
    }

    func testNewestItemComesFirst() {
        let store = makeStore()
        addText("first", to: store)
        addText("second", to: store)
        XCTAssertEqual(store.items.map(\.content), ["second", "first"])
    }

    func testDifferentImagesCopiedBackToBackAreBothKept() {
        let store = makeStore()
        addImage([1, 2, 3], to: store)
        addImage([4, 5, 6], to: store)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.imageData, Data([4, 5, 6]))
    }

    func testRepeatedImageIsStoredOnce() {
        let store = makeStore()
        addImage([1, 2, 3], to: store)
        addImage([1, 2, 3], to: store)
        XCTAssertEqual(store.items.count, 1)
    }

    func testMaxItemsDropsOldest() {
        let store = makeStore(settings: ClipboardStore.Settings(maxItems: 3))
        for text in ["a", "b", "c", "d"] {
            addText(text, to: store)
        }
        XCTAssertEqual(store.items.map(\.content), ["d", "c", "b"])
    }

    func testItemsSurviveReload() {
        let store = makeStore()
        addText("persisted", to: store)

        let reloaded = ClipboardStore(folder: store.folder)
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.content), ["persisted"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("history.json").path))
    }

    func testSettingsTrimAndExpireTheHistory() {
        let store = makeStore()
        for text in ["a", "b", "c"] { addText(text, to: store) }
        store.settings.maxItems = 2
        XCTAssertEqual(store.items.map(\.content), ["c", "b"], "fewer items keeps the newest")

        store.pruneExpiredItems(now: Date().addingTimeInterval(25 * 3600))
        XCTAssertTrue(store.items.isEmpty, "a day later they're gone")

        let forever = makeStore(settings: ClipboardStore.Settings(keepHours: 0))
        addText("kept", to: forever)
        forever.pruneExpiredItems(now: Date().addingTimeInterval(1000 * 3600))
        XCTAssertEqual(forever.items.map(\.content), ["kept"], "0 hours keeps them forever")
    }

    func testCopiedPicturesAreFilesWhileKept() throws {
        let store = makeStore()
        addImage([1, 2, 3], to: store)
        let file = try XCTUnwrap(store.imageFile(for: store.items[0]), "the card shows the picture from its file")
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
        store.removeItem(store.items[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "a removed picture's file goes too")
    }
}
