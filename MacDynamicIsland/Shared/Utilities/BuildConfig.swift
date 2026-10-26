import Foundation

/// Build configuration and environment settings
struct BuildConfig {
    
    /// True while the app is hosting unit tests: skip anything that talks to other apps or asks for permissions
    static var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The Debug configuration builds the dev app (`com.macdynamicisland.app.dev`, "Mac Dynamic Island Dev"): a separate
    /// app from the installed release, with its own settings, files, permissions and agents socket (CLAUDE.md, "Dev builds")
    nonisolated static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    /// The app's folder in Application Support, for plugins and their data
    nonisolated static var supportFolderName: String {
        isDevBuild ? "MacDynamicIsland Dev" : "MacDynamicIsland"
    }
}
