import Foundation

/// Build configuration and environment settings
struct BuildConfig {
    
    /// True while the app is hosting unit tests: skip anything that talks to other apps or asks for permissions
    static var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
