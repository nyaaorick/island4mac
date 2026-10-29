import Foundation

/// Keeps the shelf in its folder (`items.json`), the Files plugin's data folder
struct ShelfPersistenceService {
    let folder: URL

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
        guard let data = try? Data(contentsOf: file), let items = try? Self.decoder.decode([ShelfItem].self, from: data) else { return [] }
        return items
    }
}
