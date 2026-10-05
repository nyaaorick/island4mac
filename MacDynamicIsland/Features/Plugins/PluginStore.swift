import Foundation
import Combine
import Darwin
import os

/// The installed plugins and what each wants shown. A plugin runs (PluginClient) while its tab is one of
/// your tabs; its compact content and popups take the slot beside the notch after agents (popups also ahead of
/// now playing, PluginCompact after it)
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore(pluginsFolder: defaultFolder, dataFolder: defaultDataFolder, tabs: .shared)

    /// What one plugin last asked to show
    struct Content: Equatable {
        var compact: PluginCompact?
        var rows: [PluginRow] = []
        var buttons: [PluginButton] = []
        var input: PluginInput?
    }

    /// Whether a plugin of one of your tabs is running, or why it isn't
    enum Status: Equatable {
        case running
        case stopped(reason: String)
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
    /// Whether each plugin of your tabs runs, or why it stopped for good; shown in its tab and in Settings
    @Published private(set) var statuses: [String: Status] = [:]

    /// `~/Library/Application Support/MacDynamicIsland/Plugins`: one folder per plugin
    let pluginsFolder: URL
    /// `~/Library/Application Support/MacDynamicIsland/PluginData`: one folder per plugin for what it keeps
    /// (ISLAND_DATA_DIR), apart from its install folder so an update doesn't wipe it
    let dataFolder: URL
    /// Opens the island on a plugin's tab ({"type":"open"}); IslandController sets it
    var onOpen: (String) -> Void = { _ in }

    /// One plugin opens the island at most this often
    static let openInterval: TimeInterval = 10

    private let tabs: TabStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Plugin")
    private var clients: [String: PluginClient] = [:]
    private var tabsCancellable: AnyCancellable?
    private var popupSerial = 0
    private var popupDismissal: DispatchWorkItem?
    /// How many of the islands show each plugin's tab right now (one per display with "all screens" on)
    private var visibleCounts: [String: Int] = [:]
    private var lastOpened: [String: Date] = [:]

    nonisolated static let defaultFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacDynamicIsland/Plugins", isDirectory: true)
    nonisolated static let defaultDataFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacDynamicIsland/PluginData", isDirectory: true)

    private let restartDelay: TimeInterval

    init(pluginsFolder: URL, dataFolder: URL, tabs: TabStore, restartDelay: TimeInterval = 1) {
        self.pluginsFolder = pluginsFolder
        self.dataFolder = dataFolder
        self.tabs = tabs
        self.restartDelay = restartDelay
    }

    func start() {
        try? FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
        killLeftovers()
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
        saveRunning()
    }

    /// For quitting the app: asks every plugin to quit, waits up to `timeout` seconds in all, then kills what's
    /// left with everything it started. Blocks, since nothing runs after the app quits
    func stopForQuit(timeout: TimeInterval = 0.5) {
        tabsCancellable = nil
        let processes = clients.values.compactMap(\.process)
        clients.values.forEach { $0.stopWithoutKilling() }
        clients.removeAll()
        for process in processes {
            process.closeInput()
            process.signalGroup(SIGTERM)
        }
        let deadline = Date().addingTimeInterval(timeout)
        for process in processes {
            _ = process.waitForExit(timeout: max(0, deadline.timeIntervalSinceNow))
            process.signalGroup(SIGKILL)
        }
        saveRunning()
    }

    /// Starts a plugin that stopped for good
    func restart(_ pluginID: String) {
        statuses[pluginID] = nil
        clients[pluginID]?.restart()
    }

    /// The running process of a plugin (also its process group)
    func processID(of pluginID: String) -> pid_t? {
        clients[pluginID]?.process?.pid
    }

    /// The data folder of one plugin, removed with the plugin
    func dataFolder(for pluginID: String) -> URL {
        dataFolder.appendingPathComponent(pluginID, isDirectory: true)
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
        statuses.removeAll()
        syncClients()
    }

    private func syncClients() {
        let wanted = Set(tabs.enabledTabs.compactMap(\.pluginID))
        for (id, client) in clients where !wanted.contains(id) {
            client.stop()
            clients[id] = nil
            contents[id] = nil
            statuses[id] = nil
        }
        for plugin in installed where wanted.contains(plugin.id) && clients[plugin.id] == nil {
            let client = PluginClient(manifest: plugin.manifest, folder: plugin.folder, dataFolder: dataFolder(for: plugin.id),
                                      restartDelay: restartDelay)
            client.onMessage = { [weak self] message in self?.apply(message, from: plugin.id) }
            client.onLaunch = { [weak self] in
                guard let self else { return }
                // A restarted process starts from scratch, so whatever the last one showed (a countdown) is stale
                self.contents[plugin.id] = nil
                self.statuses[plugin.id] = .running
                // It learns at once whether its tab is showing
                self.clients[plugin.id]?.send(.visible((self.visibleCounts[plugin.id] ?? 0) > 0))
                self.saveRunning()
            }
            client.onGiveUp = { [weak self] reason in
                self?.contents[plugin.id] = nil
                self?.statuses[plugin.id] = .stopped(reason: reason)
                self?.saveRunning()
            }
            clients[plugin.id] = client
            client.start()
        }
        saveRunning()
    }

    // MARK: - Tab visibility

    /// A plugin's tab came into view on one island. The plugin hears of it when the first one shows it
    func tabAppeared(_ pluginID: String) {
        let count = visibleCounts[pluginID, default: 0] + 1
        visibleCounts[pluginID] = count
        if count == 1 { send(.visible(true), to: pluginID) }
    }

    /// A plugin's tab left view on one island. The plugin hears of it once no island shows it
    func tabDisappeared(_ pluginID: String) {
        let count = max(0, visibleCounts[pluginID, default: 0] - 1)
        visibleCounts[pluginID] = count
        if count == 0 { send(.visible(false), to: pluginID) }
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
        case .input(let input): content.input = input
        case .clear(.input): content.input = nil
        case .clear(.all): content = Content()
        case .popup(let popup):
            show(popup, from: pluginID)
            return
        case .open:
            open(from: pluginID)
            return
        }
        if contents[pluginID] != content { contents[pluginID] = content }
    }

    /// Opens the island on the plugin's tab, when its tab is one of yours, you allow it, and it hasn't just done so
    private func open(from pluginID: String, now: Date = Date()) {
        guard SettingsDefaults.shared.get(SettingsDefaults.pluginsMayOpenIsland),
              tabs.isEnabled(.plugin(pluginID)) else { return }
        if let last = lastOpened[pluginID], now.timeIntervalSince(last) < Self.openInterval {
            logger.notice("Plugin \(pluginID, privacy: .public) asked to open the island again too soon; ignored")
            return
        }
        lastOpened[pluginID] = now
        onOpen(pluginID)
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

    // MARK: - Leftovers

    private var runningFile: URL { dataFolder.appendingPathComponent(".running.json") }

    private struct RunningEntry: Codable {
        let pid: Int32
        let path: String
    }

    /// Notes the running plugins, so a later launch can end any the app left behind if it crashed
    private func saveRunning() {
        let entries = clients.values.compactMap { client in
            client.process.map { RunningEntry(pid: $0.pid, path: client.manifest.executableURL(in: client.folder).path) }
        }
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: runningFile, options: .atomic)
    }

    /// Ends plugins (and what they started) that a crashed app left running. Only a process still running the
    /// plugin's program is ended, so a reused process id is left alone
    private func killLeftovers() {
        guard let data = try? Data(contentsOf: runningFile),
              let entries = try? JSONDecoder().decode([RunningEntry].self, from: data) else { return }
        for entry in entries where Self.executablePath(of: entry.pid) == entry.path {
            logger.notice("Ending plugin process \(entry.pid) left from the last run")
            _ = kill(-entry.pid, SIGKILL)
        }
        try? FileManager.default.removeItem(at: runningFile)
    }

    nonisolated static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
