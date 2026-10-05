import Foundation

/// Service for managing temporary file storage
class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    
    private let fileManager = FileManager.default
    private var tempDirectory: URL
    private var trackedFiles: Set<URL> = []
    
    private init() {
        // Create app-specific temp directory
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacDynamicIsland", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        cleanupAll()
    }
    
    // MARK: - File Operations
    
    /// Save data to temporary file
    func saveTemporary(data: Data, filename: String) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        trackedFiles.insert(fileURL)
        return fileURL
    }
    
    /// Create temporary file with content
    func createTemporary(content: String, filename: String) throws -> URL {
        guard let data = content.data(using: .utf8) else {
            throw TempStorageError.encodingFailed
        }
        return try saveTemporary(data: data, filename: filename)
    }
    
    // MARK: - Cleanup
    
    /// Remove all tracked temporary files
    func cleanupAll() {
        for url in trackedFiles {
            try? fileManager.removeItem(at: url)
        }
        trackedFiles.removeAll()
        
        // Remove temp directory
        try? fileManager.removeItem(at: tempDirectory)
    }
}

enum TempStorageError: Error {
    case encodingFailed
}
