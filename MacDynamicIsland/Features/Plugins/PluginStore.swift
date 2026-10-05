import Foundation
import Combine
import os

/// The installed plugins and what each wants shown. A plugin runs (PluginClient) while its tab is one of
/// your tabs; its compact content and popups take the slot beside the notch after agents (popups also ahead of
/// now playing, PluginCompact after it)
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore(pluginsFolder: defaultFolder, tabs: .shared)

    /// What one plugin last asked to show
    struct Content: Equatable {
        var compact: PluginCompact?
        var rows: [PluginRow] = []
        var buttons: [PluginButton] = []
    }

    struct Installed: Identifiable, Equatable {
        let manifest: PluginManifest
        let folder: URL
        var id: String { manifest.id }
    }

    struct ActivePopup: Equatable {
        let pluginID: String
        let popup: PluginPopup
        /// Tells two equal popups in a row apart, so the second one restarts the timer
        let serial: Int
    }

    @Published private(set) var installed: [Installed] = []
    /// Folders in the plugins folder that aren't usable plugins, with the reason (shown in Settings)
    @Published private(set) var broken: [(folder: String, reason: String)] = []
    @Published private(set) var contents: [String: Content] = [:]
    @Published private(set) var popup: ActivePopup?

    /// `~/Library/Application Support/MacDynamicIsland/Plugins`: one folder per plugin
    let pluginsFolder: URL

    private let tabs: TabStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Plugin")
    private var clients: [String: PluginClient] = [:]
    private var tabsCancellable: AnyCancellable?
    private var popupSerial = 0
    private var popupDismissal: DispatchWorkItem?

    nonisolated static let defaultFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacDynamicIsland/Plugins", isDirectory: true)

    init(pluginsFolder: URL, tabs: TabStore) {
        self.pluginsFolder = pluginsFolder
        self.tabs = tabs
    }

    func start() {
        // Writing to a plugin that has just exited must not kill the app
        signal(SIGPIPE, SIG_IGN)
        try? FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
        reload()
        // Runs the plugins of the tabs you switch on, stops the ones you switch off. On the next turn:
        // @Published sends before the new list is stored
        tabsCancellable = tabs.$enabledTabs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncClients() }
    }

    func stop() {
        tabsCancellable = nil
        clients.values.forEach { $0.stop() }
        clients.removeAll()
    }

    /// Scans the plugins folder again, after an install, update or removal
    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: pluginsFolder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        var found: [Installed] = []
        var problems: [(folder: String, reason: String)] = []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                let manifest = try PluginManifest.load(from: folder)
                guard manifest.id == folder.lastPathComponent else {
                    problems.append((folder.lastPathComponent, "id \"\(manifest.id)\" doesn't match its folder"))
                    continue
                }
                found.append(Installed(manifest: manifest, folder: folder))
            } catch {
                problems.append((folder.lastPathComponent, String(describing: error)))
                logger.error("Plugin folder \(folder.lastPathComponent, privacy: .public) skipped: \(String(describing: error), privacy: .public)")
            }
        }
        installed = found
        broken = problems
        tabs.setPluginTabs(found.map { (IslandTab.plugin($0.id), TabStore.TabInfo(name: $0.manifest.name, symbol: $0.manifest.symbol)) })
        // Restart the ones whose files may have changed; what they showed goes with them
        clients.values.forEach { $0.stop() }
        clients.removeAll()
        contents.removeAll()
        syncClients()
    }

    private func syncClients() {
        let wanted = Set(tabs.enabledTabs.compactMap(\.pluginID))
        for (id, client) in clients where !wanted.contains(id) {
            client.stop()
            clients[id] = nil
            contents[id] = nil
        }
        for plugin in installed where wanted.contains(plugin.id) && clients[plugin.id] == nil {
            let client = PluginClient(manifest: plugin.manifest, folder: plugin.folder)
            client.onMessage = { [weak self] message in self?.apply(message, from: plugin.id) }
            // A restarted process starts from scratch, so whatever the last one showed (a countdown) is stale
            client.onLaunch = { [weak self] in self?.contents[plugin.id] = nil }
            client.onGiveUp = { [weak self] in self?.contents[plugin.id] = nil }
            clients[plugin.id] = client
            client.start()
        }
    }

    func send(_ event: PluginEvent, to pluginID: String) {
        clients[pluginID]?.send(event)
    }

    func apply(_ message: PluginMessage, from pluginID: String) {
        var content = contents[pluginID] ?? Content()
        switch message {
        case .compact(let compact): content.compact = compact
        case .list(let rows): content.rows = rows
        case .buttons(let buttons): content.buttons = buttons
        case .clear(.compact): content.compact = nil
        case .clear(.list): content.rows = []
        case .clear(.buttons): content.buttons = []
        case .clear(.all): content = Content()
        case .popup(let popup):
            show(popup, from: pluginID)
            return
        }
        if contents[pluginID] != content { contents[pluginID] = content }
    }

    private func show(_ popup: PluginPopup, from pluginID: String) {
        popupSerial += 1
        self.popup = ActivePopup(pluginID: pluginID, popup: popup, serial: popupSerial)
        popupDismissal?.cancel()
        let serial = popupSerial
        let dismissal = DispatchWorkItem { [weak self] in
            guard self?.popup?.serial == serial else { return }
            self?.popup = nil
        }
        popupDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + popup.duration, execute: dismissal)
    }

    // MARK: - Beside the notch

    /// The first of your plugin tabs that has something to show beside the notch
    var compactPlugin: (manifest: PluginManifest, compact: PluginCompact)? {
        for id in tabs.enabledTabs.compactMap(\.pluginID) {
            if let compact = contents[id]?.compact, let plugin = installed.first(where: { $0.id == id }) {
                return (plugin.manifest, compact)
            }
        }
        return nil
    }

    private var showsBesideNotch: Bool { SettingsDefaults.shared.get(SettingsDefaults.showPluginLiveActivity) }
    /// A popup to show beside the notch now
    var showsPopupLiveActivity: Bool { showsBesideNotch && popup != nil }
    /// Compact content to show beside the notch when nothing ahead of it needs the space
    var showsCompactContent: Bool { showsBesideNotch && compactPlugin != nil }
}
