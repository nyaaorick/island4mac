import Foundation

/// The coding agents whose hooks the island listens to. The raw value is what island-claude-hook
/// is given on its command line and reports back.
nonisolated enum AgentKind: String, CaseIterable, Sendable {
    case claude
    case codex
    case zcode

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .zcode: return "ZCode"
        }
    }

    /// For the badge on a session row
    var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .zcode: return "ZCode"
        }
    }
}

/// Where an agent session runs, as reported by island-claude-hook
nonisolated struct AgentTerminal: Equatable, Sendable {
    /// Bundle ID of the app that owns the shell (Terminal, iTerm2, an editor, a desktop agent app…)
    var appBundleID: String?
    var termProgram: String?
    var itermSessionID: String?
    /// Controlling terminal, e.g. "ttys003"
    var tty: String?
}

/// An item of the agent's task list
nonisolated struct AgentTask: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool
    var isActive = false
}

/// One of the questions in a Claude Code AskUserQuestion call
nonisolated struct AgentQuestion: Equatable, Sendable, Identifiable {
    struct Option: Equatable, Sendable {
        var label: String
        var description: String?
    }

    /// The full question; answers are keyed by it
    var text: String
    /// Short chip label, e.g. "Auth method"
    var header: String?
    /// Empty for a question you answer in your own words
    var options: [Option]
    var allowsMultipleSelection: Bool

    var id: String { text }
}

