import Foundation

/// App information and version utilities
struct AppInfo {
    static let shared = AppInfo()
    
    private init() {}
    
    // MARK: - System Info
    
    var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
