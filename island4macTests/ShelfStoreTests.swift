import XCTest
@testable import island4mac

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
}
