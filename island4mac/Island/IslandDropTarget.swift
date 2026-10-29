import Foundation

/// Which tabs take what you drop on the island: those whose plugin's plugin.json "accepts" files (protocol 5),
/// the bundled Files plugin among them. The island does the dragging part for all of them: it opens on the first such
/// tab when a drag nears the notch, shows where to drop (IslandDropZone), reads the drop and hands it over
@MainActor
enum IslandDropTarget {
    /// Whether this tab takes drops
    static func accepts(_ tab: IslandTab, plugins: PluginStore = .shared) -> Bool {
        guard let pluginID = pluginID(of: tab, plugins: plugins) else { return false }
        return plugins.installed.first { $0.id == pluginID }?.manifest.acceptsFiles == true && plugins.isEnabled(pluginID)
    }

    /// The tab a drag goes to: the one showing if it takes drops, or else the first of your tabs that does
    static func tab(preferring current: IslandTab?, tabs: TabStore = .shared, plugins: PluginStore = .shared) -> IslandTab? {
        if let current, tabs.isEnabled(current), accepts(current, plugins: plugins) { return current }
        return tabs.enabledTabs.first { accepts($0, plugins: plugins) }
    }

    /// Where text dropped on a tab is saved: its plugin's data folder (Drops/)
    static func textFolder(for tab: IslandTab, plugins: PluginStore = .shared) -> URL {
        let owner = pluginID(of: tab, plugins: plugins) ?? "files"
        return plugins.dataFolder.appendingPathComponent(owner, isDirectory: true).appendingPathComponent("Drops", isDirectory: true)
    }

    /// The last drop handed over, so one that arrives twice (SwiftUI's drop and the drag monitor's) counts once
    private static var lastDelivered: (drop: IslandDrop, at: Date)?

    static func deliver(_ drop: IslandDrop, to tab: IslandTab, plugins: PluginStore = .shared) {
        guard !drop.isEmpty else { return }
        if let last = lastDelivered, last.drop == drop, Date().timeIntervalSince(last.at) < 2 { return }
        lastDelivered = (drop, Date())
        guard let pluginID = pluginID(of: tab, plugins: plugins) else { return }
        plugins.send(.drop(paths: drop.paths, urls: drop.urls), to: pluginID)
    }

    /// The plugin drawing a tab: a plugin tab's, or the one that took over a built-in tab
    private static func pluginID(of tab: IslandTab, plugins: PluginStore) -> String? {
        tab.pluginID ?? plugins.replacesBuiltInTab(tab)
    }
}
