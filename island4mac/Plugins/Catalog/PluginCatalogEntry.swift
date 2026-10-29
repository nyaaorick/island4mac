import Foundation

/// One plugin in a catalog's `index.json` (the plugins repo's, or your own):
///
///     {"plugins":[{"id":"timer","name":"Timer","symbol":"timer","version":"1.0.0","protocol":1,
///                  "description":"Countdown beside the notch","archive":"https://.../timer.zip",
///                  "sha256":"…","size":123456,"author":"nyaaorick","homepage":"https://…","updated":"2026-10-29"}]}
///
/// The archive is a zip of the plugin's folder (or of its files), with its program already built. `sha256`, `size`,
/// `author`, `homepage` and `updated` are optional: an index without them still installs, but only one with a
/// `sha256` is checked before it is unpacked
struct PluginCatalogEntry: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    var symbol: String?
    let version: String
    let `protocol`: Int
    var description: String?
    let archive: URL
    /// Hex SHA-256 of the archive; an archive that doesn't match isn't installed
    var sha256: String?
    /// The archive's size in bytes
    var size: Int?
    var author: String?
    var homepage: URL?
    /// When this version was published (YYYY-MM-DD)
    var updated: String?

    /// Whether this app can run it
    var isSupported: Bool { `protocol` <= PluginManifest.supportedProtocol }

    /// Whether this is newer than the installed `version`; false when either isn't a version
    func isNewer(than installedVersion: String?) -> Bool {
        Version.isVersion(version, newerThan: installedVersion ?? "0")
    }

    /// "1.2.0 · 1.3 MB · by nyaaorick", from what the index says
    var summary: String {
        var parts = [version]
        if let size { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
        if let author { parts.append("by \(author)") }
        return parts.joined(separator: " · ")
    }

    struct Index: Decodable {
        let plugins: [PluginCatalogEntry]
    }
}
