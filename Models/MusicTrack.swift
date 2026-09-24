import Combine
import Foundation
import AppKit
import OSLog

/// Music track model
struct MusicTrack: Identifiable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var currentTime: TimeInterval
    var albumArtURL: URL?
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var albumArt: NSImage? {
        get async {
            guard let url = albumArtURL else { return nil }
            
            // Try to load from cache
            if let cached = MemoryManager.shared.cachedImage(forKey: url.absoluteString) {
                return cached
            }
            
            // Load from URL
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    MemoryManager.shared.cacheImage(image, forKey: url.absoluteString)
                    return image
                }
            } catch {
                let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MusicTrack")
                logger.error("Failed to load album art: \(error.localizedDescription)")
            }
            
            return nil
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String = "",
        duration: TimeInterval = 0,
        currentTime: TimeInterval = 0,
        albumArtURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.currentTime = currentTime
        self.albumArtURL = albumArtURL
    }
}
