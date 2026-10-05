import XCTest
@testable import MacDynamicIsland

@MainActor
final class ClipboardStoreTests: XCTestCase {

    /// A store in a throwaway folder, with a throwaway defaults domain for the old history, so tests never touch
    /// the real one
    private func makeStore(settings: ClipboardStore.Settings = ClipboardStore.Settings()) -> (ClipboardStore, UserDefaults) {
        let suiteName = "ClipboardStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }
        return (ClipboardStore(folder: folder, settings: settings, legacyDefaults: defaults), defaults)
    }

    private func addText(_ text: String, to store: ClipboardStore) {
        store.addItem(content: text, type: .text, sourceBundleID: nil, sourceAppName: nil, imageData: nil)
    }

    private func addImage(_ bytes: [UInt8], to store: ClipboardStore) {
        // ClipboardMonitor stores every image with the same placeholder content
        store.addItem(content: "[Image]", type: .image, sourceBundleID: nil, sourceAppName: nil, imageData: Data(bytes))
    }

    func testRepeatedTextIsStoredOnce() {
        let (store, _) = makeStore()
        addText("hello", to: store)
        addText("hello", to: store)
        XCTAssertEqual(store.items.map(\.content), ["hello"])
    }

    func testNewestItemComesFirst() {
        let (store, _) = makeStore()
        addText("first", to: store)
        addText("second", to: store)
        XCTAssertEqual(store.items.map(\.content), ["second", "first"])
    }

    func testDifferentImagesCopiedBackToBackAreBothKept() {
        let (store, _) = makeStore()
        addImage([1, 2, 3], to: store)
        addImage([4, 5, 6], to: store)
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.imageData, Data([4, 5, 6]))
    }

    func testRepeatedImageIsStoredOnce() {
        let (store, _) = makeStore()
        addImage([1, 2, 3], to: store)
        addImage([1, 2, 3], to: store)
        XCTAssertEqual(store.items.count, 1)
    }

    func testMaxItemsDropsOldest() {
        let (store, _) = makeStore(settings: ClipboardStore.Settings(maxItems: 3))
        for text in ["a", "b", "c", "d"] {
            addText(text, to: store)
        }
        XCTAssertEqual(store.items.map(\.content), ["d", "c", "b"])
    }

    func testItemsSurviveReload() {
        let (store, defaults) = makeStore()
        addText("persisted", to: store)

        let reloaded = ClipboardStore(folder: store.folder, legacyDefaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.content), ["persisted"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("history.json").path))
    }

    func testTheOldHistoryMovesIntoTheFolderOnce() throws {
        let (store, defaults) = makeStore()
        let old = [ClipboardItem(content: "from before", type: .text, sourceBundleID: nil, sourceAppName: nil, imageData: nil)]
        defaults.set(try JSONEncoder().encode(old), forKey: ClipboardStore.legacyKey)

        store.load()
        XCTAssertEqual(store.items.map(\.content), ["from before"])
        XCTAssertNil(defaults.data(forKey: ClipboardStore.legacyKey), "moved, not copied")

        let reloaded = ClipboardStore(folder: store.folder, legacyDefaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.items.map(\.content), ["from before"])
    }

    func testSettingsTrimAndExpireTheHistory() {
        let (store, _) = makeStore()
        for text in ["a", "b", "c"] { addText(text, to: store) }
        store.settings.maxItems = 2
        XCTAssertEqual(store.items.map(\.content), ["c", "b"], "fewer items keeps the newest")

        store.pruneExpiredItems(now: Date().addingTimeInterval(25 * 3600))
        XCTAssertTrue(store.items.isEmpty, "a day later they're gone")

        let (forever, _) = makeStore(settings: ClipboardStore.Settings(keepHours: 0))
        addText("kept", to: forever)
        forever.pruneExpiredItems(now: Date().addingTimeInterval(1000 * 3600))
        XCTAssertEqual(forever.items.map(\.content), ["kept"], "0 hours keeps them forever")
    }

    // MARK: - The tab, in the plugin protocol

    func testEachItemIsACardWithItsTextOrPicture() throws {
        let (store, _) = makeStore()
        store.addItem(content: "let x = 1", type: .code, sourceBundleID: "com.apple.dt.Xcode", sourceAppName: "Xcode", imageData: nil)
        addImage([1, 2, 3], to: store)

        let content = store.islandContent
        XCTAssertEqual(content.cards.count, 2)
        let image = try XCTUnwrap(content.cards.first)
        let file = try XCTUnwrap(store.imageFile(for: store.items[0]))
        XCTAssertEqual(image.preview, .image(.file(file.path)), "the picture is shown from its file")
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
        let text = content.cards[1]
        XCTAssertEqual(text.title, "Xcode")
        XCTAssertEqual(text.image, .app("com.apple.dt.Xcode"))
        XCTAssertEqual(text.preview, .text("let x = 1"))
        XCTAssertEqual(content.buttons.map(\.id), ["clear"])

        store.removeItem(store.items[0])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "a removed picture's file goes too")
    }

    func testTapsDeleteAndClear() throws {
        let (store, _) = makeStore()
        addText("a", to: store)
        addText("b", to: store)
        let delete = try XCTUnwrap(store.islandContent.cards.first?.actions?.first?.id)
        XCTAssertFalse(store.handle(.action(delete)))
        XCTAssertEqual(store.items.map(\.content), ["a"])
        store.handle(.action("clear"))
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.islandContent, PluginStore.Content(), "nothing: the tab shows its empty state")
    }
}
