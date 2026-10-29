import Foundation
import Combine
import os
import ServiceManagement
import SwiftUI

/// One setting in UserDefaults: its key and what it is until set
struct SettingsKey<T> {
    let key: String
    let defaultValue: T
}

/// The app's settings, read and written through typed keys. Every key here has an effect somewhere: a key with
/// none is deleted, not kept for later
final class SettingsDefaults: ObservableObject {
    static let shared = SettingsDefaults()
    private init() {}

    /// Sent before any setting changes, so SwiftUI views that observe the store redraw
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - General
    static let launchAtLogin = SettingsKey(key: "launchAtLogin", defaultValue: false)
    static let openNotchOnHover = SettingsKey(key: "openNotchOnHover", defaultValue: true)
    static let minimumHoverDuration = SettingsKey(key: "minimumHoverDuration", defaultValue: 0.2)
    static let enableHaptics = SettingsKey(key: "enableHaptics", defaultValue: true)
    static let enableGestures = SettingsKey(key: "enableGestures", defaultValue: true)
    static let autoCloseEnabled = SettingsKey(key: "autoCloseEnabled", defaultValue: false)
    static let autoCloseTimeout = SettingsKey(key: "autoCloseTimeout", defaultValue: 5.0)

    // MARK: - Display
    static let showOnAllDisplays = SettingsKey(key: "showOnAllDisplays", defaultValue: false)
    /// UUID of the display chosen for the island (NSScreen.displayUUID); empty: the built-in display
    static let preferredDisplayUUID = SettingsKey(key: "preferredDisplayUUID", defaultValue: "")
    static let automaticallySwitchDisplay = SettingsKey(key: "automaticallySwitchDisplay", defaultValue: true)
    /// Hide the island on a display while the app that's playing shows its video there in full screen
    static let hideForFullScreenVideo = SettingsKey(key: "hideForFullScreenVideo", defaultValue: true)
    /// Height of the collapsed island on a display without a notch
    static let nonNotchHeight = SettingsKey(key: "nonNotchHeight", defaultValue: 32.0)

    // MARK: - Appearance
    /// IslandTheme raw value
    static let islandTheme = SettingsKey(key: "islandTheme", defaultValue: IslandTheme.standard.rawValue)
    static let islandBackgroundColor = SettingsKey(key: "islandBackgroundColor", defaultValue: "black")
    static let cornerRadiusScaling = SettingsKey(key: "cornerRadiusScaling", defaultValue: 1.0)

    // MARK: - Music, as the island draws it (where it comes from is the Music plugin's preference)
    static let showMusicLiveActivity = SettingsKey(key: "showMusicLiveActivity", defaultValue: true)
    static let playerColorTinting = SettingsKey(key: "playerColorTinting", defaultValue: true)
    static let useMusicVisualizer = SettingsKey(key: "useMusicVisualizer", defaultValue: true)
    static let enableLyrics = SettingsKey(key: "enableLyrics", defaultValue: true)

    // MARK: - Tabs and plugins
    /// IslandTab raw values of the tabs the island shows, in order (TabStore)
    static let enabledTabs = SettingsKey(key: "enabledTabs", defaultValue: IslandTab.builtIn.map(\.rawValue))
    static let showPluginLiveActivity = SettingsKey(key: "showPluginLiveActivity", defaultValue: true)
    /// A plugin may open the island on its tab ({"type":"open"}), at most every PluginStore.openInterval
    static let pluginsMayOpenIsland = SettingsKey(key: "pluginsMayOpenIsland", defaultValue: true)
    /// index.json of the plugin catalog (PluginCatalogClient); the plugins repo's by default
    static let pluginIndexURL = SettingsKey(key: "pluginIndexURL", defaultValue: "https://raw.githubusercontent.com/nyaaorick/island4mac-plugins/main/index.json")

    func get<T>(_ key: SettingsKey<T>) -> T {
        if let value = UserDefaults.standard.object(forKey: key.key) as? T { return value }
        return key.defaultValue
    }

    func set<T>(_ key: SettingsKey<T>, value: T) {
        objectWillChange.send()
        UserDefaults.standard.set(value, forKey: key.key)
        if key.key == Self.launchAtLogin.key, let enabled = value as? Bool {
            setLaunchAtLogin(enabled)
        }
    }

    /// Registers or unregisters the app as a login item; the setting shows what was asked for
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger(subsystem: Log.subsystem, category: "Settings").error("Launch at login: \(String(describing: error), privacy: .public)")
        }
    }

    func resolveTheme() -> IslandTheme {
        IslandTheme(rawValue: get(SettingsDefaults.islandTheme)) ?? .standard
    }

    /// The default theme's background, from its name
    func resolveBackgroundColor() -> Color {
        switch get(SettingsDefaults.islandBackgroundColor).lowercased() {
        case "darkgray": return Color(white: 0.1)
        case "deepblue": return Color(red: 0.0, green: 0.0, blue: 0.2)
        case "deepred": return Color(red: 0.2, green: 0.0, blue: 0.0)
        default: return .black
        }
    }
}
