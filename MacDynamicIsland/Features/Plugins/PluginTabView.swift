import SwiftUI

/// A plugin's tab: its rows, then its text field and buttons, all drawn by the island in its own look. Tapping
/// a row or button sends its id to the plugin; a button with `confirm` asks here first
struct PluginTabView: View {
    let pluginID: String
    @ObservedObject private var plugins = PluginStore.shared
    @State private var typed = ""
    /// The button waiting for you to confirm it
    @State private var confirming: PluginButton?

    private var plugin: PluginStore.Installed? { plugins.installed.first { $0.id == pluginID } }
    private var content: PluginStore.Content { plugins.contents[pluginID] ?? PluginStore.Content() }

    var body: some View {
        VStack(spacing: 8) {
            if case .stopped(let reason) = plugins.statuses[pluginID] {
                stoppedState(reason: reason)
            } else if plugins.statuses[pluginID] == .needsSetup {
                setupState
            } else if content.rows.isEmpty && content.buttons.isEmpty && content.input == nil && content.notice == nil {
                emptyState
            } else {
                ScrollView {
                    // Room between and below the panes for their shadows (IslandSurface)
                    VStack(spacing: 8) {
                        if let notice = content.notice {
                            PluginNoticeView(notice: notice)
                        }
                        ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                            PluginRowView(row: row, action: { send(row.id) }, onAction: { send($0) })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.never)

                if let input = content.input {
                    inputField(input)
                }

                if let button = confirming {
                    confirmRow(for: button)
                } else if !content.buttons.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(content.buttons) { button in
                            PluginButtonView(title: button.title, symbol: button.symbol) { tap(button) }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The plugin may update often while its tab shows and rest otherwise (counted across displays)
        .onAppear { plugins.tabAppeared(pluginID) }
        .onDisappear { plugins.tabDisappeared(pluginID) }
        // A new field from the plugin starts from its own text
        .onChange(of: content.input?.id, initial: true) { _, _ in typed = content.input?.text ?? "" }
        // Buttons that change under a pending confirmation take it away
        .onChange(of: content.buttons) { _, buttons in
            if let pending = confirming, !buttons.contains(pending) { confirming = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: plugin?.manifest.symbol ?? "puzzlepiece.extension")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(plugin?.manifest.name ?? pluginID)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(plugin == nil ? L("plugins.tab.missing") : L("plugins.tab.empty"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A required preference is empty: the plugin waits for it, set in Settings
    private var setupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gearshape")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("plugins.tab.needs_setup", plugin?.manifest.name ?? pluginID))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            PluginButtonView(title: L("plugins.tab.open_settings"), symbol: "gearshape") {
                SettingsWindowController.shared.showSettings(pane: .plugins)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The plugin kept exiting or couldn't start: say so, and offer to start it again
    private func stoppedState(reason: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("plugins.tab.stopped", plugin?.manifest.name ?? pluginID))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            PluginButtonView(title: L("plugins.tab.restart"), symbol: "arrow.clockwise") {
                plugins.restart(pluginID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same field as an agent's question card
    private func inputField(_ input: PluginInput) -> some View {
        TextField(input.placeholder ?? "", text: $typed)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .islandInset(cornerRadius: 6)
            .padding(.horizontal, 12)
            .onChange(of: typed) { _, text in
                if text.count > PluginInput.maxLength { typed = String(text.prefix(PluginInput.maxLength)) }
            }
            .onSubmit {
                plugins.send(.submit(id: input.id, text: typed), to: pluginID)
                typed = ""
                feedback()
            }
    }

    private func confirmRow(for button: PluginButton) -> some View {
        HStack(spacing: 8) {
            Text(button.confirm ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            PluginButtonView(title: L("plugins.tab.cancel"), symbol: nil) { confirming = nil }
            PluginButtonView(title: button.title, symbol: button.symbol) {
                confirming = nil
                send(button.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func tap(_ button: PluginButton) {
        if button.confirm != nil {
            confirming = button
        } else {
            send(button.id)
        }
    }

    private func send(_ id: String?) {
        guard let id else { return }
        plugins.send(.action(id), to: pluginID)
        feedback()
    }

    private func feedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

private struct PluginRowView: View {
    let row: PluginRow
    let action: () -> Void
    /// One of its secondary actions was tapped, with that action's id
    let onAction: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let image = row.image {
                PluginImageView(image: image, size: 28, fallbackSymbol: row.symbol)
            } else if let symbol = row.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
            // Secondary actions show on hover, like the archive button of an agent session
            if isHovered, let actions = row.actions, !actions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(actions) { rowAction in
                        Button { onAction(rowAction.id) } label: {
                            Image(systemName: rowAction.symbol ?? "ellipsis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 22, height: 22)
                                .islandInset(cornerRadius: 6)
                        }
                        .buttonStyle(.plain)
                        .help(rowAction.title)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .islandTile(cornerRadius: 12, highlighted: isHovered && row.id != nil)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .contextMenu {
            ForEach(row.actions ?? []) { rowAction in
                Button { onAction(rowAction.id) } label: {
                    if let symbol = rowAction.symbol {
                        Label(rowAction.title, systemImage: symbol)
                    } else {
                        Text(rowAction.title)
                    }
                }
            }
        }
    }
}

/// A plugin's "loading" or "couldn't load" line: the same row for every plugin
private struct PluginNoticeView: View {
    let notice: PluginNotice

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch notice.state {
                case .loading:
                    ProgressView().controlSize(.small)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.9))
                }
            }
            .frame(width: 20)
            Text(notice.text ?? L(notice.state == .loading ? "plugins.tab.loading" : "plugins.tab.failed"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .islandTile(cornerRadius: 12)
    }
}

private struct PluginButtonView: View {
    let title: String
    let symbol: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .islandTile(cornerRadius: 999, highlighted: isHovered)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}
