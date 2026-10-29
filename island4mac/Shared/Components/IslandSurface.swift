import SwiftUI

/// The open island's layers, like Control Center on macOS 26: panes of Liquid Glass (tiles) over the island's
/// glass, and flat wells (insets) inside a tile. Every tab, built-in or plugin, uses these and nothing of its own,
/// so the island reads as one stack of glass. Each layer is a step deeper than the one beneath it; tiles are the
/// system's Liquid Glass, not drawn imitations
struct IslandSurface: View {
    enum Level {
        /// A raised pane: a module, card or row
        case tile
        /// A well inside a tile: a text field, a preview, an option
        case inset
    }

    let level: Level
    var cornerRadius: CGFloat
    /// Hovered or selected: a little deeper
    var isHighlighted = false
    /// Tints a tile that needs your attention (an agent's question); never decoration
    var tint: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        switch level {
        case .tile: tile
        case .inset: inset
        }
    }

    /// The system's clear Liquid Glass, a step deeper than the glass it lies on: a pane over the island's glass
    /// takes some light, as a second sheet of real glass would. Hovered or selected goes deeper still
    private static let tileGlass = Glass.clear.tint(.black.opacity(0.18))

    private var tile: some View {
        var glass = Self.tileGlass
        if let tint {
            glass = Glass.clear.tint(tint.opacity(0.22))
        } else if isHighlighted {
            glass = Glass.clear.tint(.black.opacity(0.3))
        }
        return Color.clear.glassEffect(glass, in: shape)
    }

    /// A well sits deeper than the pane around it
    private var inset: some View {
        shape
            .fill(.black.opacity(isHighlighted ? 0.26 : 0.16))
            .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

extension View {
    /// A raised pane of glass behind this view. A huge `cornerRadius` makes a capsule
    func islandTile(cornerRadius: CGFloat = 16, highlighted: Bool = false, tint: Color? = nil) -> some View {
        background(IslandSurface(level: .tile, cornerRadius: cornerRadius, isHighlighted: highlighted, tint: tint))
    }

    /// A flat well behind this view, inside a tile
    func islandInset(cornerRadius: CGFloat = 8, highlighted: Bool = false) -> some View {
        background(IslandSurface(level: .inset, cornerRadius: cornerRadius, isHighlighted: highlighted))
    }
}
