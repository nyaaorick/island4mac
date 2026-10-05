import SwiftUI

/// A plugin's tab: its rows, then its buttons, drawn by the island. Tapping one sends its id to the plugin
struct PluginTabView: View {
    let pluginID: String
    @ObservedObject private var plugins = PluginStore.shared

    private var plugin: PluginStore.Installed? { plugins.installed.first { $0.id == pluginID } }
    private var content: PluginStore.Content { plugins.contents[pluginID] ?? PluginStore.Content() }

    var body: some View {
        VStack(spacing: 8) {
            if content.rows.isEmpty && content.buttons.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                            PluginRowView(row: row) { send(row.id) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.never)

                if !content.buttons.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(content.buttons) { button in
                            PluginButtonView(button: button) { send(button.id) }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The plugin may update often while its tab shows and rest otherwise
        .onAppear { plugins.send(.visible(true), to: pluginID) }
        .onDisappear { plugins.send(.visible(false), to: pluginID) }
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

    private func send(_ id: String?) {
        guard let id else { return }
        plugins.send(.action(id), to: pluginID)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

private struct PluginRowView: View {
    let row: PluginRow
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = row.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isHovered && row.id != nil ? 0.12 : 0.06))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}

private struct PluginButtonView: View {
    let button: PluginButton
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = button.symbol {
                Image(systemName: symbol)
            }
            Text(button.title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Capsule().fill(.white.opacity(isHovered ? 0.22 : 0.14)))
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}
