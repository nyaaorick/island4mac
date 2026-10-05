import SwiftUI

/// A plugin in the pill of a display without a notch
struct CompactPluginLiveActivityView: View {
    let name: String
    let compact: PluginCompact

    var body: some View {
        PluginTimeline(compact: compact) { text, progress in
            HStack(spacing: 8) {
                PluginSymbolView(symbol: compact.symbol, progress: progress, size: 14)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(text ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(height: 28)
        }
    }
}
