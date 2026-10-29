import Foundation

/// What this build is: the installed release, or the dev app (every Debug build), which keeps its settings, files and
/// permissions apart from the release's (spec/docs/06-dev-builds-and-releases.md)
enum BuildConfig {
    /// True while the app is hosting unit tests: skip anything that talks to other apps or asks for permissions
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The Debug configuration builds the dev app (`com.nyaaorick.island4mac.dev`, "island4mac Dev")
    nonisolated static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    /// The app's folder in Application Support, for plugins and their data
    nonisolated static var supportFolderName: String {
        isDevBuild ? "island4mac Dev" : "island4mac"
    }

    /// `~/Library/Application Support/<supportFolderName>`. The first time a build that calls the folder "island4mac"
    /// runs, it takes over the folder the app kept as "MacDynamicIsland", so plugins and their data stay
    nonisolated static let supportFolder: URL = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = applicationSupport.appendingPathComponent(supportFolderName, isDirectory: true)
        let former = applicationSupport.appendingPathComponent(isDevBuild ? "MacDynamicIsland Dev" : "MacDynamicIsland", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path), FileManager.default.fileExists(atPath: former.path) {
            try? FileManager.default.moveItem(at: former, to: folder)
        }
        return folder
    }()
}
