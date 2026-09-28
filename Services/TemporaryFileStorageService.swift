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
    
    /// Copy file to temporary location
    func copyToTemporary(from sourceURL: URL) throws -> URL {
        let filename = sourceURL.lastPathComponent
        let destURL = tempDirectory.appendingPathComponent(filename)
        
        try fileManager.copyItem(at: sourceURL, to: destURL)
        trackedFiles.insert(destURL)
        
        return destURL
    }
    
    /// Move file to temporary location
    func moveToTemporary(from sourceURL: URL) throws -> URL {
        let filename = sourceURL.lastPathComponent
        let destURL = tempDirectory.appendingPathComponent(filename)
        
        try fileManager.moveItem(at: sourceURL, to: destURL)
        trackedFiles.insert(destURL)
        
        return destURL
    }
    
    /// Get temporary URL for filename
    func temporaryURL(for filename: String) -> URL {
        return tempDirectory.appendingPathComponent(filename)
    }
    
    /// Get unique temporary URL
    func uniqueTemporaryURL(extension ext: String = "tmp") -> URL {
        let filename = "\(UUID().uuidString).\(ext)"
        return tempDirectory.appendingPathComponent(filename)
    }
    
    // MARK: - Cleanup
    
    /// Remove specific temporary file
    func remove(url: URL) throws {
        try fileManager.removeItem(at: url)
        trackedFiles.remove(url)
    }
    
    /// Remove all tracked temporary files
    func cleanupAll() {
        for url in trackedFiles {
            try? fileManager.removeItem(at: url)
        }
        trackedFiles.removeAll()
        
        // Remove temp directory
        try? fileManager.removeItem(at: tempDirectory)
    }
    
    /// Remove old temporary files (older than specified time)
    func cleanupOld(olderThan interval: TimeInterval) {
        let cutoffDate = Date().addingTimeInterval(-interval)
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        for fileURL in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let creationDate = attributes[.creationDate] as? Date else {
                continue
            }
            
            if creationDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
                trackedFiles.remove(fileURL)
            }
        }
    }
    
    // MARK: - Info
    
    /// Get total size of temporary files
    func totalSize() -> Int64 {
        var total: Int64 = 0
        
        for url in trackedFiles {
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                total += size
            }
        }
        
        return total
    }
    
    /// Get count of temporary files
    var fileCount: Int {
        return trackedFiles.count
    }
    
    /// Check if file exists in temporary storage
    func exists(url: URL) -> Bool {
        return trackedFiles.contains(url) && fileManager.fileExists(atPath: url.path)
    }
}

enum TempStorageError: Error {
    case encodingFailed
    case copyFailed
    case moveFailed
    case notFound
}
