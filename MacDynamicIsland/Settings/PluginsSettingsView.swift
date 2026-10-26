import SwiftUI
import AppKit

/// Installed plugins, and the ones in the plugins repo, each installed or uninstalled with one click. Installing
/// turns the plugin's tab on when there's room; Tabs has the rest
struct PluginsSettingsView: View {
    @ObservedObject private var plugins = PluginStore.shared
    @ObservedObject private var settings = SettingsDefaults.shared

    @State private var catalog: [PluginCatalogEntry] = []
    @State private var isLoading = false
    @State private var busyID: String?
    @State private var errorText: String?
    /// What the last install or uninstall did
    @State private var notice: String?
    /// Why the catalog couldn't be read, shown quietly: not published yet, or offline
    @State private var catalogNote: String?

    private var client: PluginCatalogClient {
        PluginCatalogClient(pluginsFolder: plugins.pluginsFolder, dataFolder: plugins.dataFolder)
    }

    var body: some View {
        SettingsForm {
            Section {
                ToggleSettingsRow(
                    key: SettingsDefaults.showPluginLiveActivity,
                    title: L("settings.plugins.live_activity"),
                    help: L("settings.plugins.live_activity_help")
                )
                ToggleSettingsRow(
                    key: SettingsDefaults.pluginsMayOpenIsland,
                    title: L("settings.plugins.may_open"),
                    help: L("settings.plugins.may_open_help")
                )
            } footer: {
                SettingsNote(L("settings.plugins.about"))
            }

            Section {
                if plugins.installed.isEmpty {
                    SettingsNote(L("settings.plugins.none_installed"))
                }
                ForEach(plugins.installed) { plugin in
                    installedRow(plugin)
                }
                ForEach(plugins.broken, id: \.folder) { problem in
                    LabeledContent(problem.folder) {
                        SettingsNote(problem.reason, color: .red)
                    }
                }
                HStack {
                    Button(L("settings.plugins.open_folder")) {
                        try? FileManager.default.createDirectory(at: plugins.pluginsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(plugins.pluginsFolder)
                    }
                    Button(L("settings.plugins.reload")) { plugins.reload() }
                }
            } header: {
                Text(L("settings.plugins.installed"))
            }

            ForEach(plugins.installed.filter { $0.manifest.preferences?.isEmpty == false }) { plugin in
                PluginPreferencesView(plugin: plugin, store: plugins.preferences)
            }

            Section {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if catalog.isEmpty {
                    SettingsNote(catalogNote ?? L("settings.plugins.catalog_empty"))
                }
                ForEach(catalog) { entry in
                    catalogRow(entry)
                }
                if let errorText {
                    SettingsNote(errorText, color: .red)
                } else if let notice {
                    SettingsNote(notice)
                }
            } header: {
                HStack {
                    Text(L("settings.plugins.available"))
                    Spacer()
                    Button(L("settings.plugins.refresh")) { Task { await loadCatalog() } }
                        .disabled(isLoading)
                }
            } footer: {
                SettingsNote(L("settings.plugins.trust_note"))
            }
        }
        .task { await loadCatalog() }
    }

    private func installedRow(_ plugin: PluginStore.Installed) -> some View {
        LabeledContent {
            HStack {
                Toggle(L("settings.plugins.enabled"), isOn: Binding(
                    get: { plugins.isEnabled(plugin.id) },
                    set: { plugins.setEnabled(plugin.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(L("settings.plugins.enabled"))
                if case .stopped = plugins.statuses[plugin.id] {
                    Button(L("plugins.tab.restart")) { plugins.restart(plugin.id) }
                }
                if !plugin.isBundled {
                    uninstallButton(plugin.id)
                }
            }
        } label: {
            Label {
                Text(plugin.manifest.name)
                Text(statusText(for: plugin))
            } icon: {
                Image(systemName: plugin.manifest.symbol)
            }
        }
    }

    private func catalogRow(_ entry: PluginCatalogEntry) -> some View {
        let installed = plugins.installed.first { $0.id == entry.id }
        return LabeledContent {
            if busyID == entry.id {
                ProgressView().controlSize(.small)
            } else if !entry.isSupported {
                SettingsNote(L("settings.plugins.needs_update"))
            } else if let installed {
                HStack {
                    if installed.manifest.version != entry.version {
                        Button(L("settings.plugins.update")) { Task { await install(entry) } }
                            .disabled(busyID != nil)
                    }
                    if !installed.isBundled {
                        uninstallButton(entry.id)
                    }
                }
            } else {
                Button(L("settings.plugins.install")) { Task { await install(entry) } }
                    .disabled(busyID != nil)
            }
        } label: {
            Label {
                Text(entry.name)
                if let description = entry.description {
                    Text(description)
                }
            } icon: {
                Image(systemName: entry.symbol ?? "puzzlepiece.extension")
            }
        }
    }

    private func uninstallButton(_ pluginID: String) -> some View {
        Button(L("settings.plugins.uninstall"), role: .destructive) { uninstall(pluginID) }
            .disabled(busyID != nil)
    }

    /// Version, and whether it runs: on while its tab is shown, stopped with the reason if it kept failing
    private func statusText(for plugin: PluginStore.Installed) -> String {
        let status: String = switch plugins.statuses[plugin.id] {
        case .running: L("settings.plugins.status_running")
        case .stopped(let reason): L("settings.plugins.status_stopped", reason)
        case .needsSetup: L("settings.plugins.status_needs_setup")
        case .sleeping: L("settings.plugins.status_sleeping")
        case nil where !plugins.isEnabled(plugin.id): L("settings.plugins.status_disabled")
        case nil: L("settings.plugins.status_off")
        }
        return [plugin.manifest.version, status].compactMap { $0 }.joined(separator: " · ")
    }

    private func loadCatalog() async {
        guard let url = URL(string: settings.get(SettingsDefaults.pluginIndexURL)) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await client.fetchIndex(from: url)
            catalogNote = nil
        } catch PluginCatalogClient.CatalogError.notPublished {
            catalog = []
            catalogNote = L("settings.plugins.not_published")
        } catch {
            // Offline or the repo is down: say so quietly; Refresh tries again
            catalog = []
            catalogNote = L("settings.plugins.catalog_unreachable")
        }
    }

    /// Installs or updates it. A new plugin's tab is turned on too, while fewer than six show
    private func install(_ entry: PluginCatalogEntry) async {
        let isNew = !plugins.installed.contains { $0.id == entry.id }
        busyID = entry.id
        defer { busyID = nil }
        do {
            try await client.install(entry)
            errorText = nil
        } catch {
            errorText = L("settings.plugins.install_failed", entry.name, String(describing: error))
            plugins.refresh()
            return
        }
        plugins.refresh()
        guard isNew else {
            notice = L("settings.plugins.updated", entry.name)
            return
        }
        let tab = IslandTab.plugin(entry.id)
        let tabs = TabStore.shared
        if tabs.isEnabled(tab) || tabs.canToggle(tab) {
            tabs.setEnabled(tab, true)
            notice = L("settings.plugins.installed_with_tab", entry.name)
        } else {
            notice = L("settings.plugins.installed_no_room", entry.name, TabStore.maxEnabled)
        }
    }

    private func uninstall(_ pluginID: String) {
        let name = plugins.installed.first { $0.id == pluginID }?.manifest.name ?? pluginID
        do {
            try client.remove(pluginID)
            plugins.preferences.removeAll(for: pluginID)
            errorText = nil
            notice = L("settings.plugins.uninstalled", name)
        } catch {
            errorText = L("settings.plugins.uninstall_failed", name, String(describing: error))
        }
        plugins.refresh()
    }
}
