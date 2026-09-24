import SwiftUI

// MARK: - Display Text

extension AgentSession {
    var statusText: String {
        switch status {
        case .idle: return "Ready"
        case .working: return runningSubagents > 0 ? "Working · \(runningSubagents) subagents" : "Working"
        case .needsPermission: return "Needs permission"
        case .compacting: return "Compacting"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    /// Beside the notch: finished tasks out of all of them, otherwise how long the turn has run
    func progressText(at now: Date) -> String? {
        if !tasks.isEmpty { return "\(completedTaskCount)/\(tasks.count)" }
        return elapsed(at: now).map(Self.formatDuration)
    }

    /// The colored line under "You: …" while Claude works or waits
    var statusLineText: String {
        switch status {
        case .needsPermission:
            return ["Needs permission", activity].compactMap { $0 }.joined(separator: " · ")
        case .compacting:
            return "Compacting the conversation"
        default:
            let subagents = runningSubagents > 0 ? " · \(runningSubagents) subagents" : ""
            return (activity ?? "Working") + subagents
        }
    }

    /// How long ago, in the list: "now", "5m", "3h", "2d"
    nonisolated static func formatAge(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension AgentSession.Status {
    var color: Color {
        switch self {
        case .idle: return .white.opacity(0.45)
        case .working: return .orange
        case .needsPermission: return .yellow
        case .compacting: return .purple
        case .done: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Status Glyph

struct AgentStatusGlyph: View {
    let status: AgentSession.Status
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch status {
            case .working, .compacting:
                AgentSpinner(color: status.color, lineWidth: max(1.5, size / 8))
            case .needsPermission:
                Image(systemName: "hand.raised.fill")
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

// MARK: - Collapsed Island

/// Collapsed Claude Code on a notched display: status left of the notch, progress to its right
struct AgentNotchLiveActivityView: View {
    let session: AgentSession
    let notch: CGSize
    /// Sessions working or waiting for you; shown beside the glyph when there are several
    var activeCount = 1

    var body: some View {
        let wing = NotchMetrics.wingWidth(for: notch)

        HStack(spacing: 0) {
            HStack(spacing: 2) {
                AgentStatusGlyph(status: session.status, size: max(12, notch.height - 18))
                if activeCount > 1 {
                    Text("\(activeCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: wing)

            // Hidden behind the camera housing
            Color.clear
                .frame(width: notch.width)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(session.progressText(at: timeline.date) ?? "")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(session.status == .needsPermission ? session.status.color : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: wing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(session.projectName), \(session.statusText)"))
    }
}

/// Collapsed Claude Code on a display without a notch: status, project and progress in one pill
struct CompactAgentLiveActivityView: View {
    let session: AgentSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 8) {
                AgentStatusGlyph(status: session.status, size: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(session.statusText)
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

// MARK: - Agents Tab

struct AgentsView: View {
    @ObservedObject private var store = AgentSessionStore.shared

    var body: some View {
        if store.sessions.isEmpty {
            AgentsEmptyView()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(store.sessions) { session in
                        AgentSessionRow(session: session)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }
}

/// Sound toggle and settings, in the tab bar while the Agents tab is open
struct AgentTabControls: View {
    @ObservedObject private var settings = SettingsDefaults.shared

    var body: some View {
        let soundsOn = settings.get(SettingsDefaults.agentSoundsEnabled)
        HStack(spacing: 2) {
            controlButton(soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          help: soundsOn ? "Mute Claude Code alerts" : "Play a sound when Claude needs you or finishes") {
                settings.set(SettingsDefaults.agentSoundsEnabled, value: !soundsOn)
            }
            controlButton("gearshape.fill", help: "Claude Code settings") {
                SettingsWindowController.shared.showSettings()
            }
        }
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(alignment: .top, spacing: 12) {
                AgentStatusGlyph(status: session.status, size: 18)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleText
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Claude")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
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
            .help("Show in terminal")
        }
    }

    private var titleText: Text {
        let project = Text(session.projectName).font(.system(size: 13, weight: .bold))
        guard let title = session.displayTitle else { return project.foregroundColor(.white) }
        return Text("\(project) · \(title)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
    }

    /// Running time while Claude works, how long ago otherwise; the archive button on hover
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
                // Claude's last reply, or the error
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

/// The session's task list: counts, then a few items around the one Claude is on
private struct AgentTaskChecklist: View {
    let tasks: [AgentTask]
    private let limit = 4

    var body: some View {
        let done = tasks.filter(\.isCompleted).count
        let inProgress = tasks.filter { $0.isActive && !$0.isCompleted }.count
        let current = tasks.firstIndex { !$0.isCompleted } ?? tasks.count
        let first = max(0, min(current - 1, tasks.count - limit))
        let shown = Array(tasks[first..<min(tasks.count, first + limit)])
        let remaining = tasks.count - first - shown.count

        VStack(alignment: .leading, spacing: 3) {
            Text("\(Text("Tasks").fontWeight(.semibold)) (\(done) done, \(inProgress) in progress, \(tasks.count - done - inProgress) pending)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

            if first > 0 {
                Text("\(first) done above")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            ForEach(shown) { task in
                HStack(spacing: 6) {
                    Image(systemName: task.isCompleted ? "checkmark.square.fill" : task.isActive ? "circle.dotted.circle" : "square")
                        .font(.system(size: 10))
                        .foregroundStyle(task.isCompleted ? .white.opacity(0.35) : task.isActive ? .orange : .white.opacity(0.5))
                    Text(task.title)
                        .font(.system(size: 11, weight: task.isActive ? .semibold : .regular))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .white.opacity(0.35) : .white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            if remaining > 0 {
                Text("+\(remaining) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

private struct AgentsEmptyView: View {
    @State private var isInstalled = ClaudeHookInstaller.standard.isInstalled
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))

            if isInstalled {
                Text("No Claude Code sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Sessions show up here once you send Claude a prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Text("Claude Code isn't connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Button("Connect Claude Code") {
                    do {
                        try ClaudeHookInstaller.standard.install()
                        isInstalled = true
                        errorText = nil
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                Text(errorText ?? "Adds hooks to ~/.claude/settings.json (backed up first)")
                    .font(.system(size: 10))
                    .foregroundStyle(errorText == nil ? .white.opacity(0.4) : .red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
