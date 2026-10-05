import Foundation

/// One plugin in the plugins repo's `index.json`:
///
///     {"plugins":[{"id":"timer","name":"Timer","symbol":"timer","version":"1.0.0","protocol":1,
///                  "description":"Countdown beside the notch","archive":"https://.../timer.zip"}]}
///
/// The archive is a zip of the plugin's folder (or of its files), with its program already built
struct PluginCatalogEntry: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    var symbol: String?
    let version: String
    let `protocol`: Int
    var description: String?
    let archive: URL

    /// Whether this app can run it
    var isSupported: Bool { `protocol` <= PluginManifest.supportedProtocol }

    struct Index: Decodable {
        let plugins: [PluginCatalogEntry]
    }
}
