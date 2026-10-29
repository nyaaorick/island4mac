import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import os

/// The plugin hub's state: the catalog (fetched from the index in Settings and kept on disk, so it shows at once
/// and offline), which installed plugins it has a newer version of, and the installs, updates and removals under
/// way. Settings > Plugins draws it; AppIntegration refreshes it at launch so the Plugins pane can show a badge
@MainActor
final class PluginCatalogStore: ObservableObject {
    static let shared = PluginCatalogStore(plugins: .shared, cacheFile: BuildConfig.supportFolder.appendingPathComponent("catalog.json"))

    /// An installed plugin the catalog has a newer version of
    struct Update: Identifiable, Equatable {
        let installed: PluginStore.Installed
        let entry: PluginCatalogEntry
        var id: String { entry.id }
    }

    @Published private(set) var entries: [PluginCatalogEntry] = []
    @Published private(set) var isLoading = false
    /// When the catalog was last read from its address
    @Published private(set) var fetched: Date?
    /// Why the catalog couldn't be read, said quietly: not published yet, or offline
    @Published private(set) var note: String?
    /// The plugins being installed, updated or removed, and where each is
    @Published private(set) var busy: [String: PluginCatalogClient.Phase] = [:]
    /// What the last install, update or removal did, or why it failed
    @Published private(set) var notice: Notice?
    /// Narrows the available plugins by name, description and author
    @Published var search = ""

    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    /// A catalog older than this is read again when the pane opens or the app starts
    static let staleAfter: TimeInterval = 6 * 3600

    private let plugins: PluginStore
    private let cacheFile: URL
    private let settings: SettingsDefaults
    private let logger = Logger(subsystem: Log.subsystem, category: "PluginCatalog")

    init(plugins: PluginStore, cacheFile: URL, settings: SettingsDefaults = .shared) {
        self.plugins = plugins
        self.cacheFile = cacheFile
        self.settings = settings
        loadCache()
    }

    var client: PluginCatalogClient {
        PluginCatalogClient(pluginsFolder: plugins.pluginsFolder, dataFolder: plugins.dataFolder)
    }

    var indexURL: URL? { URL(string: settings.get(SettingsDefaults.pluginIndexURL)) }

    // MARK: - What the catalog says about what's installed

    /// Installed plugins the catalog has a newer version of, in the catalog's order. Bundled plugins update with
    /// the app, never from the catalog
    var updates: [Update] {
        entries.compactMap { entry in
            guard entry.isSupported, let installed = plugins.installed.first(where: { $0.id == entry.id }), !installed.isBundled,
                  entry.isNewer(than: installed.manifest.version) else { return nil }
            return Update(installed: installed, entry: entry)
        }
    }

    func update(for pluginID: String) -> Update? { updates.first { $0.id == pluginID } }