/// One hook event as island-claude-hook forwards it: a JSON line describing which agent sent it and
/// where the session runs, then the hook's own JSON input. Claude Code (https://code.claude.com/docs/en/hooks),
/// Codex and ZCode all send Claude Code's input format, each with a subset of its events.
nonisolated struct AgentHookEvent: Sendable {
    enum Kind: String, Sendable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case permissionDenied = "PermissionDenied"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        case taskCreated = "TaskCreated"
        case taskCompleted = "TaskCompleted"
        case preCompact = "PreCompact"
        case postCompact = "PostCompact"
        /// Codex: you stopped the turn
        case interrupt = "Interrupt"
    }

    var kind: Kind
    var sessionID: String
    var agent: AgentKind = .claude
    /// When the hook ran. Hooks can run in the background, so events can arrive out of order.
    var time: Date
    var agentPID: pid_t?
    var terminal = AgentTerminal()
    var cwd: String?
    var transcriptPath: String?
    /// Looked up by AgentHookServer, for the events after which it may have changed
    var sessionTitle: String?
    /// SessionStart: startup, resume, clear or compact
    var source: String?
    var prompt: String?
    var toolName: String?
    var toolUseID: String?
    /// Short description of the tool call, e.g. the file being edited
    var toolSummary: String?
    /// The full task list, when the tool call writes one (TodoWrite, Codex's update_plan)
    var todos: [AgentTask]?
    var taskID: String?
    var taskDescription: String?
    /// Notification text, the agent's final reply, or the error, depending on the event
    var message: String?
    var notificationType: String?
    /// PreCompact / PostCompact: manual or auto
    var trigger: String?
    /// AskUserQuestion: what Claude is asking
    var questions: [AgentQuestion]?
    /// AskUserQuestion: the tool's input as sent, to hand back with your answers
    var toolInputJSON: Data?
    /// The hook waits for the island's reply, so the island can answer for you
    var canReply = false

    init(kind: Kind, sessionID: String, agent: AgentKind = .claude, time: Date = Date()) {
        self.kind = kind
        self.sessionID = sessionID
        self.agent = agent
        self.time = time
    }

    init?(forwarded data: Data) {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              let input = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any],
              let kind = (input["hook_event_name"] as? String).flatMap(Kind.init(rawValue:)),
              let sessionID = input["session_id"] as? String, !sessionID.isEmpty
        else { return nil }

        self.init(
            kind: kind,
            sessionID: sessionID,
            // Hooks installed before the island knew other agents don't say which agent they're for
            agent: (header["agent"] as? String).flatMap(AgentKind.init(rawValue:)) ?? .claude,
            time: (header["time"] as? String).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? Date()
        )
        agentPID = (header["agent_pid"] as? String).flatMap { pid_t($0) }.flatMap { $0 > 0 ? $0 : nil }
        canReply = header["can_reply"] as? String == "1"
        terminal = AgentTerminal(
            appBundleID: header["app_bundle_id"] as? String,
            termProgram: header["term_program"] as? String,
            itermSessionID: header["iterm_session_id"] as? String,
            tty: header["tty"] as? String
        )

        // Agents run hooks in the session's directory, so the helper's own is a fallback
        cwd = [input["cwd"], header["cwd"]].lazy.compactMap { $0 as? String }.first { !$0.isEmpty }
        transcriptPath = input["transcript_path"] as? String
        source = input["source"] as? String
        prompt = Self.firstLine(input["prompt"])
        toolName = input["tool_name"] as? String
        toolUseID = input["tool_use_id"] as? String
        notificationType = input["notification_type"] as? String
        trigger = input["trigger"] as? String
        taskID = input["task_id"] as? String
        taskDescription = Self.firstLine(input["task_description"])

        // Codex sends some tools' input (a patch, a command) as a bare string
        let toolInput = input["tool_input"] as? [String: Any] ?? (input["tool_input"] as? String).map { ["command": $0] } ?? [:]
        if let toolName {
            toolSummary = Self.summary(ofTool: toolName, input: toolInput)
            switch toolName {
            case "TodoWrite": todos = Self.tasks(fromTodos: toolInput["todos"])
            case "update_plan": todos = Self.tasks(fromPlan: toolInput["plan"])
            case Self.askUserQuestionTool:
                questions = Self.questions(from: toolInput["questions"])
                toolInputJSON = try? JSONSerialization.data(withJSONObject: toolInput)
            default: break
            }
        }

        switch kind {
        case .notification: message = Self.firstLine(input["message"])
        case .stop: message = Self.firstLine(input["last_assistant_message"])
        case .stopFailure: message = Self.firstLine(input["error_message"]) ?? Self.firstLine(input["error_type"])
        case .permissionDenied: message = Self.firstLine(input["denial_reason"])
        default: break
        }
    }

    static let askUserQuestionTool = "AskUserQuestion"

    /// The PermissionRequest hook output that answers an AskUserQuestion call: the tool's input with
    /// `answers` filled in (question text → the chosen labels, comma-separated, or your own words)
    static func answerOutput(toolInput: Data?, answers: [String: String]) -> Data? {
        var input = toolInput.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        input["answers"] = answers
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": Kind.permissionRequest.rawValue,
                "decision": ["behavior": "allow", "updatedInput": input],
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: output)
    }

    /// What the notch and the Agents tab show for a tool call: the tool plus its target
    var toolActivity: String? {
        guard let toolName else { return nil }
        guard let toolSummary else { return toolName }
        return "\(toolName) · \(toolSummary)"
    }

    private static func summary(ofTool tool: String, input: [String: Any]) -> String? {
        switch tool {
        case "Bash", "shell":
            return firstLine(input["description"]) ?? firstLine(commandLine(input["command"]))
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            // ZCode calls the file `path`
            let path = ["file_path", "notebook_path", "path"].lazy.compactMap { input[$0] as? String }.first
            return path.map { URL(fileURLWithPath: $0).lastPathComponent }
        case "apply_patch", "ApplyPatch":
            let patch = ["command", "patch", "input"].lazy.compactMap { input[$0] as? String }.first
            return patch.flatMap(patchSummary)
        case "Grep", "Glob":
            return firstLine(input["pattern"])
        case "WebFetch":
            return (input["url"] as? String).flatMap { URL(string: $0)?.host() }
        case "WebSearch":
            return firstLine(input["query"])
        case "Task", "Agent":
            return firstLine(input["description"])
        default:
            return nil
        }
    }

    /// A command given as a string, or as an argument vector such as ["bash", "-lc", "make"]
    private static func commandLine(_ value: Any?) -> String? {
        if let parts = value as? [String] {
            return parts.count == 3 && ["-c", "-lc"].contains(parts[1]) ? parts[2] : parts.joined(separator: " ")
        }
        return value as? String
    }

    /// The first file a patch in apply_patch format touches, and how many more there are
    private static func patchSummary(_ patch: String) -> String? {
        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        let files = patch.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
            return URL(fileURLWithPath: line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)).lastPathComponent
        }
        guard let first = files.first else { return nil }
        return files.count > 1 ? "\(first) +\(files.count - 1)" : first
    }

    private static func tasks(fromTodos value: Any?) -> [AgentTask]? {
        guard let todos = value as? [[String: Any]] else { return nil }
        return todos.enumerated().map { index, todo in
            let status = todo["status"] as? String
            return AgentTask(
                id: "todo-\(index)",
                title: firstLine(status == "in_progress" ? todo["activeForm"] ?? todo["content"] : todo["content"]) ?? "Task",
                isCompleted: status == "completed",
                isActive: status == "in_progress"
            )
        }
    }

    private static func questions(from value: Any?) -> [AgentQuestion]? {
        guard let items = value as? [[String: Any]] else { return nil }
        let questions = items.compactMap { item -> AgentQuestion? in
            guard let text = (item["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> AgentQuestion.Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return AgentQuestion.Option(label: label, description: firstLine(option["description"]))
            }
            return AgentQuestion(
                text: text,
                header: firstLine(item["header"]),
                options: options,
                allowsMultipleSelection: item["multiSelect"] as? Bool ?? false
            )
        }
        return questions.isEmpty ? nil : questions
    }

    /// Codex's plan: steps with the same statuses as TodoWrite
    private static func tasks(fromPlan value: Any?) -> [AgentTask]? {
        guard let plan = value as? [[String: Any]] else { return nil }
        return plan.enumerated().map { index, item in
            let status = item["status"] as? String
            return AgentTask(
                id: "plan-\(index)",
                title: firstLine(item["step"]) ?? "Step",
                isCompleted: status == "completed",
                isActive: status == "in_progress"
            )
        }
    }

    /// First non-empty line, trimmed and kept short enough for one row
    private static func firstLine(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let line = text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 160 ? String(line.prefix(160)) + "…" : line
    }
}
