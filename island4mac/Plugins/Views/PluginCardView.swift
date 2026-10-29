import SwiftUI
import AppKit

/// A plugin's card (PluginCard): its picture and title along the top, its preview large below. Actions show on
/// hover and in its context menu; a card with a file drags out as that file
struct PluginCardView: View {
    let card: PluginCard
    let action: () -> Void
    /// One of its secondary actions was tapped
    let onAction: (PluginRowAction) -> Void
    @State private var isHovered = false

    static let width: CGFloat = 170
    static let height: CGFloat = 160
    /// What's left for the preview inside the card's padding and the inset's
    private static let previewSize = CGSize(width: width - 44, height: height - 68)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let image = card.image {
                    PluginImageView(image: image, size: 16, fallbackSymbol: card.symbol)
                } else if card.symbol != nil || card.state != nil {
                    PluginSymbolView(symbol: card.symbol, progress: nil, size: 14, state: card.state)
                        .frame(width: 16, height: 16)
                }
                Text(card.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: card.state == nil ? .regular : .medium))
                        .foregroundStyle(card.state?.color ?? .white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            preview
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .islandInset(cornerRadius: 10)
                .overlay(alignment: .topTrailing) {
                    // Secondary actions show on hover, like a row's
                    if isHovered, let actions = card.actions, !actions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(actions) { cardAction in
                                Button { onAction(cardAction) } label: {
                                    Image(systemName: cardAction.symbol ?? "ellipsis")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: 22, height: 22)
                                        .islandInset(cornerRadius: 6)
                                }
                                .buttonStyle(.plain)
                                .help(cardAction.title)
                            }
                        }
                        .padding(5)
                    }
                }
        }
        .padding(12)
        .frame(width: Self.width, height: Self.height)
        .islandTile(cornerRadius: 16, highlighted: isHovered && card.id != nil)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .modifier(FileDrag(path: card.file))
        .contextMenu {
            ForEach(card.actions ?? []) { cardAction in
                Button { onAction(cardAction) } label: {
                    if let symbol = cardAction.symbol {
                        Label(cardAction.title, systemImage: symbol)
                    } else {
                        Text(cardAction.title)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch card.preview {
        case .text(let text):
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        case .image(let image):
            PluginImageView(preview: image, width: Self.previewSize.width, height: Self.previewSize.height, fallbackSymbol: card.symbol)
        case nil:
            // No preview: its picture or symbol, large
            Group {
                if let image = card.image {
                    PluginImageView(image: image, size: 48, fallbackSymbol: card.symbol)
                } else {
                    Image(systemName: card.symbol ?? "square.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Lets a card with a file be dragged out as that file (to Finder, Mail, …); a card without one doesn't drag
private struct FileDrag: ViewModifier {
    let path: String?

    func body(content: Content) -> some View {
        if let path {
            content.onDrag {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                provider.suggestedName = url.lastPathComponent
                return provider
            }
        } else {
            content
        }
    }
}
