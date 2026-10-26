import AppKit

/// How the open island's tab labels are spaced, picked so every label shows whole: the roomiest style the
/// tabs fit in, then tighter ones, then labels without icons, and only when even those don't fit, a row that
/// scrolls sideways. Labels are never cut short or shrunk
struct TabBarLayout: Equatable {
    var showsIcons: Bool
    var iconSpacing: CGFloat
    var horizontalPadding: CGFloat
    var itemSpacing: CGFloat
    /// Not even the tightest style fits: the tabs scroll sideways
    var scrolls = false

    static let regular = TabBarLayout(showsIcons: true, iconSpacing: 6, horizontalPadding: 10, itemSpacing: 4)
    static let tight = TabBarLayout(showsIcons: true, iconSpacing: 4, horizontalPadding: 7, itemSpacing: 2)
    static let labelsOnly = TabBarLayout(showsIcons: false, iconSpacing: 0, horizontalPadding: 8, itemSpacing: 2)

    static let fontSize: CGFloat = 11
    /// Room an icon takes; SF Symbols at this size are no wider
    static let iconWidth: CGFloat = 14

    /// The first style in which each group of tabs fits in `width`; one style for all, so both sides of the
    /// camera look alike
    static func fitting(_ groups: [[String]], in width: CGFloat) -> TabBarLayout {
        for layout in [regular, tight, labelsOnly] where groups.allSatisfy({ layout.width(of: $0) <= width }) {
            return layout
        }
        var layout = labelsOnly
        layout.scrolls = true
        return layout
    }

    /// Width of a row of tabs with these labels
    func width(of labels: [String]) -> CGFloat {
        guard !labels.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: Self.fontSize, weight: .semibold)
        let items = labels.reduce(CGFloat(0)) { total, label in
            let text = ceil((label as NSString).size(withAttributes: [.font: font]).width)
            return total + text + 2 * horizontalPadding + (showsIcons ? Self.iconWidth + iconSpacing : 0)
        }
        return items + itemSpacing * CGFloat(labels.count - 1)
    }
}
