import SwiftUI

/// What a plugin shows in its tab: its cards, its rows, then its text field and buttons, all drawn by the island
/// in its own look. `send` gets the taps (a row, card or button id) and what you typed. A button with `confirm`
/// asks here first. Buttons alone, with nothing else to show, are drawn larger in the middle of the tab. The built-in Clipboard and Files tabs draw with it too, from the content they make themselves
struct PluginContentView: View {
    let content: PluginStore.Content
    /// Shown while there's nothing at all: the plugin's symbol and name
    let emptySymbol: String
    let emptyTitle: String
    var emptyText = L("plugins.tab.empty")
    let send: (PluginEvent) -> Void

    @State private var typed = ""
    /// The button waiting for you to confirm it
    @State private var confirming: PluginButton?

    private var showsOnlyButtons: Bool {
        !content.buttons.isEmpty && content.rows.isEmpty && content.cards.isEmpty && content.input == nil && content.notice == nil
    }

    private var isEmpty: Bool {
        content.rows.isEmpty && content.cards.isEmpty && content.buttons.isEmpty && content.input == nil && content.notice == nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if isEmpty {
                emptyState
            } else if showsOnlyButtons {
                buttonsOnly
            } else {
                if !content.cards.isEmpty {
                    ScrollView(.horizontal) {
                        // Room around the cards for their shadows (IslandSurface)
                        HStack(spacing: 12) {
                            ForEach(Array(content.cards.enumerated()), id: \.offset) { _, card in
                                PluginCardView(card: card, action: { tap(card.id) }, onAction: { tap($0) })
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                    }
                    .scrollIndicators(.never)
                    // Only as tall as the cards, so the buttons sit right under them
                    .fixedSize(horizontal: false, vertical: true)
                }

                if !content.rows.isEmpty || content.notice != nil {
                    ScrollView {
                        // Room between and below the panes for their shadows (IslandSurface)
                        VStack(spacing: 8) {
                            if let notice = content.notice {
                                PluginNoticeView(notice: notice)
                            }
                            ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                                PluginRowView(row: row, action: { tap(row.id) }, onAction: { tap($0) })
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 22)
                    }
                    .scrollIndicators(.never)
                }

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
                    .padding(.bottom, 14)
                }

                // What's left of the tab goes below
                Spacer(minLength: 0)
            }
        }
        // A new field from the plugin starts from its own text
        .onChange(of: content.input?.id, initial: true) { _, _ in typed = content.input?.text ?? "" }
        // Buttons that change under a pending confirmation take it away
        .onChange(of: content.buttons) { _, buttons in
            if let pending = confirming, !buttons.contains(pending) { confirming = nil }
        }
    }

    /// Only buttons: larger, in the middle of the tab, like the tab's own states (Restart, Open Settings)
    private var buttonsOnly: some View {
        Group {
            if let button = confirming {
                confirmRow(for: button)
            } else {
                HStack(spacing: 10) {
                    ForEach(content.buttons) { button in
                        PluginButtonView(title: button.title, symbol: button.symbol, isProminent: true) { tap(button) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptySymbol)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            Text(emptyTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(emptyText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
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
                send(.submit(id: input.id, text: typed))
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
                tap(button.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func tap(_ button: PluginButton) {
        if button.confirm != nil {
            confirming = button
        } else {
            tap(button.id)
        }
    }

    private func tap(_ id: String?) {
        guard let id else { return }
        send(.action(id))
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
