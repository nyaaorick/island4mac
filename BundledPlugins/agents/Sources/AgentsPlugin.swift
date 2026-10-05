import Foundation
import Combine
import IslandKit

/// Claude Code, Codex and ZCode in the island, as a plugin that ships inside the app. Its logic is the shared
/// AgentsCore (the hook socket, the installers, the sessions, answering a waiting hook); what it shows goes
/// through the plugin protocol only, with the island's own rows, fields and buttons
@main
struct AgentsPlugin: IslandPlugin {
    static let id = "agents"
    static let name = "Agents"
    static let symbol = "terminal"
    static let version = "1.0.0"
    static let description: String? = "Claude Code, Codex and ZCode sessions; answer their questions in the island"
    /// The hooks must be answered whether or not the Agents tab is one of yours
    static let background = true
    /// An agent at work shows beside the notch even while music plays
    static let priority = NotchPriority.high

    @Preference("Play a sound when an agent needs you, finishes or fails") var sounds = true
    @Preference("Show the active session beside the notch") var besideNotch = true

    /// The labels picked so far, by question text, for the prompt being answered
    @State var picked: [String: [String]] = [:]
    /// Which question of a prompt with several is showing
    @State var questionIndex = 0
    /// What a connect or disconnect said, under the agents list
    @State var note: String? = nil

    private var store: AgentSessionStore { AgentSessionStore.shared }

    func onStart() {
        AgentsService.shared.start(soundsOn: { sounds })
    }

    /// Ticks the elapsed time: every second while the tab shows, every minute beside the notch
    var timeline: [Date] {
        guard store.sessions.contains(where: \.isActive) else { return [] }
        let now = Island.now
        let step: TimeInterval = Island.isTabVisible ? 1 : 60
        return [Date(timeIntervalSince1970: (now.timeIntervalSince1970 / step).rounded(.down) * step + step)]
    }

    var body: some IslandContent {
        if besideNotch, let session = store.liveSession {
            Compact(symbol: symbol(for: session),
                    text: [session.projectName, session.progressText(at: Island.now) ?? session.statusText].joined(separator: " · "))
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
                    subtitle: subtitle(for: session),
                    symbol: symbol(for: session),
                    id: "session-\(session.id)",
                    actions: [RowAction("Remove from the list", symbol: "archivebox") { store.archive(session.id) }]) {
                    TerminalFocuser.focus(session.terminal)
                }
            }
            if store.sessions.contains(where: \.hasEnded) {
                Button("Clear finished", symbol: "archivebox") {
                    for session in store.sessions where session.hasEnded { store.archive(session.id) }
                }
            }
        }
    }

    private func subtitle(for session: AgentSession) -> String {
        var lines = ["\(session.agent.shortName) · \(session.isActive ? session.statusLineText : session.statusText) · \(AgentSession.formatAge(Island.now.timeIntervalSince(session.updatedAt)))"]
        if let prompt = session.prompt { lines.append("You: \(prompt)") }
        if !session.tasks.isEmpty {
            let current = session.currentTask.map { " · \($0.title)" } ?? ""
            lines.append("Tasks \(session.completedTaskCount)/\(session.tasks.count)\(current)")
        }
        return lines.joined(separator: "\n")
    }

    private func symbol(for session: AgentSession) -> String {
        switch session.status {
        case .working, .compacting: return "ellipsis.circle"
        case .needsPermission: return session.isAsking ? "questionmark.bubble.fill" : "hand.raised.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "circle.dotted"
        }
    }
}

/// What an agent is waiting on you for, filling the tab: one prompt at a time, the oldest first
struct PromptView: IslandComponent {
    let prompt: AgentPrompt
    let position: Int
    let count: Int
    let session: AgentSession?
    let picked: Binding<[String: [String]]>
    let questionIndex: Binding<Int>

    private var store: AgentSessionStore { AgentSessionStore.shared }

