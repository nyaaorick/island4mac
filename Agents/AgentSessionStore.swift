import Foundation
import Combine

/// A Claude Code session as the island shows it
struct AgentSession: Identifiable, Equatable {
    enum Status: Equatable {
        /// Started, waiting for a prompt
        case idle
        case working
        case needsPermission
        case compacting
        case done
        case failed
    }

    let id: String
    var cwd = ""
    var status: Status = .idle
    /// Claude Code's title for the session (from /rename, the Claude app or Claude itself)
    var title: String?
    /// Stands in for the title until Claude Code has named the session
    var firstPrompt: String?
    /// Your latest prompt
    var prompt: String?
    /// What Claude is doing now, e.g. "Bash · Run the tests"
    var activity: String?
    /// The permission prompt, Claude's final reply or the error, depending on `status`
    var message: String?
    var tasks: [AgentTask] = []
    var runningSubagents = 0
    var turnStartedAt: Date?
    var finishedAt: Date?
    var updatedAt: Date
    var agentPID: pid_t?
    var terminal = AgentTerminal()
    /// Claude Code has exited; the session stays only while its finished turn is still on show
    var hasEnded = false

    /// Time of the event that last set `status`, so a late event can't undo a newer one
    private var statusChangedAt = Date.distantPast
    /// The tool call waiting for permission; other tool calls finishing don't clear the prompt
    private var pendingPermissionToolUseID: String?

    init(id: String, updatedAt: Date) {
        self.id = id
        self.updatedAt = updatedAt
    }

    var projectName: String {
        cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent
    }

    var displayTitle: String? { title ?? firstPrompt }

    var isActive: Bool { status == .working || status == .needsPermission || status == .compacting }

    var completedTaskCount: Int { tasks.filter(\.isCompleted).count }

    /// The task Claude is on: the one marked in progress, or else the first one left
    var currentTask: AgentTask? {
        tasks.first(where: \.isActive) ?? tasks.first { !$0.isCompleted }
    }

    /// How long the current (or last) turn has run
    func elapsed(at now: Date) -> TimeInterval? {
        guard let turnStartedAt else { return nil }
        return max(0, (finishedAt ?? now).timeIntervalSince(turnStartedAt))
    }

    mutating func apply(_ event: ClaudeHookEvent, now: Date) {
        updatedAt = now
        if let cwd = event.cwd, !cwd.isEmpty { self.cwd = cwd }
        if let pid = event.agentPID { agentPID = pid }
        if event.terminal != AgentTerminal() { terminal = event.terminal }
        if let sessionTitle = event.sessionTitle { title = sessionTitle }

        let isLatest = event.time >= statusChangedAt
        func setStatus(_ newStatus: Status) {
            guard isLatest else { return }
            status = newStatus
            statusChangedAt = event.time
        }

        switch event.kind {
        case .sessionStart:
            if event.source == "clear" {
                title = event.sessionTitle
                firstPrompt = nil
                prompt = nil
                activity = nil
                message = nil
                tasks = []
                turnStartedAt = nil
                finishedAt = nil
            }
            // After a compaction the session carries on with what it was doing
            if event.source != "compact" { setStatus(.idle) }

        case .userPromptSubmit:
            guard isLatest else { return }
            setStatus(.working)
            prompt = event.prompt
            if firstPrompt == nil { firstPrompt = event.prompt }
            activity = nil
            message = nil
            pendingPermissionToolUseID = nil
            turnStartedAt = event.time
            finishedAt = nil
            // A finished task list belongs to the previous piece of work
            if !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) { tasks = [] }

        case .preToolUse:
            if let todos = event.todos { tasks = todos }
            guard isLatest, status != .needsPermission else { return }
            setStatus(.working)
            activity = event.toolActivity
            startTurnIfNeeded(at: event.time)

        case .permissionRequest:
            setStatus(.needsPermission)
            guard isLatest else { return }
            pendingPermissionToolUseID = event.toolUseID
            activity = event.toolActivity
            message = event.toolName.map { "Allow \($0)?" }
            startTurnIfNeeded(at: event.time)

        case .notification:
            // The permission prompt also arrives as PermissionRequest; this covers older Claude Code versions
            guard event.notificationType == "permission_prompt", status != .needsPermission else { return }
            setStatus(.needsPermission)
            if isLatest { message = event.message }

        case .postToolUse, .postToolUseFailure, .permissionDenied:
            guard status == .needsPermission,
                  pendingPermissionToolUseID == nil || pendingPermissionToolUseID == event.toolUseID else { return }
            pendingPermissionToolUseID = nil
            setStatus(.working)
            if isLatest { message = nil }

        case .stop, .stopFailure:
            setStatus(event.kind == .stop ? .done : .failed)
            guard isLatest else { return }
            activity = nil
            message = event.message
            pendingPermissionToolUseID = nil
            runningSubagents = 0
            finishedAt = event.time

        case .subagentStart:
            runningSubagents += 1

        case .subagentStop:
            runningSubagents = max(0, runningSubagents - 1)

        case .taskCreated:
            guard let taskID = event.taskID, !tasks.contains(where: { $0.id == taskID }) else { return }
            tasks.append(AgentTask(id: taskID, title: event.taskDescription ?? "Task", isCompleted: false))

        case .taskCompleted:
            guard let taskID = event.taskID else { return }
            if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                tasks[index].isCompleted = true
                tasks[index].isActive = false
            } else {
                tasks.append(AgentTask(id: taskID, title: event.taskDescription ?? "Task", isCompleted: true))
            }

        case .preCompact:
            setStatus(.compacting)

