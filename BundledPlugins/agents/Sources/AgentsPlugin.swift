import Foundation
import Combine
import IslandKit

/// Claude Code, Codex and ZCode in the island, as a plugin that ships inside the app. Its logic is the shared
/// Core/ (the hook socket, the installers, the sessions, answering a waiting hook); what it shows goes
/// through the plugin protocol only, with the island's own rows, fields and buttons
@main
struct AgentsPlugin: IslandPlugin {
    static let id = "agents"
    static let name = "Agents"
    static let symbol = "terminal"
    static let version = "1.1.0"
    static let description: String? = "Claude Code, Codex and ZCode sessions; answer their questions in the island"
    /// The hooks must be answered whether or not the Agents tab is one of yours
    static let background = true
    /// An agent at work shows beside the notch even while music plays
    static let priority = NotchPriority.high

    @Preference("Play a sound when an agent needs you, finishes or fails") var sounds = true
    @Preference("Show the active session beside the notch") var besideNotch = true
    @Preference("Open the island when an agent needs you") var openIsland = true

    /// The labels picked so far, by prompt id and question text, so a prompt answered in the terminal leaves
    /// nothing behind for the next one
    @State var picked: [String: [String]] = [:]
    /// Which question of a prompt with several is showing, by prompt id
    @State var questionIndex: [String: Int] = [:]
    /// What a connect or disconnect said, under the agents list
    @State var note: ConnectionNote? = nil

    private var store: AgentSessionStore { AgentSessionStore.shared }

    func onStart() {
        AgentsService.shared.start(soundsOn: { sounds }, opensIsland: { openIsland })
    }

    /// Ticks the elapsed time of a running turn every second while the tab shows and every minute beside the
    /// notch; with nothing running, the "5m" ages of the sessions on show tick every minute
    var timeline: [Date] {
        let step: TimeInterval
        if store.sessions.contains(where: \.isActive) {
            step = Island.isTabVisible ? 1 : 60
        } else if Island.isTabVisible, !store.sessions.isEmpty {
            step = 60
        } else {
            return []
        }
        let now = Island.now.timeIntervalSince1970
        return [Date(timeIntervalSince1970: (now / step).rounded(.down) * step + step)]
    }

    var body: some IslandContent {
        if besideNotch, let session = store.liveSession {
            Compact(symbol: AgentLook.symbol(for: session), text: compactText(for: session), state: AgentLook.state(of: session))
        }
        if let prompt = store.pendingPrompts.first {
            PromptView(prompt: prompt, position: 1, count: store.pendingPrompts.count,
                       session: store.sessions.first { $0.id == prompt.sessionID },
                       picked: $picked, questionIndex: $questionIndex)
        } else if store.sessions.isEmpty {
            ConnectView(note: $note)
        } else {
            for session in store.sessions {
                Row("\(session.projectName) · \(session.displayTitle ?? session.agent.displayName)",
                    subtitle: AgentLook.subtitle(for: session),
                    symbol: AgentLook.symbol(for: session),
                    state: AgentLook.state(of: session),
                    detail: AgentLook.detail(for: session, at: Island.now),
                    id: "session-\(session.id)",
                    actions: [RowAction("Remove from the list", symbol: "archivebox") { store.archive(session.id) }]) {
                    TerminalFocuser.focus(session.terminal)
                }
            }
            if store.sessions.contains(where: { $0.hasEnded || $0.status == .done || $0.status == .failed }) {
                Button("Clear finished", symbol: "archivebox") {
                    for session in store.sessions where session.hasEnded || session.status == .done || session.status == .failed {
                        store.archive(session.id)
                    }
                }
            }
            // Connecting and disconnecting stay at hand below the sessions
            AgentConnectionRows(note: $note)
        }
    }

    /// Beside the notch: the project, how many more sessions are busy, and the turn's progress (or what the
    /// agent is waiting on you for)
    private func compactText(for session: AgentSession) -> String {
        let others = store.activeSessionCount - (session.isActive ? 1 : 0)
        let project = others > 0 ? "\(session.projectName) +\(others)" : session.projectName
        let progress = session.status == .needsPermission ? session.statusText : session.progressText(at: Island.now) ?? session.statusText
        return "\(project) · \(progress)"
    }
}

