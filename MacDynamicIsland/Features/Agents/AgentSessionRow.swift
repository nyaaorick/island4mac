import SwiftUI

struct AgentSessionRow: View {
    let session: AgentSession
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(alignment: .top, spacing: 12) {
                AgentStatusGlyph(status: session.status, isAsking: session.isAsking, size: 18)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleText
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(session.agent.shortName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(session.agent.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(session.agent.color.opacity(0.15)))
                        trailing(at: timeline.date)
                            .frame(minWidth: 34, alignment: .trailing)
                    }

                    if let prompt = session.prompt {
                        Text("You: \(prompt)")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    statusLine

                    if !session.tasks.isEmpty {
                        AgentTaskChecklist(tasks: session.tasks)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.09 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isHovering ? 0.1 : 0), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture { TerminalFocuser.focus(session.terminal) }
            .onHover { isHovering = $0 }
            .help("Show the session")
        }
    }

    private var titleText: Text {
        let project = Text(session.projectName).font(.system(size: 13, weight: .bold))
        guard let title = session.displayTitle else { return project.foregroundColor(.white) }
        return Text("\(project) · \(title)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
    }

    /// Running time while the agent works, how long ago otherwise; the archive button on hover
    @ViewBuilder
    private func trailing(at now: Date) -> some View {
        if isHovering {
            Button {
                withAnimation(boringInteractiveSpring) { AgentSessionStore.shared.archive(session.id) }
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove from the list")
        } else {
            let text = session.isActive
                ? session.elapsed(at: now).map(AgentSession.formatDuration) ?? ""
                : AgentSession.formatAge(now.timeIntervalSince(session.updatedAt))
            Text(text)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch session.status {
        case .idle:
            Text("Ready").font(.system(size: 11, weight: .medium)).foregroundStyle(session.status.color)
        case .working, .compacting, .needsPermission:
            Text(session.statusLineText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(session.status.color)
                .lineLimit(1)
        case .done, .failed:
            if let message = session.message {
                // The agent's last reply, or the error
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(session.status == .failed ? session.status.color : .white.opacity(0.75))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(session.statusText).font(.system(size: 11, weight: .medium)).foregroundStyle(session.status.color)
            }
        }
    }
}
