import SwiftUI
import AppKit

/// A plugin's picture (PluginImage), sized and cropped by the island: rounded like the island's own thumbnails.
/// Until it loads, or if it can't, the plugin's symbol shows instead
struct PluginImageView: View {
    let image: PluginImage
    let size: CGFloat
    var fallbackSymbol: String?

    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let loaded {
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: isIcon ? .fit : .fill)
            } else {
                Image(systemName: fallbackSymbol ?? "photo")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: isIcon ? 0 : size * 0.22, style: .continuous))
        .task(id: image) { loaded = await PluginImageLoader.shared.image(for: image, size: size) }
    }

    /// App icons keep their own shape; thumbnails and pictures are cropped square
    private var isIcon: Bool {
        if case .app = image { return true }
        return false
    }
}

/// Loads and caches plugins' pictures: file thumbnails, app icons and https downloads
@MainActor
final class PluginImageLoader {
    static let shared = PluginImageLoader()

    /// Downloads larger than this are refused
    static let maxDownloadSize = 5 * 1024 * 1024

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(for image: PluginImage, size: CGFloat) async -> NSImage? {
        let key = "\(image)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let loaded: NSImage?
        switch image {
        case .file(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            loaded = await ThumbnailService.shared.generateThumbnail(for: url, size: CGSize(width: size * scale, height: size * scale))
                ?? NSWorkspace.shared.icon(forFile: url.path)
        case .app(let bundleID):
            loaded = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        case .url(let url):
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  data.count <= Self.maxDownloadSize else { return nil }
            loaded = NSImage(data: data)
        }
        if let loaded { cache.setObject(loaded, forKey: key) }
        return loaded
    }
}
