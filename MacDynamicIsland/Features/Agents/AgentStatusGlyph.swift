import SwiftUI

struct AgentStatusGlyph: View {
    let status: AgentSession.Status
    /// Waiting for an answer to a question rather than for a permission
    var isAsking = false
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch status {
            case .working, .compacting:
                AgentSpinner(color: status.color, lineWidth: max(1.5, size / 8))
            case .needsPermission:
                Image(systemName: isAsking ? "questionmark.bubble.fill" : "hand.raised.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(status.color)
                    .symbolEffect(.pulse, options: .repeating)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(status.color)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(status.color)
            case .idle:
                Image(systemName: "circle.dotted")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(status.color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A turning arc, driven by the timeline so it never leaks an implicit animation into the layout
private struct AgentSpinner: View {
    let color: Color
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let turns = timeline.date.timeIntervalSinceReferenceDate / 0.9
            Circle()
                .trim(from: 0.12, to: 1)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? 0 : turns.truncatingRemainder(dividingBy: 1) * 360))
        }
    }
}
