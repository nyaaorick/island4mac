import SwiftUI

// MARK: - Display Text

extension AgentSession {
    var statusText: String {
        switch status {
        case .idle: return "Ready"
        case .working: return runningSubagents > 0 ? "Working · \(runningSubagents) subagents" : "Working"
        case .needsPermission: return isAsking ? "Has a question" : "Needs permission"
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

    /// The colored line under "You: …" while the agent works or waits
    var statusLineText: String {
        switch status {
        case .needsPermission:
            if isAsking { return "Waiting for your answer" }
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

extension AgentKind {
    /// The badge on a session row
    var color: Color {
        switch self {
        case .claude: return .orange
        case .codex: return .cyan
        case .zcode: return .mint
        }
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

// MARK: - Collapsed Island

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

// MARK: - Agents Tab

struct AgentsView: View {
    @ObservedObject private var store = AgentSessionStore.shared

    var body: some View {
        if store.sessions.isEmpty {
            AgentsEmptyView()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    // What an agent is waiting on you for comes first
                    ForEach(store.pendingPrompts) { prompt in
                        let session = store.sessions.first { $0.id == prompt.sessionID }
                        switch prompt.kind {
                        case .question(let questions):
                            AgentQuestionCard(prompt: prompt, questions: questions, session: session)
                        case .permission(let permission):
                            AgentPermissionCard(prompt: prompt, permission: permission, session: session)
                        }
                    }
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
                          help: soundsOn ? "Mute agent alerts" : "Play a sound when an agent needs you or finishes") {
                settings.set(SettingsDefaults.agentSoundsEnabled, value: !soundsOn)
            }
            controlButton("gearshape.fill", help: "Agent settings") {
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

/// Top of a prompt card: who's asking, a way to leave it to the terminal, and what you can do here
private struct AgentPromptHeader: View {
    let prompt: AgentPrompt
    let session: AgentSession?
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.yellow)
                Text("\(session?.projectName ?? prompt.agent.displayName) · \(title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    AgentSessionStore.shared.dismissPrompt(prompt.id)
                    if let session { TerminalFocuser.focus(session.terminal) }
                } label: {
                    Text("Answer in terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Leave this to the terminal and bring it to the front")
            }
            Text(prompt.canAnswer ? hint : "Answer this one in the terminal: the session started before the island could answer for it")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private extension View {
    func agentPromptCard() -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                    )
            )
    }
}

/// A tool call Claude Code wants to make, allowed or denied right in the island
private struct AgentPermissionCard: View {
    let prompt: AgentPrompt
    let permission: AgentPermission
    let session: AgentSession?
    /// What Claude should do instead; denying with it lets Claude carry on
    @State private var note = ""

    private var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentPromptHeader(
                prompt: prompt,
                session: session,
                symbol: "hand.raised.fill",
                title: "\(prompt.agent.shortName) wants to use \(permission.toolName)",
                hint: "Allow or deny here, or answer in the terminal"
            )

            Text(permission.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            if let detail = permission.detail, detail != permission.summary {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.35)))
            }

            if prompt.canAnswer {
                TextField("Or tell Claude what to do instead…", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                    .onSubmit { if hasNote { respond { $0.deny(prompt.id, note: note) } } }

                HStack(spacing: 8) {
                    Button(hasNote ? "Deny with note" : "Deny") {
                        respond { $0.deny(prompt.id, note: note) }
                    }
                    .help(hasNote ? "Deny, and Claude carries on with your note" : "Deny and stop Claude, like Esc in the terminal")

                    if let always = permission.alwaysAllowDescription {
                        Button("Always allow") {
                            respond { $0.allow(prompt.id, always: true) }
                        }
                        .help("Allow, and don't ask again for \(always)")
                    }

                    Spacer()

                    // Only a click allows: as the default button, Return in the note above would allow the call
                    // instead of sending the note, and so would Return anywhere else in the island
                    Button("Allow") {
                        respond { $0.allow(prompt.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                }
                .controlSize(.small)

                if let always = permission.alwaysAllowDescription {
                    Text("Always allow adds \(always)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }
            }
        }
        .agentPromptCard()
    }

    private func respond(_ action: (AgentSessionStore) -> Void) {
        withAnimation(boringInteractiveSpring) { action(AgentSessionStore.shared) }
    }
}

/// A question an agent is waiting on, answered right in the island. With a single question that takes one
/// choice, picking an option answers it; otherwise you pick, then submit.
private struct AgentQuestionCard: View {
    let prompt: AgentPrompt
    let questions: [AgentQuestion]
    let session: AgentSession?
    /// Question text → the labels you picked
    @State private var picked: [String: Set<String>] = [:]
    /// Question text → your own answer
    @State private var typed: [String: String] = [:]

    private var answersOnTap: Bool {
        questions.count == 1 && !questions[0].allowsMultipleSelection && !questions[0].options.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentPromptHeader(
                prompt: prompt,
                session: session,
                symbol: "questionmark.bubble.fill",
                title: "\(prompt.agent.shortName) is asking you",
                hint: answersOnTap ? "Pick an answer here, or answer in the terminal" : "Answer here and submit, or answer in the terminal"
            )

            ForEach(questions) { item in
                questionView(item)
            }

            if prompt.canAnswer && !answersOnTap {
                HStack {
                    Spacer()
                    Button("Submit") { submit() }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                        .foregroundStyle(.black)
                        .controlSize(.small)
                        .disabled(answers == nil)
                }
            }
        }
        .agentPromptCard()
    }

    private func questionView(_ item: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let header = item.header {
                    Text(header)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.15)))
                }
                Text(item.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(item.options, id: \.label) { option in
                optionRow(option, of: item)
            }

            TextField(item.options.isEmpty ? "Your answer" : "Other…", text: typedBinding(for: item))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                .disabled(!prompt.canAnswer)
                .onSubmit { if answers != nil { submit() } }
        }
    }

    private func optionRow(_ option: AgentQuestion.Option, of item: AgentQuestion) -> some View {
        let isPicked = picked[item.text, default: []].contains(option.label)
        let symbol = item.allowsMultipleSelection
            ? (isPicked ? "checkmark.square.fill" : "square")
            : (isPicked ? "largecircle.fill.circle" : "circle")
        return Button {
            pick(option.label, in: item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isPicked ? .yellow : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    if let description = option.description {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isPicked ? 0.12 : 0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!prompt.canAnswer)
    }

    private func pick(_ label: String, in item: AgentQuestion) {
        if item.allowsMultipleSelection {
            picked[item.text, default: []].formSymmetricDifference([label])
            return
        }
        picked[item.text] = [label]
        typed[item.text] = nil
        if answersOnTap { submit() }
    }

    private func typedBinding(for item: AgentQuestion) -> Binding<String> {
        Binding(
            get: { typed[item.text] ?? "" },
            set: { text in
                typed[item.text] = text
                // Your own words replace a single choice
                if !item.allowsMultipleSelection && !text.isEmpty { picked[item.text] = nil }
            }
        )
    }

    /// Every question's answer, or nil while one is unanswered
    private var answers: [String: String]? {
        var answers: [String: String] = [:]
        for item in questions {
            let own = (typed[item.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = item.options.map(\.label).filter { picked[item.text, default: []].contains($0) }
            let parts = item.allowsMultipleSelection ? chosen + (own.isEmpty ? [] : [own]) : [own.isEmpty ? chosen.first : own].compactMap { $0 }
            guard !parts.isEmpty else { return nil }
            answers[item.text] = parts.joined(separator: ", ")
        }
        return answers
    }

    private func submit() {
        guard prompt.canAnswer, let answers else { return }
        withAnimation(boringInteractiveSpring) {
            AgentSessionStore.shared.answer(prompt.id, with: answers)
        }
    }
}

/// The session's task list: counts, then a few items around the one the agent is on
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
    @State private var connected = Set(AgentHookInstaller.all.filter(\.isInstalled).map(\.agent))
    @State private var note: String?
    @State private var errorText: String?

    /// Agents used on this Mac that aren't connected yet; all of them when none has been used
    private var connectable: [AgentHookInstaller] {
        let installers = AgentHookInstaller.all.filter { !connected.contains($0.agent) }
        let present = installers.filter(\.isAgentPresent)
        return present.isEmpty && connected.isEmpty ? installers : present
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))

            if connected.isEmpty {
                Text("No agent is connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("No agent sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Sessions show up here once you send an agent a prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if !connectable.isEmpty {
                HStack(spacing: 8) {
                    ForEach(connectable, id: \.agent) { installer in
                        connectButton(installer)
                    }
                }
            }

            if let caption = errorText ?? note ?? (connectable.isEmpty ? nil : "Adds hooks to the agent's config file (backed up first)") {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(errorText == nil ? .white.opacity(0.4) : .red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func connectButton(_ installer: AgentHookInstaller) -> some View {
        let button = Button("Connect \(installer.agent.displayName)") {
            do {
                try installer.install()
                connected.insert(installer.agent)
                errorText = nil
                // Codex runs a new hook only once you've trusted it
                note = installer.agent == .codex ? "In Codex, run /hooks and trust the new hooks" : nil
            } catch {
                errorText = error.localizedDescription
            }
        }
        .tint(installer.agent.color)
        // The main call to action until an agent is connected
        if connected.isEmpty {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
