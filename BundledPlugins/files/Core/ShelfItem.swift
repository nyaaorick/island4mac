import Foundation
import AppKit
import UniformTypeIdentifiers

/// Represents an item stored on the shelf (file, folder, or URL)
/// Following the Boring Notch pattern: persistent data struct
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var bookmarkData: Data?
    var dateAdded: Date
    
    init(url: URL, bookmarkData: Data? = nil) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.bookmarkData = bookmarkData
        self.dateAdded = Date()
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        name.isEmpty ? url.lastPathComponent : name
    }
    
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
    
    var iconName: String {
        if isDirectory { return "folder.fill" }
        if isImage { return "photo.fill" }
        if isVideo { return "video.fill" }
        if isAudio { return "music.note" }
        if isPDF { return "doc.fill" }
        return "doc.fill"
    }

    var isImage: Bool { UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true }
    var isVideo: Bool { UTType(filenameExtension: fileExtension)?.conforms(to: .movie) == true }
    var isAudio: Bool { UTType(filenameExtension: fileExtension)?.conforms(to: .audio) == true }
    var isPDF: Bool { UTType(filenameExtension: fileExtension)?.conforms(to: .pdf) == true }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
}
