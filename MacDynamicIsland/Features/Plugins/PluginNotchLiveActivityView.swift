import SwiftUI

/// A plugin beside the notch on a notched display: its symbol (with a progress ring) left of the notch,
/// its text right of it. A popup shows the same way for its few seconds
struct PluginNotchLiveActivityView: View {
    let symbol: String?
    let text: String?
    let progress: Double?
    let notch: CGSize
    let wings: IslandWings

    var body: some View {
        NotchWingsLayout(notch: notch, wings: wings) { _ in
            PluginSymbolView(symbol: symbol, progress: progress, size: max(12, notch.height - 18))
        } secondary: { _ in
            Text(text ?? "")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                // A narrow right wing still fits "12:34"
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}
