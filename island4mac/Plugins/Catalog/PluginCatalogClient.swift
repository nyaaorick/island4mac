import CryptoKit
import Foundation

/// Talks to a plugin catalog: reads its index, downloads a plugin's archive, checks it and unpacks it into the
/// plugins folder. Also installs a zip or folder from this Mac. PluginStore picks the change up on its next reload
struct PluginCatalogClient {
    let pluginsFolder: URL
    /// Where plugins keep their data (PluginStore.dataFolder); a removed plugin's goes with it
    var dataFolder: URL?
    var session: URLSession = .shared
    /// Uninstalling moves the plugin and its data to the Trash, so a slip of the mouse can be undone there
    var movesToTrash = true

    /// Where an install is, for Settings to say so
    enum Phase: Equatable {
        case downloading, verifying, installing
    }

    enum CatalogError: Error, CustomStringConvertible, Equatable {
        case insecureURL(URL)
        /// The index isn't there (yet): nothing is published, which isn't a failure
        case notPublished
        case http(Int)
        case unpackFailed(Int32)
        case noManifest
        case wrongPlugin(expected: String, found: String)
        case wrongVersion(expected: String, found: String)
        case checksumMismatch
        case notAPlugin(URL)

        var description: String {
            switch self {
            case .insecureURL(let url): return "not an https address: \(url.absoluteString)"
            case .notPublished: return "no plugins published yet"
            case .http(let status): return "the catalog answered \(status)"
            case .unpackFailed(let status): return "couldn't unpack the archive (ditto exit \(status))"
            case .noManifest: return "the archive has no \(PluginManifest.fileName)"
            case .wrongPlugin(let expected, let found): return "the archive holds \"\(found)\", not \"\(expected)\""
            case .wrongVersion(let expected, let found): return "the archive holds version \(found), not \(expected)"
            case .checksumMismatch: return "the download doesn't match the catalog's checksum"
            case .notAPlugin(let url): return "\(url.lastPathComponent) is neither a plugin folder nor a zip of one"
            }
        }
    }

    func fetchIndex(from url: URL) async throws -> [PluginCatalogEntry] {
        try checkScheme(url)
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) { throw CatalogError.notPublished }
        let (data, response) = try await session.data(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw status == 404 ? CatalogError.notPublished : CatalogError.http(status)
        }
        return try Self.decodeIndex(data)
    }

    static func decodeIndex(_ data: Data) throws -> [PluginCatalogEntry] {
        try JSONDecoder().decode(PluginCatalogEntry.Index.self, from: data).plugins
    }

    /// Installs or updates the plugin. The download is checked against the index's checksum when it has one, and
    /// the old copy is replaced only once the new one has unpacked and checks out
    func install(_ entry: PluginCatalogEntry, progress: (Phase) -> Void = { _ in }) async throws {
        try checkScheme(entry.archive)
        progress(.downloading)
        let (download, _) = try await session.download(from: entry.archive)
        let work = try makeWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("plugin.zip")
        try FileManager.default.moveItem(at: download, to: archive)

        progress(.verifying)
        if let expected = entry.sha256?.lowercased(), !expected.isEmpty {
            guard try Self.sha256(of: archive) == expected else { throw CatalogError.checksumMismatch }
        }
        let unpacked = try await unpack(archive, into: work.appendingPathComponent("unpacked", isDirectory: true))
        let manifest = try PluginManifest.load(from: unpacked)
        guard manifest.id == entry.id else { throw CatalogError.wrongPlugin(expected: entry.id, found: manifest.id) }
        if let version = manifest.version, version != entry.version {
            throw CatalogError.wrongVersion(expected: entry.version, found: version)
        }

        progress(.installing)
        try place(unpacked, as: entry.id)
    }

    /// Installs a plugin from this Mac: a zip of its folder, or the folder itself. Returns its manifest
    @discardableResult
    func install(from source: URL) async throws -> PluginManifest {
        let work = try makeWorkFolder()
        defer { try? FileManager.default.removeItem(at: work) }
        let unpacked: URL
        if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            unpacked = work.appendingPathComponent("copy", isDirectory: true)
            try FileManager.default.copyItem(at: source, to: unpacked)
        } else if source.pathExtension.lowercased() == "zip" {
            unpacked = try await unpack(source, into: work.appendingPathComponent("unpacked", isDirectory: true))
        } else {
            throw CatalogError.notAPlugin(source)
        }
        let manifest = try PluginManifest.load(from: unpacked)
        try place(unpacked, as: manifest.id)
        return manifest
    }

    /// Uninstalls the plugin, with what it kept in its data folder
    func remove(_ pluginID: String) throws {
        try discard(pluginsFolder.appendingPathComponent(pluginID))
        if let dataFolder {
            let data = dataFolder.appendingPathComponent(pluginID)
            if FileManager.default.fileExists(atPath: data.path) { try? discard(data) }
        }
    }

    // MARK: - Helpers

    private func makeWorkFolder() throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return work
    }

    /// Puts the unpacked plugin in the plugins folder as `id`, in place of what was there
    private func place(_ unpacked: URL, as id: String) throws {
        try FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
        let target = pluginsFolder.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: unpacked)
        } else {
            try FileManager.default.moveItem(at: unpacked, to: target)
        }
    }

    /// To the Trash, or gone where there's none (a volume without one)
    private func discard(_ item: URL) throws {
        if movesToTrash, (try? FileManager.default.trashItem(at: item, resultingItemURL: nil)) != nil { return }
        try FileManager.default.removeItem(at: item)
    }

    /// Only https, plus local files (a repo checked out on this Mac, and the tests)
    private func checkScheme(_ url: URL) throws {
        guard url.scheme == "https" || url.isFileURL else { throw CatalogError.insecureURL(url) }
    }

    static func sha256(of file: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: file))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Unzips the archive into `folder` and returns the plugin's root in it
    private func unpack(_ archive: URL, into folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await unzip(archive, into: folder)
        return try pluginRoot(in: folder)
    }

    /// ditto keeps the program's executable bit, which a plain unzip into Foundation types would lose
    private func unzip(_ archive: URL, into folder: URL) async throws {
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, folder.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw CatalogError.unpackFailed(status) }
    }

    /// The archive may hold the plugin's files, or one folder with them
    private func pluginRoot(in folder: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(PluginManifest.fileName).path) {
            return folder
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
        let folders = children.filter { $0.lastPathComponent != "__MACOSX" }
        guard folders.count == 1,
              FileManager.default.fileExists(atPath: folders[0].appendingPathComponent(PluginManifest.fileName).path) else {
            throw CatalogError.noManifest
        }
        return folders[0]
    }
}
