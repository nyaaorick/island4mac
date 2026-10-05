import SwiftUI

/// A plugin's symbol, inside a progress ring when it reports progress
struct PluginSymbolView: View {
    let symbol: String?
    let progress: Double?
    let size: CGFloat
    /// Shown in place of the symbol (protocol 4)
    var image: PluginImage?

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
            if let image {
                PluginImageView(image: image, size: progress == nil ? size : size * 0.62, fallbackSymbol: symbol)
            } else {
                Image(systemName: symbol ?? "puzzlepiece.extension")
                    .font(.system(size: progress == nil ? size * 0.8 : size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
