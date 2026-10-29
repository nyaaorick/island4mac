import SwiftUI
import AppKit

/// The plugin hub: what's installed (with its updates, settings and switches) and what the catalog offers, each
/// installed, updated or removed with one click. PluginCatalogStore holds the state; this only draws it
struct PluginsSettingsView: View {
    @ObservedObject private var plugins = PluginStore.shared
    @ObservedObject private var catalog = PluginCatalogStore.shared

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

            installedSection

            ForEach(plugins.installed.filter { $0.manifest.preferences?.isEmpty == false }) { plugin in
                PluginPreferencesView(plugin: plugin, store: plugins.preferences)
            }

            availableSection
        }
        .task { await catalog.refreshIfStale() }
    }

    // MARK: - Installed

    private var installedSection: some View {
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
                Button(L("settings.plugins.install_file")) { catalog.installFromFile() }
                Button(L("settings.plugins.open_folder")) {
                    try? FileManager.default.createDirectory(at: plugins.pluginsFolder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(plugins.pluginsFolder)
                }
                Button(L("settings.plugins.reload")) { plugins.reload() }
            }
        } header: {
            HStack {
                Text(L("settings.plugins.installed"))
                Spacer()
                if catalog.updates.count > 1 {
                    Button(L("settings.plugins.update_all", catalog.updates.count)) { Task { await catalog.updateAll() } }
                        .disabled(!catalog.busy.isEmpty)
                }
            }
        }
    }

    private func installedRow(_ plugin: PluginStore.Installed) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                if let phase = catalog.busy[plugin.id] {
                    phaseLabel(phase)
                } else if let update = catalog.update(for: plugin.id) {
                    Button(L("settings.plugins.update_to", update.entry.version)) { Task { await catalog.install(update.entry) } }
                        .disabled(!catalog.busy.isEmpty)
                }
                if case .stopped = plugins.statuses[plugin.id] {
                    Button(L("plugins.tab.restart")) { plugins.restart(plugin.id) }
                }
                Toggle(L("settings.plugins.enabled"), isOn: Binding(
                    get: { plugins.isEnabled(plugin.id) },
                    set: { plugins.setEnabled(plugin.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(L("settings.plugins.enabled"))
                if !plugin.isBundled {
                    Menu {
                        Button(L("settings.plugins.show_in_finder")) { NSWorkspace.shared.activateFileViewerSelecting([plugin.folder]) }
                        Button(L("settings.plugins.open_data_folder")) {
                            let folder = plugins.dataFolder(for: plugin.id)
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                        if let homepage = catalog.entries.first(where: { $0.id == plugin.id })?.homepage {
                            Link(L("settings.plugins.homepage"), destination: homepage)
                        }
                        Divider()
                        Button(L("settings.plugins.uninstall"), role: .destructive) { catalog.uninstall(plugin.id) }
                            .disabled(!catalog.busy.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 24)
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
        var parts = [plugin.manifest.version, status].compactMap { $0 }
        if plugin.isBundled { parts.append(L("settings.plugins.bundled")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Available

    private var availableSection: some View {
        Section {
            if catalog.isLoading && catalog.entries.isEmpty {
                ProgressView().controlSize(.small)
            } else if catalog.entries.isEmpty {
                SettingsNote(catalog.note ?? L("settings.plugins.catalog_empty"))
            } else if catalog.available.isEmpty {
                SettingsNote(catalog.search.isEmpty ? L("settings.plugins.all_installed") : L("settings.plugins.no_match"))
            }
            ForEach(catalog.available) { entry in
                catalogRow(entry)
            }
            if let notice = catalog.notice {
                SettingsNote(notice.text, color: notice.isError ? .red : .secondary)
            } else if let note = catalog.note, !catalog.entries.isEmpty {
                SettingsNote(note, color: .orange)
            }
        } header: {
            HStack(spacing: 8) {
                Text(L("settings.plugins.available"))
                Spacer()
                if catalog.entries.count > 3 {
                    TextField(L("settings.plugins.search"), text: $catalog.search)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 160)
                }
                if catalog.isLoading {
                    ProgressView().controlSize(.mini)
                }
                Button(L("settings.plugins.refresh")) { Task { await catalog.refresh() } }
                    .disabled(catalog.isLoading)
            }
        } footer: {
            SettingsNote(L("settings.plugins.trust_note"))
        }
    }

    private func catalogRow(_ entry: PluginCatalogEntry) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                if let homepage = entry.homepage {
                    Link(destination: homepage) { Image(systemName: "arrow.up.right.square") }
                        .help(L("settings.plugins.homepage"))
                }
                if let phase = catalog.busy[entry.id] {
                    phaseLabel(phase)
                } else if !entry.isSupported {
                    SettingsNote(L("settings.plugins.needs_update"))
                } else {
                    Button(L("settings.plugins.install")) { Task { await catalog.install(entry) } }
                        .disabled(!catalog.busy.isEmpty)
                }
            }
        } label: {
            Label {
                Text(entry.name)
                if let description = entry.description {
                    Text(description)
                }
                Text(entry.summary)
            } icon: {
                Image(systemName: entry.symbol ?? "puzzlepiece.extension")
            }
        }
    }

    private func phaseLabel(_ phase: PluginCatalogClient.Phase) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            SettingsNote(phaseText(phase))
        }
    }

    private func phaseText(_ phase: PluginCatalogClient.Phase) -> String {
        switch phase {
        case .downloading: L("settings.plugins.phase_downloading")
        case .verifying: L("settings.plugins.phase_verifying")
        case .installing: L("settings.plugins.phase_installing")
        }
    }
}
