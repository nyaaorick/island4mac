import Foundation
import AppKit
import QuickLookThumbnailing

/// Service for generating thumbnails for files
class ThumbnailGenerationService {
    static let shared = ThumbnailGenerationService()
    
    private let cache = NSCache<NSURL, NSImage>()
    private let thumbnailSize = CGSize(width: 256, height: 256)
    private let queue = DispatchQueue(label: "com.macdynamicisland.thumbnail", qos: .userInitiated)
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    // MARK: - Public API
    
    func generateThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            completion(cached)
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let thumbnail = self.generateThumbnailSync(for: url)
            
            if let thumbnail = thumbnail {
                self.cache.setObject(thumbnail, forKey: url as NSURL)
            }
            
            DispatchQueue.main.async {
                completion(thumbnail)
            }
        }
    }
    
    func generateThumbnail(for url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            generateThumbnail(for: url) { image in
                continuation.resume(returning: image)
            }
        }
    }
    
    func generateThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        // Use default thumbnail generation, ignore custom size for now
        await generateThumbnail(for: url)
    }
    
    // MARK: - Synchronous Generation
    
    private func generateThumbnailSync(for url: URL) -> NSImage? {
        // Try QuickLook thumbnail first
        if let qlThumbnail = generateQuickLookThumbnail(for: url) {
            return qlThumbnail
        }
        
        // Fall back to icon
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    private func generateQuickLookThumbnail(for url: URL) -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        
        var thumbnail: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, _, error in
            if let rep = rep {
                thumbnail = rep.nsImage
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        return thumbnail
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    func removeCachedThumbnail(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
