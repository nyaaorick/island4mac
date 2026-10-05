import Foundation

/// A picture a plugin shows on a row or beside the notch (protocol 4). The plugin says where it comes from; the
/// island sizes, crops and caches it, so it looks like every other picture in the island:
///
///     {"file": "/Users/me/Desktop/photo.jpg"}     a thumbnail of the file, made by the island
///     {"app": "com.apple.Safari"}                  that app's icon
///     {"url": "https://example.com/cover.jpg"}     downloaded by the island (https only, up to 5 MB)
enum PluginImage: Decodable, Equatable, Hashable {
    case file(String)
    case app(String)
    case url(URL)

    private enum CodingKeys: String, CodingKey { case file, app, url }

    enum DecodeError: Error { case noSource, insecureURL }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .file) {
            self = .file(path)
        } else if let bundleID = try container.decodeIfPresent(String.self, forKey: .app) {
            self = .app(bundleID)
        } else if let url = try container.decodeIfPresent(URL.self, forKey: .url) {
            guard url.scheme == "https" else { throw DecodeError.insecureURL }
            self = .url(url)
        } else {
            throw DecodeError.noSource
        }
    }
}