        case .postCompact:
            // An automatic compaction happens mid-turn; /compact leaves the session waiting for a prompt
            setStatus(event.trigger == "auto" ? .working : .idle)

        case .sessionEnd:
            break
        }
    }

    /// The app may start in the middle of a turn
    private mutating func startTurnIfNeeded(at time: Date) {
        if turnStartedAt == nil || finishedAt != nil {
            turnStartedAt = time
            finishedAt = nil
        }
    }
}

/// Claude Code sessions reported through island-claude-hook
@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    /// Most urgent first
    @Published private(set) var sessions: [AgentSession] = []
    /// The session the collapsed island shows beside the notch
    @Published private(set) var liveSession: AgentSession?

    /// How long a finished turn stays beside the notch
    static let finishedDisplayDuration: TimeInterval = 8
    /// Sessions that have been quiet this long are dropped
    private let staleAfter: TimeInterval = 12 * 60 * 60

    private var liveRefreshTask: Task<Void, Never>?
    private var pruneTimer: Timer?

    /// Called when a session's status changes, e.g. to play a sound when Claude needs you
    var onStatusChange: ((_ session: AgentSession, _ previous: AgentSession.Status?) -> Void)?

    /// Sessions working or waiting for you
    var activeSessionCount: Int { sessions.filter(\.isActive).count }

    /// Whether the collapsed island shows Claude Code beside the notch
    var showsCompactLiveActivity: Bool {
        SettingsDefaults.shared.get(SettingsDefaults.showAgentLiveActivity) && liveSession != nil
    }

    func apply(_ event: ClaudeHookEvent, now: Date = Date()) {
        var updated = sessions
        var changed: (session: AgentSession, previous: AgentSession.Status?)?
        if event.kind == .sessionEnd {
            // `claude -p` exits right after its turn; let the finished turn show before the session goes
            if let index = updated.firstIndex(where: { $0.id == event.sessionID }),
               Self.isShowingFinishedTurn(updated[index], now: now) {
                updated[index].hasEnded = true
            } else {
                updated.removeAll { $0.id == event.sessionID }
            }
        } else if let index = updated.firstIndex(where: { $0.id == event.sessionID }) {
            let previous = updated[index].status
            updated[index].apply(event, now: now)
            if updated[index].status != previous { changed = (updated[index], previous) }
        } else {
            var session = AgentSession(id: event.sessionID, updatedAt: now)
            session.apply(event, now: now)
            updated.append(session)
            changed = (session, nil)
        }
        publish(updated, now: now)
        if let changed { onStatusChange?(changed.session, changed.previous) }
    }

    /// Takes a session off the list; it comes back if Claude Code reports on it again
    func archive(_ sessionID: String) {
        publish(sessions.filter { $0.id != sessionID }, now: Date())
    }

    /// Drops sessions whose Claude Code process exited without a SessionEnd (killed, crashed)
    func startPruning() {
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
    }

    func prune(now: Date = Date(), isAlive: (pid_t) -> Bool = AgentSessionStore.processIsAlive) {
        let kept = sessions.filter { session in
            if let pid = session.agentPID, !isAlive(pid) { return false }
            return now.timeIntervalSince(session.updatedAt) < staleAfter
        }
        if kept.count != sessions.count {
            publish(kept, now: now)
        }
    }

    nonisolated static func processIsAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }

    private func publish(_ updated: [AgentSession], now: Date) {
        sessions = updated.sorted { lhs, rhs in
            let (left, right) = (Self.urgency(of: lhs), Self.urgency(of: rhs))
            return left != right ? left < right : lhs.updatedAt > rhs.updatedAt
        }
        refreshLiveSession(now: now)
    }

    private func refreshLiveSession(now: Date = Date()) {
        if sessions.contains(where: { $0.hasEnded && !Self.isShowingFinishedTurn($0, now: now) }) {
            sessions.removeAll { $0.hasEnded && !Self.isShowingFinishedTurn($0, now: now) }
        }
        let live = Self.liveSession(in: sessions, now: now)
        if live != liveSession {
            liveSession = live
        }

        // Look again when the next finished turn is due to leave the notch
        liveRefreshTask?.cancel()
        let nextExpiry = sessions
            .compactMap { $0.finishedAt?.addingTimeInterval(Self.finishedDisplayDuration) }
            .filter { $0 > now }
            .min()
        if let nextExpiry {
            liveRefreshTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(nextExpiry.timeIntervalSince(now) + 0.05))
                guard !Task.isCancelled else { return }
                self?.refreshLiveSession()
            }
        }
    }

    /// Needs permission first, then a turn that just finished (it's only on show briefly), then working
    static func liveSession(in sessions: [AgentSession], now: Date) -> AgentSession? {
        func rank(_ session: AgentSession) -> Int? {
            switch session.status {
            case .needsPermission: return 0
            case .done, .failed: return isShowingFinishedTurn(session, now: now) ? 1 : nil
            case .working, .compacting: return 2
            case .idle: return nil
            }
        }
        return sessions
            .compactMap { session in rank(session).map { (session, $0) } }
            .min { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.updatedAt > rhs.0.updatedAt }?
            .0
    }

    private static func isShowingFinishedTurn(_ session: AgentSession, now: Date) -> Bool {
        guard session.status == .done || session.status == .failed, let finishedAt = session.finishedAt else { return false }
        return now.timeIntervalSince(finishedAt) < finishedDisplayDuration
    }

    private static func urgency(of session: AgentSession) -> Int {
        switch session.status {
        case .needsPermission: return 0
        case .working, .compacting: return 1
        case .failed: return 2
        case .done: return 3
        case .idle: return 4
        }
    }
}
