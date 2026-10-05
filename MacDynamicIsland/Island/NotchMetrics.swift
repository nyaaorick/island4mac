import SwiftUI

/// Island geometry shared with OverlayWindowController
enum NotchMetrics {
    /// Outward flare of the top corners, like the curve where the notch meets the top edge
    static let compactTopRadius: CGFloat = 6
    static let expandedTopRadius: CGFloat = 19

    /// Tabs row and divider at the top of the open island
    static let tabBarHeight: CGFloat = 53

    /// Width of the open island. The same for every tab, so switching tabs never slides the tab bar
    /// out from under the pointer
    static let expandedWidth: CGFloat = 640
    /// Width of the open island on a large display, again the same for every tab
    static let largeDisplayExpandedWidth: CGFloat = 760

    /// Open island below the camera housing: a content area as tall as what each tab shows, under the tab bar
    /// on a display without a notch (with one, the tabs sit beside the camera, above this)
    static func expandedSize(for section: AppState.IslandSection, largeDisplay: Bool, notch: CGSize) -> CGSize {
        let contentHeight: CGFloat
        switch section {
        case .music:
            // Artwork beside title, lyrics, progress and controls
            contentHeight = 190
        case .clipboard:
            // One row of 160pt cards
            contentHeight = 210
        case .files:
            // Shelf header over a scrolling grid
            contentHeight = 260
        case .agents:
            // A couple of session rows with their task lists; the list scrolls
            contentHeight = 270
        }
        let tabs = notch == .zero ? tabBarHeight : 0
        return CGSize(width: largeDisplay ? largeDisplayExpandedWidth : expandedWidth, height: tabs + contentHeight)
    }
    /// Collapsed pill on displays without a notch
    static let nonNotchWidth: CGFloat = 185
    /// Collapsed pill on a large display while it shows now playing or an agent session:
    /// wide enough for the whole title and lyric line
    static let largeDisplayLiveActivityWidth: CGFloat = 360
    /// External displays at least this wide (1080p and up) are large: the wider island still leaves
    /// the menus and status icons their room
    static let largeDisplayMinWidth: CGFloat = 1920

    /// Whether the island on a display gets the wider layout. Only an external display can,
    /// so the island on the built-in display always stays as it is
    static func isLargeDisplay(width: CGFloat, notch: CGSize, isBuiltIn: Bool) -> Bool {
        !isBuiltIn && notch == .zero && width >= largeDisplayMinWidth
    }

    /// Room around the open island so the open spring's overshoot isn't cut off by the panel
    static let overshootMargin: CGFloat = 10

    /// Widest a wing of collapsed content gets (artwork, spectrum, status, progress)
    static func wingWidth(for notch: CGSize) -> CGFloat {
        notch.height + 6
    }

    /// Narrowest wing worth showing: the artwork or the agent's status glyph, with a little air
    static let minWingWidth: CGFloat = 16
    /// Air kept between a wing and the nearest menu or status icon. Their frames already include padding,
    /// and the island's flared top corners only reach past its body above the icons
    static let wingMargin: CGFloat = 2

    /// Wings that fit into the room the menus and status icons leave beside the notch. The primary item
    /// (artwork, agent status) goes left and the secondary one (spectrum, progress) right; with no room on the
    /// right both go left, as they do while that room is unknown. Nothing is ever laid over a menu or an icon.
    static func liveActivityWings(leadingRoom: CGFloat?, trailingRoom: CGFloat?, notch: CGSize) -> IslandWings {
        let wing = wingWidth(for: notch)
        let left = (leadingRoom ?? .infinity) - wingMargin
        let right = (trailingRoom ?? 0) - wingMargin
        if right >= minWingWidth {
            let leading = left >= minWingWidth ? min(wing, left).rounded(.down) : 0
            return IslandWings(leading: leading, trailing: min(wing, right).rounded(.down))
        }
        if left >= 2 * wing { return IslandWings(leading: 2 * wing, trailing: 0) }
        return IslandWings(leading: left >= minWingWidth ? min(wing, left).rounded(.down) : 0, trailing: 0)
    }

    /// Horizontal offset of the island's center from the notch's, when its wings differ in width
    static func islandOffset(expanded: Bool, notch: CGSize, wings: IslandWings) -> CGFloat {
        guard !expanded, notch != .zero else { return 0 }
        return (wings.trailing - wings.leading) / 2
    }

    /// Settled size of the island; the panel matches it (plus `overshootMargin` when open)
    static func islandSize(expanded: Bool, section: AppState.IslandSection, notch: CGSize, wings: IslandWings,
                           largeDisplay: Bool, nonNotchHeight: CGFloat) -> CGSize {
        if expanded {
            // Content starts below the camera housing
            let open = expandedSize(for: section, largeDisplay: largeDisplay, notch: notch)
            return CGSize(width: open.width, height: open.height + notch.height)
        }
        // No notch (external display): a small pill at the top center. On a large display it widens
        // while it shows now playing or an agent session (it has wings then)
        guard notch != .zero else {
            let width = largeDisplay && !wings.isEmpty ? largeDisplayLiveActivityWidth : nonNotchWidth
            return CGSize(width: width, height: nonNotchHeight)
        }
        // Collapsed: the notch itself, plus the live activity beside it
        let width = notch.width + 2 * compactTopRadius + wings.leading + wings.trailing
        return CGSize(width: width, height: notch.height)
    }

    /// Fixed size of the SwiftUI canvas: the largest open island plus its overshoot margin
    static func canvasSize(notch: CGSize, largeDisplay: Bool) -> CGSize {
        let openSizes = AppState.IslandSection.allCases.map { expandedSize(for: $0, largeDisplay: largeDisplay, notch: notch) }
        return CGSize(
            width: (openSizes.map(\.width).max() ?? 0) + 2 * overshootMargin,
            height: (openSizes.map(\.height).max() ?? 0) + notch.height + overshootMargin
        )
    }
}

/// Width of the collapsed island's content left and right of the notch
struct IslandWings: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    static let none = IslandWings()
    var isEmpty: Bool { leading == 0 && trailing == 0 }
}