    var body: some IslandContent {
        let project = session?.projectName ?? prompt.agent.displayName
        let queue = count > 1 ? " · \(position) of \(count)" : ""
        switch prompt.kind {
        case .permission(let permission):
            Row("\(project) · \(prompt.agent.shortName) needs permission\(queue)", symbol: "hand.raised.fill")
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
            Row("\(project) · \(prompt.agent.shortName) is asking you\(queue)", symbol: "questionmark.bubble.fill")
            if prompt.canAnswer, let item = questions[safe: questionIndex.wrappedValue] {
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
    let questionIndex: Binding<Int>

    private var store: AgentSessionStore { AgentSessionStore.shared }
    private var isLast: Bool { questionIndex.wrappedValue >= questions.count - 1 }
    private var chosen: [String] { picked.wrappedValue[item.text] ?? [] }

    var body: some IslandContent {
        Row(item.text, subtitle: [item.header, questions.count > 1 ? "Question \(questionIndex.wrappedValue + 1) of \(questions.count)" : nil]
                .compactMap { $0 }.joined(separator: " · "), symbol: "text.bubble")
        for option in item.options {
            let isPicked = chosen.contains(option.label)
            Row(option.label, subtitle: option.description,
                symbol: item.allowsMultipleSelection ? (isPicked ? "checkmark.square.fill" : "square") : (isPicked ? "largecircle.fill.circle" : "circle"),
                id: "option-\(item.text.hashValue)-\(option.label)") {
                pick(option.label)
            }
        }
        TextField(item.options.isEmpty ? "Your answer, then Return" : "Other, then Return", id: "own-\(prompt.id)-\(questionIndex.wrappedValue)") { text in
            let own = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !own.isEmpty else { return }
            picked.wrappedValue[item.text] = item.allowsMultipleSelection ? chosen + [own] : [own]
            advance()
        }
        if item.allowsMultipleSelection || questions.count > 1 {
            Button(isLast ? "Submit" : "Next", symbol: isLast ? "paperplane" : "chevron.right") { advance() }
        }
    }

    private func pick(_ label: String) {
        if item.allowsMultipleSelection {
            var labels = chosen
            if let index = labels.firstIndex(of: label) { labels.remove(at: index) } else { labels.append(label) }
            picked.wrappedValue[item.text] = labels
        } else {
            picked.wrappedValue[item.text] = [label]
            advance()
        }
    }

    /// The next question, or the answers to Claude once each has one
    private func advance() {
        guard !chosen.isEmpty else { return }
        if !isLast {
            questionIndex.wrappedValue += 1
            return
        }
        var answers: [String: String] = [:]
        for question in questions {
            guard let labels = picked.wrappedValue[question.text], !labels.isEmpty else { return }
            answers[question.text] = labels.joined(separator: ", ")
        }
        store.answer(prompt.id, with: answers)
        picked.wrappedValue = [:]
        questionIndex.wrappedValue = 0
    }
}

/// No sessions yet: the agents to connect, and what connecting does
struct ConnectView: IslandComponent {
    let note: Binding<String?>

    var body: some IslandContent {
        let installers = AgentHookInstaller.all.filter(\.isAgentPresent)
        let connected = installers.filter(\.isInstalled)
        Row(connected.isEmpty ? "No agent is connected" : "No agent sessions",
            subtitle: connected.isEmpty ? "Connect one to see its sessions here and answer its questions"
                                        : "Sessions show up here once you send an agent a prompt",
            symbol: "terminal")
        for installer in installers {
            Row(installer.agent.displayName, subtitle: installer.isInstalled ? "Connected" : "Adds hooks to its config file (backed up first)",
                symbol: installer.isInstalled ? "checkmark.circle.fill" : "circle",
                id: "connect-\(installer.agent.rawValue)",
                actions: installer.isInstalled ? [RowAction("Disconnect", symbol: "minus.circle") { change(installer, connect: false) }] : []) {
                if !installer.isInstalled { change(installer, connect: true) }
            }
        }
        if let text = note.wrappedValue {
            Row(text, symbol: "info.circle")
        }
    }

    private func change(_ installer: AgentHookInstaller, connect: Bool) {
        do {
            if connect { try installer.install() } else { try installer.uninstall() }
            // Codex runs a new hook only once you've trusted it
            note.wrappedValue = connect && installer.agent == .codex ? "In Codex, run /hooks and trust the new hooks" : nil
        } catch {
            note.wrappedValue = error.localizedDescription
        }
        Island.refresh()
    }
}

/// The hook socket and the session store: AgentsCore wired up in this process
@MainActor
final class AgentsService {
    static let shared = AgentsService()

    private var server: AgentHookServer?
    private var changes: AnyCancellable?

    func start(soundsOn: @escaping () -> Bool) {
        // The helper the hooks run lives in the app, not beside this program
        if let app = ProcessInfo.processInfo.environment["ISLAND_APP_BUNDLE"] {
            AgentHookInstaller.appBundleURL = URL(fileURLWithPath: app, isDirectory: true)
        }
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
        // Claude is waiting on you: say so beside the notch and open the island on Agents
        store.onPrompt = { prompt in
            Island.popup(prompt.isQuestion ? "\(prompt.agent.shortName) is asking you" : "\(prompt.agent.shortName) needs permission",
                         symbol: prompt.isQuestion ? "questionmark.bubble.fill" : "hand.raised.fill", seconds: 4)
            Island.open()
        }
        store.startPruning()
        // The store changed: show it (rendered on the next turn, after the change landed)
        changes = store.objectWillChange.sink { _ in Island.refresh() }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
