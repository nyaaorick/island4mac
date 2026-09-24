import Foundation
import AppKit

/// Build configuration and environment settings
struct BuildConfig {
    
    // MARK: - Environment
    
    enum Environment {
        case development
        case staging
        case production
        
        static var current: Environment {
            #if DEBUG
            return .development
            #elseif STAGING
            return .staging
            #else
            return .production
            #endif
        }
        
        var name: String {
            switch self {
            case .development: return "Development"
            case .staging: return "Staging"
            case .production: return "Production"
            }
        }
    }
    
    // MARK: - Features
    
    static var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    static var enableLogging: Bool {
        return isDebugMode || UserDefaults.standard.bool(forKey: "enableLogging")
    }
    
    static var enableAnalytics: Bool {
        return Environment.current == .production
    }
    
    static var enableCrashReporting: Bool {
        return true
    }
    
    static var enablePerformanceMonitoring: Bool {
        return isDebugMode
    }

    /// True while the app is hosting unit tests: skip anything that talks to other apps or asks for permissions
    static var isRunningUnitTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    // MARK: - API Configuration
    
    static var apiBaseURL: String {
        switch Environment.current {
        case .development:
            return "http://localhost:8080"
        case .staging:
            return "https://staging-api.example.com"
        case .production:
            return "https://api.example.com"
        }
    }
    
    static var apiTimeout: TimeInterval {
        return 30.0
    }
    
    // MARK: - Cache Configuration
    
    static var cacheEnabled: Bool {
        return true
    }
    
    static var cacheDuration: TimeInterval {
        return 86400 // 24 hours
    }
    
    static var maxCacheSize: Int {
        return 100 * 1024 * 1024 // 100 MB
    }
    
    // MARK: - UI Configuration
    
    static var animationsEnabled: Bool {
        return !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    
    static var defaultAnimationDuration: Double {
        return 0.3
    }
    
    static var notchWidth: CGFloat {
        return 300
    }
    
    static var notchHeight: CGFloat {
        return 32
    }
    
    static var expandedNotchHeight: CGFloat {
        return 200
    }
    
    // MARK: - Limits
    
    static var maxShelfItems: Int {
        return 50
    }
    
    static var maxFileSize: Int64 {
        return 100 * 1024 * 1024 // 100 MB
    }
    
    static var maxConcurrentDownloads: Int {
        return 3
    }
    
    // MARK: - Intervals
    
    static var batteryUpdateInterval: TimeInterval {
        return 30.0
    }
    
    static var musicUpdateInterval: TimeInterval {
        return 1.0
    }
    
    static var clipboardPollInterval: TimeInterval {
        return 0.6
    }
    
    // MARK: - Debug
    
    static func printConfiguration() {
        print("""
        =====================================
        Build Configuration
        =====================================
        Environment: \(Environment.current.name)
        Debug Mode: \(isDebugMode)
        App Version: \(AppInfo.shared.fullVersion)
        
        Features:
        - Logging: \(enableLogging)
        - Analytics: \(enableAnalytics)
        - Crash Reporting: \(enableCrashReporting)
        - Performance Monitoring: \(enablePerformanceMonitoring)
        
        API:
        - Base URL: \(apiBaseURL)
        - Timeout: \(apiTimeout)s
        
        Cache:
        - Enabled: \(cacheEnabled)
        - Duration: \(cacheDuration)s
        - Max Size: \(maxCacheSize / 1024 / 1024) MB
        
        UI:
        - Animations: \(animationsEnabled)
        - Notch Size: \(notchWidth)x\(notchHeight)
        =====================================
        """)
    }
}
