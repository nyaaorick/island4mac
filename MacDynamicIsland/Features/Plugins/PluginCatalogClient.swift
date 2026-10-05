import Foundation

/// Talks to the plugins repo: reads its index, downloads a plugin's archive and unpacks it into the plugins
/// folder. PluginStore picks the change up on its next reload
struct PluginCatalogClient {
    let pluginsFolder: URL
    var session: URLSession = .shared

    enum CatalogError: Error, CustomStringConvertible {
        case insecureURL(URL)
        case unpackFailed(Int32)
        case noManifest
        case wrongPlugin(expected: String, found: String)

        var description: String {
            switch self {
            case .insecureURL(let url): return "not an https address: \(url.absoluteString)"
            case .unpackFailed(let status): return "couldn't unpack the archive (ditto exit \(status))"
            case .noManifest: return "the archive has no \(PluginManifest.fileName)"
            case .wrongPlugin(let expected, let found): return "the archive holds \"\(found)\", not \"\(expected)\""
            }
        }
    }

    func fetchIndex(from url: URL) async throws -> [PluginCatalogEntry] {
        try checkScheme(url)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(PluginCatalogEntry.Index.self, from: data).plugins
    }

    /// Installs or updates the plugin. The old copy is replaced only once the new one has unpacked and checks out
    func install(_ entry: PluginCatalogEntry) async throws {
        try checkScheme(entry.archive)
        let (download, _) = try await session.download(from: entry.archive)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        try await unzip(download, into: work)
        let unpacked = try pluginRoot(in: work)
        let manifest = try PluginManifest.load(from: unpacked)
        guard manifest.id == entry.id else { throw CatalogError.wrongPlugin(expected: entry.id, found: manifest.id) }

        try FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
        let target = pluginsFolder.appendingPathComponent(entry.id)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: unpacked)
        } else {
            try FileManager.default.moveItem(at: unpacked, to: target)
        }
    }

    func remove(_ pluginID: String) throws {
        try FileManager.default.removeItem(at: pluginsFolder.appendingPathComponent(pluginID))
    }

    // MARK: - Helpers

    /// Only https, plus local files (a repo checked out on this Mac, and the tests)
    private func checkScheme(_ url: URL) throws {
        guard url.scheme == "https" || url.isFileURL else { throw CatalogError.insecureURL(url) }
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
