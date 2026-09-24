import Foundation

/// Where a Claude Code session runs, as reported by island-claude-hook
nonisolated struct AgentTerminal: Equatable, Sendable {
    /// Bundle ID of the app that owns the shell (Terminal, iTerm2, an editor…)
    var appBundleID: String?
    var termProgram: String?
    var itermSessionID: String?
    /// Controlling terminal, e.g. "ttys003"
    var tty: String?
}

/// An item of Claude Code's task list
nonisolated struct AgentTask: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var isCompleted: Bool
    var isActive = false
}

/// One Claude Code hook event (https://code.claude.com/docs/en/hooks) as island-claude-hook forwards it:
/// a JSON line describing where the session runs, then the hook's own JSON input.
nonisolated struct ClaudeHookEvent: Sendable {
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
    }

    var kind: Kind
    var sessionID: String
    /// When the hook ran. Hooks run in the background, so events can arrive out of order.
    var time: Date
    var agentPID: pid_t?
    var terminal = AgentTerminal()
    var cwd: String?
    var transcriptPath: String?
    /// Read from the transcript by ClaudeHookServer, for the events after which it may have changed
    var sessionTitle: String?
    /// SessionStart: startup, resume, clear or compact
    var source: String?
    var prompt: String?
    var toolName: String?
    var toolUseID: String?
    /// Short description of the tool call, e.g. the file being edited
    var toolSummary: String?
    /// The full task list, when the tool call is TodoWrite
    var todos: [AgentTask]?
    var taskID: String?
    var taskDescription: String?
    /// Notification text, Claude's final reply, or the error, depending on the event
    var message: String?
    var notificationType: String?
    /// PreCompact / PostCompact: manual or auto
    var trigger: String?

    init(kind: Kind, sessionID: String, time: Date = Date()) {
        self.kind = kind
        self.sessionID = sessionID
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
            time: (header["time"] as? String).flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? Date()
        )
        agentPID = (header["agent_pid"] as? String).flatMap { pid_t($0) }.flatMap { $0 > 0 ? $0 : nil }
        terminal = AgentTerminal(
            appBundleID: header["app_bundle_id"] as? String,
            termProgram: header["term_program"] as? String,
            itermSessionID: header["iterm_session_id"] as? String,
            tty: header["tty"] as? String
        )

        cwd = input["cwd"] as? String
        transcriptPath = input["transcript_path"] as? String
        source = input["source"] as? String
        prompt = Self.firstLine(input["prompt"])
        toolName = input["tool_name"] as? String
        toolUseID = input["tool_use_id"] as? String
        notificationType = input["notification_type"] as? String
        trigger = input["trigger"] as? String
        taskID = input["task_id"] as? String
        taskDescription = Self.firstLine(input["task_description"])

        let toolInput = input["tool_input"] as? [String: Any] ?? [:]
        if let toolName {
            toolSummary = Self.summary(ofTool: toolName, input: toolInput)
            if toolName == "TodoWrite" {
                todos = Self.tasks(fromTodos: toolInput["todos"])
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

    /// What the notch and the Agents tab show for a tool call: the tool plus its target
    var toolActivity: String? {
        guard let toolName else { return nil }
        guard let toolSummary else { return toolName }
        return "\(toolName) · \(toolSummary)"
    }

    private static func summary(ofTool tool: String, input: [String: Any]) -> String? {
        switch tool {
        case "Bash":
            return firstLine(input["description"]) ?? firstLine(input["command"])
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            let path = input["file_path"] as? String ?? input["notebook_path"] as? String
            return path.map { URL(fileURLWithPath: $0).lastPathComponent }
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
