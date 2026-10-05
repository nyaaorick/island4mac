import SwiftUI

/// A collapsed agent session on a notched display: status and progress left of the notch
struct AgentNotchLiveActivityView: View {
    let session: AgentSession
    let notch: CGSize
    let wings: IslandWings
    /// Sessions working or waiting for you; shown beside the glyph when there are several
    var activeCount = 1

    var body: some View {
        NotchWingsLayout(notch: notch, wings: wings) { _ in
            HStack(spacing: 2) {
                AgentStatusGlyph(status: session.status, isAsking: session.isAsking, size: max(12, notch.height - 18))
                if activeCount > 1 {
                    Text("\(activeCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        } secondary: { _ in
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(session.progressText(at: timeline.date) ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(session.status == .needsPermission ? session.status.color : .white.opacity(0.85))
                    .lineLimit(1)
                    // A narrow right wing still fits "12:34"
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(session.agent.displayName), \(session.projectName), \(session.statusText)"))
    }
}
