import XCTest
@testable import Mac灵动岛

@MainActor
final class ClipboardHubStoreTests: XCTestCase {

    /// A store backed by a throwaway defaults domain, so tests never touch the real history.
    private func makeStore() -> (ClipboardHubStore, UserDefaults) {
        let suiteName = "ClipboardHubStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return (ClipboardHubStore(defaults: defaults), defaults)
    }

    private func addText(_ text: String, to store: ClipboardHubStore) {
        store.addItem(content: text, type: .text, sourceBundleID: nil, sourceAppName: nil, imageData: nil)
    }

    private func addImage(_ bytes: [UInt8], to store: ClipboardHubStore) {
        // ClipboardManager stores every image with the same placeholder content
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

        let reloaded = ClipboardHubStore(defaults: defaults)
        reloaded.loadFromDisk()
        XCTAssertEqual(reloaded.items.map(\.content), ["persisted"])
    }
}
