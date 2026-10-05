import SwiftUI

/// A plugin's symbol, inside a progress ring when it reports progress
struct PluginSymbolView: View {
    let symbol: String?
    let progress: Double?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
            }
            Image(systemName: symbol ?? "puzzlepiece.extension")
                .font(.system(size: progress == nil ? size * 0.8 : size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
