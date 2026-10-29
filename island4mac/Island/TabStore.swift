import Foundation
import Combine
import SwiftUI

/// Which tabs the open island shows, and in what order: up to six (the room beside the camera), from the
/// built-in ones and the installed plugins'. Picked under Settings > Tabs
@MainActor
final class TabStore: ObservableObject {
    static let shared = TabStore()

    /// Three tabs fit either side of the camera
    static let maxEnabled = 6

    struct TabInfo: Equatable {
        let name: String
        /// SF Symbol
        let symbol: String
    }

    /// Plugin tabs, in the order PluginStore found the plugins
    @Published private(set) var pluginTabs: [IslandTab] = []
    /// The tabs the island shows, in order: never empty, never more than maxEnabled
    @Published private(set) var enabledTabs: [IslandTab] = IslandTab.builtIn

    private var pluginInfo: [IslandTab: TabInfo] = [:]
    /// The order you saved, kept as is: a plugin's tab stays in it while the plugin hasn't loaded yet
    private var savedIDs: [String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedIDs = defaults.stringArray(forKey: SettingsDefaults.enabledTabs.key) ?? SettingsDefaults.enabledTabs.defaultValue
        enabledTabs = resolve()
    }

    /// Every tab you can pick: the built-in ones, then the plugins'
    var availableTabs: [IslandTab] { IslandTab.builtIn + pluginTabs }

    func isEnabled(_ tab: IslandTab) -> Bool { enabledTabs.contains(tab) }

    /// Whether you may switch this tab on or off: the last tab can't go, and a seventh can't come
    func canToggle(_ tab: IslandTab) -> Bool {
        isEnabled(tab) ? enabledTabs.count > 1 : enabledTabs.count < Self.maxEnabled
    }

    func info(for tab: IslandTab) -> TabInfo {
        switch tab {
        case .music: return TabInfo(name: L("tab.music"), symbol: "music.note")
        case .clipboard: return TabInfo(name: L("tab.clipboard"), symbol: "doc.on.clipboard")
        case .files: return TabInfo(name: L("tab.files"), symbol: "folder")
        case .agents: return TabInfo(name: L("tab.agents"), symbol: "terminal")
        default: return pluginInfo[tab] ?? TabInfo(name: tab.pluginID ?? tab.rawValue, symbol: "puzzlepiece.extension")
        }
    }

    func setEnabled(_ tab: IslandTab, _ enabled: Bool) {
        guard enabled != isEnabled(tab), canToggle(tab) else { return }
        var tabs = enabledTabs
        if enabled { tabs.append(tab) } else { tabs.removeAll { $0 == tab } }
        save(tabs)
    }

    /// Moves enabled tabs, as List's onMove reports it
    func moveEnabled(fromOffsets source: IndexSet, toOffset destination: Int) {
        var tabs = enabledTabs
        tabs.move(fromOffsets: source, toOffset: destination)
        save(tabs)
    }

    /// The installed plugins' tabs. A tab you enabled comes back when its plugin is installed again
    func setPluginTabs(_ tabs: [(tab: IslandTab, info: TabInfo)]) {
        pluginInfo = Dictionary(tabs.map { ($0.tab, $0.info) }, uniquingKeysWith: { first, _ in first })
        pluginTabs = tabs.map(\.tab)
        enabledTabs = resolve()
    }

    private func save(_ tabs: [IslandTab]) {
        // Saved tabs of plugins that aren't loaded right now keep their place at the end
        let unavailable = savedIDs.filter { id in !availableTabs.contains(IslandTab(rawValue: id)) }
        savedIDs = tabs.map(\.rawValue) + unavailable
        defaults.set(savedIDs, forKey: SettingsDefaults.enabledTabs.key)
        enabledTabs = resolve()
    }

    private func resolve() -> [IslandTab] {
        var seen = Set<IslandTab>()
        let tabs = savedIDs.map(IslandTab.init(rawValue:))
            .filter { availableTabs.contains($0) && seen.insert($0).inserted }
        let capped = Array(tabs.prefix(Self.maxEnabled))
        return capped.isEmpty ? [IslandTab.builtIn[0]] : capped
    }
}