/// How a session reads in the island: its state, symbol, status line and the time at the row's edge. The island
/// draws the colors, the turning arc and the pulse from the state; the plugin only says what the session is up to
enum AgentLook {
    static func state(of session: AgentSession) -> ItemState? {
        switch session.status {
        case .working, .compacting: return .working
        case .needsPermission: return .attention
        case .done: return .done
        case .failed: return .failed
        case .idle: return nil
        }
    }

    static func symbol(for session: AgentSession) -> String {
        switch session.status {
        case .working, .compacting: return "ellipsis.circle"
        case .needsPermission: return session.isAsking ? "questionmark.bubble.fill" : "hand.raised.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "circle.dotted"
        }
    }

    /// The status line first (the island colors it), then your prompt, then the agent's reply, its error or the
    /// task it's on
    static func subtitle(for session: AgentSession) -> String {
        var lines = [session.isActive ? session.statusLineText : session.statusText]
        if let prompt = session.prompt { lines.append("You: \(prompt)") }
        if (session.status == .done || session.status == .failed), let message = session.message, !message.isEmpty {
            lines.append(message)
        } else if !session.tasks.isEmpty {
            let current = session.currentTask.map { " · \($0.title)" } ?? ""
            lines.append("Tasks \(session.completedTaskCount)/\(session.tasks.count)\(current)")
        }
        return lines.joined(separator: "\n")
    }

    /// The agent, and the running time of its turn or how long ago it was last heard from
    static func detail(for session: AgentSession, at now: Date) -> String {
        let time = session.isActive
            ? session.elapsed(at: now).map(AgentSession.formatDuration) ?? AgentSession.formatAge(now.timeIntervalSince(session.updatedAt))
            : AgentSession.formatAge(now.timeIntervalSince(session.updatedAt))
        return "\(session.agent.shortName) · \(time)"
    }
}

/// What an agent is waiting on you for, filling the tab: one prompt at a time, the oldest first
struct PromptView: IslandComponent {
    let prompt: AgentPrompt
    let position: Int
    let count: Int
    let session: AgentSession?
    let picked: Binding<[String: [String]]>
    let questionIndex: Binding<[String: Int]>

    private var store: AgentSessionStore { AgentSessionStore.shared }

    var body: some IslandContent {
        let project = session?.projectName ?? prompt.agent.displayName
        let queue = count > 1 ? " · \(position) of \(count)" : ""
        let waiting = AgentSession.formatAge(Island.now.timeIntervalSince(prompt.askedAt))
        switch prompt.kind {
        case .permission(let permission):
            Row("\(project) · \(prompt.agent.shortName) needs permission\(queue)", subtitle: session?.displayTitle,
                symbol: "hand.raised.fill", state: .attention, detail: waiting)
            Row(permission.summary, subtitle: permission.detail.flatMap { $0 == permission.summary ? nil : $0 }, symbol: "terminal")
            if prompt.canAnswer {
                if let always = permission.alwaysAllowDescription {
                    Row("Always allow adds \(always)", symbol: "info.circle")
                }
                TextField("Or tell Claude what to do instead, then Return", id: "note-\(prompt.id)") { note in
                    if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.deny(prompt.id, note: note) }
                }
                Button("Deny", symbol: "xmark") { store.deny(prompt.id) }
                if permission.alwaysAllowDescription != nil {
                    Button("Always allow", symbol: "checkmark.seal") { store.allow(prompt.id, always: true) }
                }
                Button("Allow", symbol: "checkmark") { store.allow(prompt.id) }
            } else {
                terminalOnly
            }
        case .question(let questions):
            Row("\(project) · \(prompt.agent.shortName) is asking you\(queue)", subtitle: session?.displayTitle,
                symbol: "questionmark.bubble.fill", state: .attention, detail: waiting)
            if prompt.canAnswer, let item = questions[safe: questionIndex.wrappedValue[prompt.id.uuidString] ?? 0] {
                QuestionView(prompt: prompt, questions: questions, item: item, picked: picked, questionIndex: questionIndex)
            } else {
                for item in questions { Row(item.text, subtitle: item.header) }
                terminalOnly
            }
        }
        Button("Answer in terminal", symbol: "terminal") {
            if let session { TerminalFocuser.focus(session.terminal) }
            store.dismissPrompt(prompt.id)
        }
    }

    @IslandBuilder private var terminalOnly: some IslandContent {
        Row("Answer this one in the terminal", subtitle: "The session started before the island could answer for it", symbol: "info.circle")
    }
}

