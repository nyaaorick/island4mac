import Foundation

/// Service for persisting shelf items to disk
class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var shelfFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("MacDynamicIsland", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("shelf_items_v2.json")
    }
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Save/Load
    
    func saveItems(_ items: [ShelfItem]) async throws {
        let data = try encoder.encode(items)
        try data.write(to: shelfFileURL, options: .atomic)
    }
    
    func loadItems() async throws -> [ShelfItem] {
        guard fileManager.fileExists(atPath: shelfFileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: shelfFileURL)
        let items = try decoder.decode([ShelfItem].self, from: data)
        return items
    }
}
