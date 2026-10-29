import Foundation
import AppKit
import Combine

/// The files, folders and links you put on the shelf, newest first, kept in its folder (the Files plugin's data
/// folder). What you drop arrives as paths and links (IslandDrop): no drag handling and no SwiftUI in here
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    let maxItems = 50
    private let persistence: ShelfPersistenceService

    init(folder: URL) {
        persistence = ShelfPersistenceService(folder: folder)
        items = persistence.load()
    }

    var isEmpty: Bool { items.isEmpty }

    /// Puts files (paths) and links on the shelf, newest first, skipping ones already on it
    func add(paths: [String] = [], urls: [String] = []) {
        let new = paths.map { URL(fileURLWithPath: $0) } + urls.compactMap(URL.init(string:))
        for url in new where !items.contains(where: { $0.url == url }) {
            let bookmarkData = url.isFileURL
                ? try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                : nil
            items.insert(ShelfItem(url: url, bookmarkData: bookmarkData), at: 0)
        }
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        persistence.save(items)
    }

    func removeItem(_ itemID: UUID) {
        items.removeAll { $0.id == itemID }
        persistence.save(items)
    }

    func clearAll() {
        items.removeAll()
        persistence.save(items)
    }

    /// Where the item is now: its bookmark follows a file that moved
    func resolveFileURL(for item: ShelfItem) -> URL? {
        if let data = item.bookmarkData {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                return resolved
            }
        }
        return item.url
    }
}
