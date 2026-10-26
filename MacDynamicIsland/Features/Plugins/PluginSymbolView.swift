import SwiftUI

/// A plugin's symbol, inside a progress ring when it reports progress, or drawn as its state (protocol 6): a
/// turning arc while it works, pulsing in the attention color while it needs you, and in the done or failed color
/// otherwise. The same glyph in a row, beside the notch and in the pill
struct PluginSymbolView: View {
    let symbol: String?
    let progress: Double?
    let size: CGFloat
    /// Shown in place of the symbol (protocol 4)
    var image: PluginImage?
    var state: PluginItemState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A ring or arc around the picture makes room by drawing it smaller
    private var hasRing: Bool { progress != nil || (state == .working && image != nil) }

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
            } else if state == .working {
                // The arc stands for the symbol while it works, as the agents' spinner did
                WorkingArc(color: PluginItemState.working.color, lineWidth: max(1.5, size / 8), isTurning: !reduceMotion)
            }
            if let image {
                PluginImageView(image: image, size: hasRing ? size * 0.62 : size, fallbackSymbol: symbol)
            } else if state != .working, let name = symbol ?? state?.fallbackSymbol {
                Image(systemName: name)
                    .font(.system(size: progress == nil ? size * 0.8 : size * 0.5, weight: .semibold))
                    .foregroundStyle(state?.color ?? .white)
                    .symbolEffect(.pulse, options: .repeating, isActive: state == .attention && !reduceMotion)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A turning arc, driven by the timeline so it never leaks an implicit animation into the island's layout
private struct WorkingArc: View {
    let color: Color
    let lineWidth: CGFloat
    let isTurning: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isTurning)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate / 0.9
            Circle()
                .trim(from: 0.12, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(isTurning ? turns.truncatingRemainder(dividingBy: 1) * 360 : 0))
        }
    }
}
