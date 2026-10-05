//
//  Defaults+Keys.swift
//  MacDynamicIsland
//
//  UserDefaults wrapper (replaces Defaults library)
//

import Foundation
import Combine
import ServiceManagement
import SwiftUI

// MARK: - Native UserDefaults Wrapper

struct SettingsKey<T> {
    let key: String
    let defaultValue: T
}

final class SettingsDefaults: ObservableObject {
    static let shared = SettingsDefaults()
    private init() {}
    
    // Broadcast changes for SwiftUI
    let objectWillChange = ObservableObjectPublisher()
    
    // MARK: - General Settings
    static let menubarIcon = SettingsKey(key: "menubarIcon", defaultValue: true)
    static let openNotchOnHover = SettingsKey(key: "openNotchOnHover", defaultValue: true)
    static let minimumHoverDuration = SettingsKey(key: "minimumHoverDuration", defaultValue: 0.2)
    static let enableHaptics = SettingsKey(key: "enableHaptics", defaultValue: true)
    static let enableShadow = SettingsKey(key: "enableShadow", defaultValue: true)
    
    // MARK: - Appearance
    static let cornerRadiusScaling = SettingsKey(key: "cornerRadiusScaling", defaultValue: 1.0)
    static let lightingEffect = SettingsKey(key: "lightingEffect", defaultValue: true)
    static let enableGradient = SettingsKey(key: "enableGradient", defaultValue: true)
    
    // MARK: - Music
    static let showMusicLiveActivity = SettingsKey(key: "showMusicLiveActivity", defaultValue: true)
    static let playerColorTinting = SettingsKey(key: "playerColorTinting", defaultValue: true)
    static let coloredSpectrogram = SettingsKey(key: "coloredSpectrogram", defaultValue: true)
    static let useMusicVisualizer = SettingsKey(key: "useMusicVisualizer", defaultValue: true)
    static let enableLyrics = SettingsKey(key: "enableLyrics", defaultValue: true)
    /// Read once to carry it over to the Music plugin's preferences (AppIntegration)
    static let lyricsSource = SettingsKey(key: "lyricsSource", defaultValue: "auto")
    static let musicControlSlotLimit = SettingsKey(key: "musicControlSlotLimit", defaultValue: 5)
    static let sliderColor = SettingsKey(key: "sliderColor", defaultValue: "white")

    // MARK: - Clipboard
    // The clipboard's settings before it was a plugin, read once to carry them over to its preferences (AppIntegration)
    static let clipboardMaxItems = SettingsKey(key: "clipboardMaxItems", defaultValue: 50)
    /// 0: forever
    static let clipboardKeepHours = SettingsKey(key: "clipboardKeepHours", defaultValue: 24)

    // MARK: - Gestures
    static let enableGestures = SettingsKey(key: "enableGestures", defaultValue: true)
    
    // MARK: - Claude Code
    // The built-in Agents' settings, read once to carry them over to the Agents plugin's (AppIntegration)
    static let showAgentLiveActivity = SettingsKey(key: "showAgentLiveActivity", defaultValue: true)
    static let agentSoundsEnabled = SettingsKey(key: "agentSoundsEnabled", defaultValue: true)
    static let agentPromptsOpenIsland = SettingsKey(key: "agentPromptsOpenIsland", defaultValue: true)

    // MARK: - Plugins
    static let showPluginLiveActivity = SettingsKey(key: "showPluginLiveActivity", defaultValue: true)
    /// A plugin may open the island on its tab ({"type":"open"}), at most every PluginStore.openInterval
    static let pluginsMayOpenIsland = SettingsKey(key: "pluginsMayOpenIsland", defaultValue: true)
    /// index.json of the plugins repo (PluginCatalogClient)
    static let pluginIndexURL = SettingsKey(key: "pluginIndexURL", defaultValue: "https://raw.githubusercontent.com/nyaaorick/island4mac-plugins/main/index.json")

    // MARK: - Display
    static let showOnAllDisplays = SettingsKey(key: "showOnAllDisplays", defaultValue: false)
    /// UUID of the display chosen for the island (NSScreen.displayUUID); empty: the built-in display
    static let preferredDisplayUUID = SettingsKey(key: "preferredDisplayUUID", defaultValue: "")
    static let automaticallySwitchDisplay = SettingsKey(key: "automaticallySwitchDisplay", defaultValue: true)
    /// Hide the island on a display while the app that's playing shows its video there in full screen
    static let hideForFullScreenVideo = SettingsKey(key: "hideForFullScreenVideo", defaultValue: true)

    // MARK: - Advanced
    static let settingsIconInNotch = SettingsKey(key: "settingsIconInNotch", defaultValue: true)
    static let showNotHumanFace = SettingsKey(key: "showNotHumanFace", defaultValue: true)
    
    // MARK: - Sizing & Behavior
    static let nonNotchHeight = SettingsKey(key: "nonNotchHeight", defaultValue: 32.0)
    /// IslandTab raw values of the tabs the island shows, in order (TabStore)
    static let enabledTabs = SettingsKey(key: "enabledTabs", defaultValue: IslandTab.builtIn.map(\.rawValue))
    static let rememberLastTab = SettingsKey(key: "rememberLastTab", defaultValue: false)
    static let autoCloseEnabled = SettingsKey(key: "autoCloseEnabled", defaultValue: false)
    static let autoCloseTimeout = SettingsKey(key: "autoCloseTimeout", defaultValue: 5.0)
    
    // MARK: - App Customization
    static let islandBackgroundColor = SettingsKey(key: "islandBackgroundColor", defaultValue: "black")
    /// IslandTheme raw value
    static let islandTheme = SettingsKey(key: "islandTheme", defaultValue: IslandTheme.standard.rawValue)
    static let launchAtLogin = SettingsKey(key: "launchAtLogin", defaultValue: false)

    // Getters/setters for non-primitive types
    func get<T>(_ key: SettingsKey<T>) -> T {
        if let value = UserDefaults.standard.object(forKey: key.key) as? T {
            return value
        }
        return key.defaultValue
    }
    
    func set<T>(_ key: SettingsKey<T>, value: T) {
        objectWillChange.send()
        UserDefaults.standard.set(value, forKey: key.key)
        
        // Handle specific side effects
        if key.key == "launchAtLogin" {
            if let enabled = value as? Bool {
                saveLaunchAtLogin(enabled)
            }
        }
    }
    
    private func saveLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Error updating launch at login: \(error)")
            }
        }
    }
    
    func resolveTheme() -> IslandTheme {
        IslandTheme(rawValue: get(SettingsDefaults.islandTheme)) ?? .standard
    }

    // Resolve color string to SwiftUI Color
    func resolveBackgroundColor() -> Color {
        let colorName = get(SettingsDefaults.islandBackgroundColor)
        switch colorName.lowercased() {
        case "black": return .black
        case "darkgray": return Color(white: 0.1)
        case "deepblue": return Color(red: 0.0, green: 0.0, blue: 0.2)
        case "deepred": return Color(red: 0.2, green: 0.0, blue: 0.0)
        default: return .black
        }
    }
}