/// One question of a prompt. A single choice answers it on tap; several choices, or several questions, go on
/// with Next and end with Submit
struct QuestionView: IslandComponent {
    let prompt: AgentPrompt
    let questions: [AgentQuestion]
    let item: AgentQuestion
    let picked: Binding<[String: [String]]>
    let questionIndex: Binding<[String: Int]>

    private var store: AgentSessionStore { AgentSessionStore.shared }
    private var promptKey: String { prompt.id.uuidString }
    private var index: Int { questionIndex.wrappedValue[promptKey] ?? 0 }
    private var isLast: Bool { index >= questions.count - 1 }
    /// The answers to this prompt's questions, by question text
    private func key(_ question: AgentQuestion) -> String { "\(promptKey)|\(question.text)" }
    private var chosen: [String] { picked.wrappedValue[key(item)] ?? [] }

    var body: some IslandContent {
        Row(item.text, subtitle: [item.header, questions.count > 1 ? "Question \(index + 1) of \(questions.count)" : nil]
                .compactMap { $0 }.joined(separator: " · "), symbol: "text.bubble",
            detail: questions.count > 1 ? "\(index + 1)/\(questions.count)" : nil)
        for option in item.options {
            let isPicked = chosen.contains(option.label)
            Row(option.label, subtitle: option.description,
                symbol: item.allowsMultipleSelection ? (isPicked ? "checkmark.square.fill" : "square") : (isPicked ? "largecircle.fill.circle" : "circle"),
                id: "option-\(item.text.hashValue)-\(option.label)") {
                pick(option.label)
            }
        }
        TextField(item.options.isEmpty ? "Your answer, then Return" : "Other, then Return", id: "own-\(prompt.id)-\(index)") { text in
            let own = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !own.isEmpty else { return }
            picked.wrappedValue[key(item)] = item.allowsMultipleSelection ? chosen + [own] : [own]
            advance()
        }
        if item.allowsMultipleSelection || questions.count > 1 {
            Button(isLast ? "Submit" : "Next", symbol: isLast ? "paperplane" : "chevron.right") { advance() }
        }
    }

    private func pick(_ label: String) {
        if item.allowsMultipleSelection {
            var labels = chosen
            if let position = labels.firstIndex(of: label) { labels.remove(at: position) } else { labels.append(label) }
            picked.wrappedValue[key(item)] = labels
        } else {
            picked.wrappedValue[key(item)] = [label]
            advance()
        }
    }

    /// The next question, or the answers to Claude once each has one
    private func advance() {
        guard !chosen.isEmpty else { return }
        if !isLast {
            questionIndex.wrappedValue[promptKey] = index + 1
            return
        }
        var answers: [String: String] = [:]
        for question in questions {
            guard let labels = picked.wrappedValue[key(question)], !labels.isEmpty else { return }
            answers[question.text] = labels.joined(separator: ", ")
        }
        store.answer(prompt.id, with: answers)
        // This prompt's answers are sent; what other prompts picked stays theirs
        picked.wrappedValue = picked.wrappedValue.filter { !$0.key.hasPrefix(promptKey) }
        questionIndex.wrappedValue[promptKey] = nil
    }
}

/// What the last connect or disconnect said: a hint, or what went wrong
struct ConnectionNote: Codable, Equatable {
    let text: String
    let isError: Bool
}

/// No sessions yet: the agents to connect, and what connecting does
struct ConnectView: IslandComponent {
    let note: Binding<ConnectionNote?>

