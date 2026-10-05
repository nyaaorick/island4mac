import Foundation

/// One tab of the open island: one of the four built in, or a plugin's. TabStore keeps which are shown
struct IslandTab: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let music = IslandTab(rawValue: "music")
    static let clipboard = IslandTab(rawValue: "clipboard")
    static let files = IslandTab(rawValue: "files")
    static let agents = IslandTab(rawValue: "agents")

    /// The built-in tabs, in their default order
    static let builtIn: [IslandTab] = [.music, .clipboard, .files, .agents]

    private static let pluginPrefix = "plugin."

    /// The tab of the plugin with this id (PluginManifest.id)
    static func plugin(_ id: String) -> IslandTab {
        IslandTab(rawValue: pluginPrefix + id)
    }

    /// Plugins that ship in the app and draw a built-in tab: its place and name stay yours
    static let builtInTabsOfPlugins: [String: IslandTab] = ["agents": .agents]

    /// Where a plugin shows: the built-in tab it took over, or a tab of its own
    static func tab(forPlugin id: String) -> IslandTab {
        builtInTabsOfPlugins[id] ?? plugin(id)
    }

    /// The plugin this tab belongs to; nil for a built-in tab
    var pluginID: String? {
        rawValue.hasPrefix(Self.pluginPrefix) ? String(rawValue.dropFirst(Self.pluginPrefix.count)) : nil
    }
}

@MainActor
extension IslandTab {
    var displayName: String { TabStore.shared.info(for: self).name }
    var iconName: String { TabStore.shared.info(for: self).symbol }
}