    /// The catalog's plugins that aren't installed, narrowed by `search`
    var available: [PluginCatalogEntry] {
        let installed = Set(plugins.installed.map(\.id))
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            guard !installed.contains(entry.id) else { return false }
            guard !needle.isEmpty else { return true }
            return [entry.name, entry.description ?? "", entry.author ?? "", entry.id].contains { $0.lowercased().contains(needle) }
        }
    }

    // MARK: - Reading the catalog

    /// Takes these as the catalog (tests, and a catalog read some other way)
    func use(_ entries: [PluginCatalogEntry]) {
        self.entries = entries
        fetched = Date()
        note = nil
    }

    /// Reads the catalog again if it's old or was never read
    func refreshIfStale() async {
        if let fetched, Date().timeIntervalSince(fetched) < Self.staleAfter, !entries.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        guard let url = indexURL, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await client.session.data(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw status == 404 ? PluginCatalogClient.CatalogError.notPublished : PluginCatalogClient.CatalogError.http(status)
            }
            entries = try PluginCatalogClient.decodeIndex(data)
            fetched = Date()
            note = nil
            saveCache(data)
        } catch PluginCatalogClient.CatalogError.notPublished {
            entries = []
            note = L("settings.plugins.not_published")
        } catch {
            // Offline or the repo is down: keep what the cache had, say so quietly; Refresh tries again
            logger.notice("Couldn't read the plugin catalog: \(String(describing: error), privacy: .public)")
            note = entries.isEmpty ? L("settings.plugins.catalog_unreachable") : L("settings.plugins.catalog_stale")
        }
    }

    private struct Cache: Codable {
        let url: String
        let fetched: Date
        let index: Data
    }

    /// The last catalog read, if it was read from the address Settings has now
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheFile), let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.url == settings.get(SettingsDefaults.pluginIndexURL),
              let entries = try? PluginCatalogClient.decodeIndex(cache.index) else { return }
        self.entries = entries
        fetched = cache.fetched
    }

    private func saveCache(_ index: Data) {
        let cache = Cache(url: settings.get(SettingsDefaults.pluginIndexURL), fetched: Date(), index: index)
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: cacheFile, options: .atomic)
    }

    // MARK: - Installing, updating, removing

    /// Installs or updates it. A new plugin's tab is turned on too, while fewer than six show
    func install(_ entry: PluginCatalogEntry) async {
        guard busy[entry.id] == nil else { return }
        let isNew = !plugins.installed.contains { $0.id == entry.id }
        busy[entry.id] = .downloading
        defer { busy[entry.id] = nil }
        do {
            try await client.install(entry) { phase in Task { @MainActor in self.busy[entry.id] = phase } }
        } catch {
            notice = Notice(text: L("settings.plugins.install_failed", entry.name, String(describing: error)), isError: true)
            plugins.refresh()
            return
        }
        plugins.refresh()
        guard isNew else {
            notice = Notice(text: L("settings.plugins.updated", entry.name, entry.version), isError: false)
            return
        }
        notice = Notice(text: turnOnTab(entry.id, name: entry.name), isError: false)
    }

    /// Updates every installed plugin the catalog has a newer version of, one after another
    func updateAll() async {
        let pending = updates
        for update in pending { await install(update.entry) }
        if pending.count > 1 { notice = Notice(text: L("settings.plugins.all_updated", pending.count), isError: false) }
    }

    /// Installs a plugin from a zip or folder on this Mac
    func install(from source: URL) async {
        let key = source.lastPathComponent
        busy[key] = .installing
        defer { busy[key] = nil }
        do {
            let manifest = try await client.install(from: source)
            plugins.refresh()
            notice = Notice(text: turnOnTab(manifest.id, name: manifest.name), isError: false)
        } catch {
            notice = Notice(text: L("settings.plugins.install_failed", source.lastPathComponent, String(describing: error)), isError: true)
            plugins.refresh()
        }
    }

    /// Asks for a zip or folder to install
    func installFromFile() {
        let panel = NSOpenPanel()
        panel.title = L("settings.plugins.install_file")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder]
        panel.message = L("settings.plugins.install_file_message")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await install(from: url) }
    }

    func uninstall(_ pluginID: String) {
        let name = plugins.installed.first { $0.id == pluginID }?.manifest.name ?? pluginID
        do {
            try client.remove(pluginID)
            plugins.preferences.removeAll(for: pluginID)
            notice = Notice(text: L("settings.plugins.uninstalled", name), isError: false)
        } catch {
            notice = Notice(text: L("settings.plugins.uninstall_failed", name, String(describing: error)), isError: true)
        }
        plugins.refresh()
    }

    func clearNotice() { notice = nil }

    /// Turns a newly installed plugin's tab on when there's room, and says what happened
    private func turnOnTab(_ pluginID: String, name: String) -> String {
        let tab = IslandTab.plugin(pluginID)
        let tabs = TabStore.shared
        if tabs.isEnabled(tab) || tabs.canToggle(tab) {
            tabs.setEnabled(tab, true)
            return L("settings.plugins.installed_with_tab", name)
        }
        return L("settings.plugins.installed_no_room", name, TabStore.maxEnabled)
    }
}