    var body: some IslandContent {
        let connected = AgentHookInstaller.all.filter { $0.isAgentPresent && $0.isInstalled }
        Row(connected.isEmpty ? "No agent is connected" : "No agent sessions",
            subtitle: connected.isEmpty ? "Connect one to see its sessions here and answer its questions"
                                        : "Sessions show up here once you send an agent a prompt",
            symbol: "terminal")
        AgentConnectionRows(note: note)
    }
}

/// One row per agent on this Mac: tap to connect one; a connected one disconnects from its row's actions
struct AgentConnectionRows: IslandComponent {
    let note: Binding<ConnectionNote?>

    var body: some IslandContent {
        let installers = AgentHookInstaller.all.filter(\.isAgentPresent)
        for installer in installers {
            Row(installer.agent.displayName, subtitle: installer.isInstalled ? "Connected" : "Adds hooks to its config file (backed up first)",
                symbol: installer.isInstalled ? "checkmark.circle.fill" : "circle",
                state: installer.isInstalled ? .done : nil,
                id: "connect-\(installer.agent.rawValue)",
                actions: installer.isInstalled ? [RowAction("Disconnect", symbol: "minus.circle") { change(installer, connect: false) }] : []) {
                if !installer.isInstalled { change(installer, connect: true) }
            }
        }
        if let note = note.wrappedValue {
            Row(note.text, symbol: note.isError ? "exclamationmark.triangle.fill" : "info.circle", state: note.isError ? .failed : nil)
        }
    }

    private func change(_ installer: AgentHookInstaller, connect: Bool) {
        do {
            if connect { try installer.install() } else { try installer.uninstall() }
            // Codex runs a new hook only once you've trusted it
            note.wrappedValue = connect && installer.agent == .codex
                ? ConnectionNote(text: "In Codex, run /hooks and trust the new hooks", isError: false) : nil
        } catch {
            note.wrappedValue = ConnectionNote(text: error.localizedDescription, isError: true)
        }
        Island.refresh()
    }
}

/// The hook socket and the session store: the Core folder wired up in this process
@MainActor
final class AgentsService {
    static let shared = AgentsService()

    private var server: AgentHookServer?
    private var changes: AnyCancellable?
    private var promptsAnswered: AnyCancellable?

    func start(soundsOn: @escaping () -> Bool, opensIsland: @escaping () -> Bool) {
        let store = AgentSessionStore.shared
        // ISLAND_AGENTS_SOCKET: a socket of its own, for tests, which then leave the agents' config files alone
        let socketOverride = ProcessInfo.processInfo.environment["ISLAND_AGENTS_SOCKET"].map { URL(fileURLWithPath: $0) }
        if socketOverride == nil { AgentHookInstaller.all.forEach { $0.refreshIfInstalled() } }
        server = AgentHookServer(socketURL: socketOverride ?? AgentHookInstaller.standard(.claude).socketURL) { event, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AgentSessionStore.shared.apply(event, reply: reply) }
            }
        }
        do {
            try server?.start()
        } catch {
            Island.log("The agent hook socket couldn't be opened: \(error)")
        }
        store.onStatusChange = { session, previous in
            if soundsOn() { AgentAlertSound.play(for: session, previous: previous) }
        }
        // Claude is waiting on you: say so beside the notch and open the island on Agents, held open until it's
        // answered (here or in the terminal)
        store.onPrompt = { prompt in
            Island.popup(prompt.isQuestion ? "\(prompt.agent.shortName) is asking you" : "\(prompt.agent.shortName) needs permission",
                         symbol: prompt.isQuestion ? "questionmark.bubble.fill" : "hand.raised.fill", seconds: 4)
            if opensIsland() { Island.open(hold: true) }
        }
        store.startPruning()
        // The store changed: show it (rendered on the next turn, after the change landed)
        changes = store.objectWillChange.sink { _ in Island.refresh() }
        // Every question answered: close the island a question opened
        promptsAnswered = store.$pendingPrompts
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .sink { noneLeft in if noneLeft { Island.close() } }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
