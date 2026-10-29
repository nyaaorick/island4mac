import SwiftUI

/// A plugin beside the notch on a notched display: its symbol (with a progress ring) left of the notch,
/// its text right of it. A popup shows the same way for its few seconds. A countdown ticks here, in the island
struct PluginNotchLiveActivityView: View {
    let compact: PluginCompact
    let notch: CGSize
    let wings: IslandWings

    var body: some View {
        PluginTimeline(compact: compact) { text, progress in
            NotchWingsLayout(notch: notch, wings: wings) { _ in
                PluginSymbolView(symbol: compact.symbol, progress: progress, size: max(12, notch.height - 18), image: compact.image, state: compact.state)
            } secondary: { _ in
                Text(text ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    // "Needs permission" in the attention color, as the glyph is
                    .foregroundStyle(compact.state == .attention ? PluginItemState.attention.color : .white.opacity(0.85))
                    .lineLimit(1)
                    // A narrow right wing still fits "12:34"
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
