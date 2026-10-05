import XCTest
@testable import MacDynamicIsland

@MainActor
final class ClipboardStoreTests: XCTestCase {

    /// A store backed by a throwaway defaults domain and image folder, so tests never touch the real history.
    private func makeStore() -> (ClipboardStore, UserDefaults) {
        let suiteName = "ClipboardStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let images = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: images)
        }
        return (ClipboardStore(defaults: defaults, imageFolder: images), defaults)
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
        let (store, _) = makeStore()
        store.maxItems = 3
        for text in ["a", "b", "c", "d"] {
            addText(text, to: store)
        }
        XCTAssertEqual(store.items.map(\.content), ["d", "c", "b"])
    }

    func testItemsSurviveReload() {
        let (store, defaults) = makeStore()
        addText("persisted", to: store)

        let reloaded = ClipboardStore(defaults: defaults, imageFolder: store.imageFolder)
        reloaded.loadFromDisk()
        XCTAssertEqual(reloaded.items.map(\.content), ["persisted"])
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
        XCTAssertFalse(store.handle(.action(delete), pastingInto: nil))
        XCTAssertEqual(store.items.map(\.content), ["a"])
        store.handle(.action("clear"), pastingInto: nil)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.islandContent, PluginStore.Content(), "nothing: the tab shows its empty state")
    }
}
