import Foundation

/// Keeps the shelf in its folder (`items.json`), the Files plugin's data folder, moving the app's old shelf file
/// there the first time
struct ShelfPersistenceService {
    let folder: URL
    /// Where the app kept the shelf before (Application Support/MacDynamicIsland/shelf_items_v2.json)
    var legacyFile: URL?

    private var file: URL { folder.appendingPathComponent("items.json") }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func save(_ items: [ShelfItem]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: file, options: .atomic)
    }

    func load() -> [ShelfItem] {
        if let data = try? Data(contentsOf: file), let items = try? Self.decoder.decode([ShelfItem].self, from: data) {
            return items
        }
        guard let legacyFile, let data = try? Data(contentsOf: legacyFile),
              let items = try? Self.decoder.decode([ShelfItem].self, from: data) else { return [] }
        save(items)
        // Only once the shelf is safely in the folder
        if FileManager.default.fileExists(atPath: file.path) { try? FileManager.default.removeItem(at: legacyFile) }
        return items
    }
}
