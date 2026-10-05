import XCTest
@testable import MacDynamicIsland

@MainActor
final class ShelfStoreTests: XCTestCase {

    /// A folder of its own, removed after the test
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testDroppedFilesAndLinksStayOnTheShelf() throws {
        let folder = try makeFolder()
        let store = ShelfStore(folder: folder)
        store.add(paths: ["/tmp/a.pdf"], urls: ["https://example.com"])
        store.add(paths: ["/tmp/a.pdf", "/tmp/b.pdf"])
        XCTAssertEqual(store.items.map(\.url.absoluteString), ["file:///tmp/b.pdf", "https://example.com", "file:///tmp/a.pdf"],
                       "newest first, each once")

        let reloaded = ShelfStore(folder: folder)
        XCTAssertEqual(reloaded.items.map(\.id), store.items.map(\.id))

        reloaded.removeItem(reloaded.items[0].id)
        XCTAssertEqual(reloaded.items.count, 2)
        reloaded.clearAll()
        XCTAssertTrue(ShelfStore(folder: folder).isEmpty)
    }

    func testTheOldShelfMovesIntoTheFolderOnce() throws {
        let folder = try makeFolder()
        let legacy = folder.appendingPathComponent("shelf_items_v2.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([ShelfItem(url: URL(fileURLWithPath: "/tmp/old.pdf"))]).write(to: legacy)

        let store = ShelfStore(folder: folder.appendingPathComponent("files"), legacyFile: legacy)
        XCTAssertEqual(store.items.map(\.url.path), ["/tmp/old.pdf"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "moved, not copied")
        XCTAssertEqual(ShelfStore(folder: folder.appendingPathComponent("files"), legacyFile: legacy).items.map(\.url.path), ["/tmp/old.pdf"])
    }

    func testEmptyShelfOffersOneLargeButton() {
        let store = ShelfStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(store.islandContent.buttons.map(\.id), ["choose"])
        XCTAssertTrue(store.islandContent.cards.isEmpty)
    }
}
