import Foundation
import Security

/// Updates the app from its GitHub releases: finds the latest, downloads its DMG and puts the app in it in place of
/// this one. Only an app whose code signature satisfies this app's designated requirement is installed, so the same
/// bundle id signed with the same certificate (the self-signed "island4mac Release"). That is also what keeps macOS
/// permissions across updates. Releases are made by Release.command (spec/docs/06-dev-builds-and-releases.md)
struct UpdateClient {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/nyaaorick/island4mac/releases/latest")!

    var latestRelease = UpdateClient.latestReleaseURL
    var session: URLSession = .shared

    struct Release: Equatable {
        let version: String
        /// The DMG
        let download: URL
        /// Its page on GitHub
        let page: URL
    }

    enum UpdateError: Error, CustomStringConvertible {
        case http(Int)
        case translocated
        case toolFailed(String, Int32)
        case noApp
        case untrusted(OSStatus)
        case wrongVersion(expected: String, found: String)

        var description: String {
            switch self {
            case .http(let status): return "GitHub answered \(status)"
            case .translocated: return "the app runs from a temporary copy macOS made of it; move it to Applications first"
            case .toolFailed(let tool, let status): return "\(tool) failed (exit \(status))"
            case .noApp: return "the DMG holds no app"
            case .untrusted(let status): return "the downloaded app isn't signed like this one (\(status))"
            case .wrongVersion(let expected, let found): return "the DMG holds version \(found), not \(expected)"
            }
        }
    }

    /// The latest release, when it is newer than `version`. Nil when there is none, or none with a DMG
    func newerRelease(than version: String) async throws -> Release? {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            // 404: nothing is released yet
            if status == 404 { return nil }
            throw UpdateError.http(status)
        }
        guard let release = try Self.release(from: data), Version.isVersion(release.version, newerThan: version) else {
            return nil
        }
        return release
    }

    /// Downloads the release's DMG, checks the app in it and puts it in place of `app`. The running app goes on
    /// running the old code until it quits; `relaunch` starts the new one
    func install(_ release: Release, over app: URL) async throws {
        guard !app.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)")
        // On the app's volume, so putting it in place is a rename
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer {
            try? fileManager.removeItem(at: work)
            try? fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)

        let (download, _) = try await session.download(from: release.download)
        let dmg = work.appendingPathComponent("update.dmg")
        try fileManager.moveItem(at: download, to: dmg)

        let mount = work.appendingPathComponent("mount")
        try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-mountpoint", mount.path, "-nobrowse", "-readonly", "-noautoopen", "-quiet"])
        let staged = staging.appendingPathComponent(app.lastPathComponent)
        do {
            let apps = try fileManager.contentsOfDirectory(at: mount, includingPropertiesForKeys: [.isSymbolicLinkKey])
                .filter { $0.pathExtension == "app" && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
            guard let found = apps.first else { throw UpdateError.noApp }
            // ditto keeps the bundle exactly as signed
            try await run("/usr/bin/ditto", [found.path, staged.path])
        } catch {
            try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
            throw error
        }
        try? await run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])

        try Self.checkSignature(of: staged)
        let found = Bundle(url: staged)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        guard found == release.version else { throw UpdateError.wrongVersion(expected: release.version, found: found) }
        _ = try fileManager.replaceItemAt(app, withItemAt: staged)
    }

    /// Opens the app at `app` once this process has quit, which the caller does next
    static func relaunch(_ app: URL) {
        let process = Process()
        // A one-line wait in sh rather than a helper program: it has to outlive this process, and a helper would sit
        // in the bundle that was just replaced. Gives up waiting after 30 s; the pid and path are arguments, not code
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"for i in $(/usr/bin/seq 300); do /bin/kill -0 "$0" 2>/dev/null || break; /bin/sleep 0.1; done; /usr/bin/open "$1""#,
                             String(getpid()), app.path]
        try? process.run()
    }

    // MARK: - Helpers

    /// The release GitHub's API describes, if it has a DMG
    static func release(from data: Data) throws -> Release? {
        struct GitHubRelease: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadUrl: URL
            }
            let tagName: String
            let htmlUrl: URL
            let assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              dmg.browserDownloadUrl.scheme == "https" else { return nil }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return Release(version: version, download: dmg.browserDownloadUrl, page: release.htmlUrl)
    }

    /// The app must satisfy the running app's designated requirement: its identifier and signing certificate
    private static func checkSignature(of app: URL) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var update: SecStaticCode?
        var status = SecCodeCopySelf([], &running)
        if status == errSecSuccess, let running { status = SecCodeCopyStaticCode(running, [], &runningStatic) }
        if status == errSecSuccess, let runningStatic { status = SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) }
        if status == errSecSuccess { status = SecStaticCodeCreateWithPath(app as CFURL, [], &update) }
        guard status == errSecSuccess, let requirement, let update else { throw UpdateError.untrusted(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        status = SecStaticCodeCheckValidity(update, flags, requirement)
        guard status == errSecSuccess else { throw UpdateError.untrusted(status) }
    }

    private func run(_ tool: String, _ arguments: [String]) async throws {
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError.toolFailed(URL(fileURLWithPath: tool).lastPathComponent, status) }
    }
}
