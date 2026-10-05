import SwiftUI

/// A collapsed agent session on a display without a notch: status, project and progress in one pill
struct CompactAgentLiveActivityView: View {
    let session: AgentSession
    /// The wider pill of a large display, with room to say what the agent is doing rather than just its state
    var isWide = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 8) {
                AgentStatusGlyph(status: session.status, isAsking: session.isAsking, size: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isWide && session.isActive ? session.statusLineText : session.statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(session.status.color)
                }
                .lineLimit(1)

                Spacer(minLength: 0)

                Text(session.progressText(at: timeline.date) ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(height: 28)
    }
}
