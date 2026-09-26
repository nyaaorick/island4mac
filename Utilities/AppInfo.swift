import Combine
import Foundation
import AppKit

/// App information and version utilities
struct AppInfo {
    static let shared = AppInfo()
    
    private init() {}
    
    // MARK: - Version Info
    
    var version: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildNumber: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var fullVersion: String {
        return "\(version) (\(buildNumber))"
    }
    
    // MARK: - App Info
    
    var appName: String {
        return Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Mac Dynamic Island"
    }
    
    var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.macdynamicisland.app"
    }
    
    var displayName: String {
        return Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? appName
    }
    
    // MARK: - Paths
    
    var appSupportDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(appName)
        
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }
    
    var cacheDirectory: URL {
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCache = caches.appendingPathComponent(appName)
        
        try? fileManager.createDirectory(at: appCache, withIntermediateDirectories: true)
        return appCache
    }
    
    var logDirectory: URL {
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logs = library.appendingPathComponent("Logs").appendingPathComponent(appName)
        
        try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs
    }
    
    // MARK: - System Info
    
    var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    var machineName: String {
        return Host.current().localizedName ?? "Mac"
    }
    
    var systemUptime: TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }
    
    // MARK: - Launch Info
    
    var isFirstLaunch: Bool {
        return !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    
    func markAsLaunched() {
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
    }
    
    var launchCount: Int {
        return UserDefaults.standard.integer(forKey: "launchCount")
    }
    
    func incrementLaunchCount() {
        let count = launchCount + 1
        UserDefaults.standard.set(count, forKey: "launchCount")
    }
    
    // MARK: - Debug Info
    
    func printDebugInfo() {
        print("""
        =====================================
        App Debug Information
        =====================================
        Name: \(appName)
        Version: \(fullVersion)
        Bundle ID: \(bundleIdentifier)
        macOS: \(macOSVersion)
        Machine: \(machineName)
        First Launch: \(isFirstLaunch)
        Launch Count: \(launchCount)
        =====================================
        """)
    }
    
    var debugInfo: [String: Any] {
        return [
            "appName": appName,
            "version": version,
            "buildNumber": buildNumber,
            "bundleIdentifier": bundleIdentifier,
            "macOSVersion": macOSVersion,
            "machineName": machineName,
            "isFirstLaunch": isFirstLaunch,
            "launchCount": launchCount,
            "systemUptime": systemUptime
        ]
    }
}
