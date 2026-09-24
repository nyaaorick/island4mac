import Foundation
import os

/// Feature flags for gradual rollouts and A/B testing
class FeatureFlags {
    static let shared = FeatureFlags()
    
    private let defaults = UserDefaults.standard
    private let prefix = "feature_flag_"
    
    private init() {
        registerDefaultFlags()
    }
    
    // MARK: - Flag Definitions
    
    enum Flag: String, CaseIterable {
        // Music
        case musicPlayer = "music_player"
        case spotifyIntegration = "spotify_integration"
        case youtubeMusicIntegration = "youtube_music_integration"
        case lyricsSupport = "lyrics_support"
        
        // UI Features
        case newShelfUI = "new_shelf_ui"
        case compactMode = "compact_mode"
        case customThemes = "custom_themes"
        case animations = "animations"
        
        // System Features
        case batteryMonitoring = "battery_monitoring"
        case cameraIntegration = "camera_integration"
        case screenshotTools = "screenshot_tools"
        
        // Advanced
        case mediaKeyInterception = "media_key_interception"
        case fullscreenDetection = "fullscreen_detection"
        case xpcHelper = "xpc_helper"
        
        // Experimental
        case experimentalFeatures = "experimental_features"
        case betaFeatures = "beta_features"
        
        var defaultValue: Bool {
            switch self {
            // Stable features enabled by default
            case .musicPlayer, .batteryMonitoring, .animations:
                return true
            // Integration features opt-in
            case .spotifyIntegration, .youtubeMusicIntegration:
                return true
            // Advanced features opt-in
            case .mediaKeyInterception, .fullscreenDetection:
                return false
            // Experimental disabled by default
            case .experimentalFeatures, .betaFeatures:
                return false
            // Other features
            default:
                return true
            }
        }
        
        var description: String {
            switch self {
            case .musicPlayer: return "Music Player Integration"
            case .spotifyIntegration: return "Spotify Support"
            case .youtubeMusicIntegration: return "YouTube Music Support"
            case .lyricsSupport: return "Lyrics Display"
            case .newShelfUI: return "New Shelf Interface"
            case .compactMode: return "Compact Display Mode"
            case .customThemes: return "Custom Themes"
            case .animations: return "UI Animations"
            case .batteryMonitoring: return "Battery Monitoring"
            case .cameraIntegration: return "Camera Integration"
            case .screenshotTools: return "Screenshot Tools"
            case .mediaKeyInterception: return "Media Key Control"
            case .fullscreenDetection: return "Fullscreen Auto-Hide"
            case .xpcHelper: return "XPC Helper Service"
            case .experimentalFeatures: return "Experimental Features"
            case .betaFeatures: return "Beta Features"
            }
        }
    }
    
    // MARK: - Registration
    
    private func registerDefaultFlags() {
        for flag in Flag.allCases {
            let key = prefix + flag.rawValue
            if defaults.object(forKey: key) == nil {
                defaults.set(flag.defaultValue, forKey: key)
            }
        }
    }
    
    // MARK: - Access
    
    func isEnabled(_ flag: Flag) -> Bool {
        let key = prefix + flag.rawValue
        return defaults.bool(forKey: key)
    }
    
    func setEnabled(_ flag: Flag, enabled: Bool) {
        let key = prefix + flag.rawValue
        defaults.set(enabled, forKey: key)
        
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "FeatureFlags")
        logger.info("Feature flag \(flag.rawValue, privacy: .public) set to \(enabled, privacy: .public)")
        
        // Post notification for observers
        NotificationCenter.default.post(
            name: .featureFlagChanged,
            object: self,
            userInfo: ["flag": flag, "enabled": enabled]
        )
    }
    
    func resetToDefaults() {
        for flag in Flag.allCases {
            setEnabled(flag, enabled: flag.defaultValue)
        }
    }
    
    // MARK: - Batch Operations
    
    func enableAll() {
        for flag in Flag.allCases {
            setEnabled(flag, enabled: true)
        }
    }
    
    func disableAll() {
        for flag in Flag.allCases {
            setEnabled(flag, enabled: false)
        }
    }
    
    func getAllFlags() -> [Flag: Bool] {
        var result: [Flag: Bool] = [:]
        for flag in Flag.allCases {
            result[flag] = isEnabled(flag)
        }
        return result
    }
    
    // MARK: - Debug
    
    func printAllFlags() {
        print("=====================================")
        print("Feature Flags Status")
        print("=====================================")
        
        for flag in Flag.allCases {
            let status = isEnabled(flag) ? "✓" : "✗"
            print("\(status) \(flag.description): \(flag.rawValue)")
        }
        
        print("=====================================")
    }
}

// MARK: - Notification

extension Notification.Name {
    static let featureFlagChanged = Notification.Name("featureFlagChanged")
}

// MARK: - Convenience

extension FeatureFlags {
    var isMusicEnabled: Bool { isEnabled(.musicPlayer) }
    var isSpotifyEnabled: Bool { isEnabled(.spotifyIntegration) }
    var isYouTubeMusicEnabled: Bool { isEnabled(.youtubeMusicIntegration) }
    var isBatteryEnabled: Bool { isEnabled(.batteryMonitoring) }
    var areAnimationsEnabled: Bool { isEnabled(.animations) }
}
