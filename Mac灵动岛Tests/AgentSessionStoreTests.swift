import XCTest
@testable import Mac灵动岛

@MainActor
final class AgentSessionStoreTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ kind: ClaudeHookEvent.Kind,
        at offset: TimeInterval,
        session: String = "s1",
        _ configure: (inout ClaudeHookEvent) -> Void = { _ in }
    ) -> ClaudeHookEvent {
        var event = ClaudeHookEvent(kind: kind, sessionID: session, time: start.addingTimeInterval(offset))
        event.cwd = "/Users/me/code/island"
        configure(&event)
        return event
    }

    /// Delivered as it happens, or later when `arrivingAt` is given
    private func deliver(_ event: ClaudeHookEvent, to store: AgentSessionStore, arrivingAt arrival: TimeInterval? = nil) {
        store.apply(event, now: arrival.map { start.addingTimeInterval($0) } ?? event.time)
    }

    func testATurnGoesFromWorkingToDone() throws {
        let store = AgentSessionStore()
        deliver(event(.sessionStart, at: 0), to: store)
        XCTAssertEqual(store.sessions.first?.status, .idle)
        XCTAssertNil(store.liveSession, "an idle session stays out of the notch")

        deliver(event(.userPromptSubmit, at: 1) { $0.prompt = "Fix the tests" }, to: store)
        deliver(event(.preToolUse, at: 2) { $0.toolName = "Bash"; $0.toolSummary = "Run the tests" }, to: store)
        let working = try XCTUnwrap(store.liveSession)
        XCTAssertEqual(working.status, .working)
        XCTAssertEqual(working.activity, "Bash · Run the tests")
        XCTAssertEqual(working.projectName, "island")
        XCTAssertEqual(working.elapsed(at: start.addingTimeInterval(61)), 60)

        deliver(event(.stop, at: 90) { $0.message = "All tests pass." }, to: store)
        let done = try XCTUnwrap(store.liveSession, "a finished turn stays beside the notch for a moment")
        XCTAssertEqual(done.status, .done)
        XCTAssertEqual(done.message, "All tests pass.")
        XCTAssertEqual(done.elapsed(at: start.addingTimeInterval(500)), 89, "the clock stops when the turn ends")

        let later = start.addingTimeInterval(90 + AgentSessionStore.finishedDisplayDuration + 1)
        XCTAssertNil(AgentSessionStore.liveSession(in: store.sessions, now: later), "then it leaves the notch")
    }

    func testAPermissionPromptWaitsForItsOwnToolCall() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0), to: store)
        deliver(event(.preToolUse, at: 1) { $0.toolName = "Read"; $0.toolUseID = "a" }, to: store)
        deliver(event(.preToolUse, at: 2) { $0.toolName = "Bash"; $0.toolUseID = "b" }, to: store)
        deliver(event(.permissionRequest, at: 3) { $0.toolName = "Bash"; $0.toolUseID = "b" }, to: store)
        XCTAssertEqual(store.liveSession?.status, .needsPermission)
        XCTAssertEqual(store.liveSession?.message, "Allow Bash?")

        deliver(event(.postToolUse, at: 4) { $0.toolUseID = "a" }, to: store)
        XCTAssertEqual(store.liveSession?.status, .needsPermission, "another tool call finishing doesn't answer the prompt")

        deliver(event(.postToolUse, at: 5) { $0.toolUseID = "b" }, to: store)
        XCTAssertEqual(store.liveSession?.status, .working)
    }

    func testTheSessionWaitingForYouTakesTheNotch() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0, session: "busy"), to: store)
        deliver(event(.userPromptSubmit, at: 1, session: "blocked"), to: store)
        deliver(event(.permissionRequest, at: 2, session: "blocked") { $0.toolName = "Edit" }, to: store)
        deliver(event(.preToolUse, at: 3, session: "busy") { $0.toolName = "Grep" }, to: store)

        XCTAssertEqual(store.liveSession?.id, "blocked")
        XCTAssertEqual(store.sessions.map(\.id), ["blocked", "busy"], "the Agents tab lists the most urgent first")
    }

    func testAFinishedTurnIsAnnouncedOverOtherWork() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0, session: "long"), to: store)
        deliver(event(.userPromptSubmit, at: 1, session: "quick"), to: store)
        deliver(event(.stop, at: 5, session: "quick"), to: store)
        deliver(event(.preToolUse, at: 6, session: "long") { $0.toolName = "Bash" }, to: store)

        XCTAssertEqual(store.liveSession?.id, "quick", "the finished turn shows while it's on show")
        let later = start.addingTimeInterval(5 + AgentSessionStore.finishedDisplayDuration + 1)
        XCTAssertEqual(AgentSessionStore.liveSession(in: store.sessions, now: later)?.id, "long")
    }

    func testAHeadlessRunShowsItsFinishedTurnBeforeGoing() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0), to: store)
        deliver(event(.stop, at: 10), to: store)
        // `claude -p` ends the session a moment after its turn
        deliver(event(.sessionEnd, at: 10.1), to: store)

        XCTAssertEqual(store.liveSession?.status, .done)

        // An interactive session that ends long after its last turn goes right away
        deliver(event(.userPromptSubmit, at: 0, session: "old"), to: store)
        deliver(event(.stop, at: 1, session: "old"), to: store)
        deliver(event(.sessionEnd, at: 60, session: "old"), to: store)
        XCTAssertFalse(store.sessions.contains { $0.id == "old" })
    }

    func testALateEventDoesNotUndoANewerStatus() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0), to: store)
        deliver(event(.stop, at: 10), to: store)
        // Hooks run in the background, so a tool call's event can arrive after the turn ended
        deliver(event(.preToolUse, at: 9) { $0.toolName = "Bash" }, to: store, arrivingAt: 11)

        XCTAssertEqual(store.sessions.first?.status, .done)
        XCTAssertNil(store.sessions.first?.activity)
    }

    func testTaskEventsGiveTheProgress() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0), to: store)
        for (offset, id) in ["t1", "t2", "t3"].enumerated() {
            deliver(event(.taskCreated, at: 1 + Double(offset)) { $0.taskID = id; $0.taskDescription = "Step \(id)" }, to: store)
        }
        deliver(event(.taskCompleted, at: 5) { $0.taskID = "t1" }, to: store)

        let session = store.sessions.first
        XCTAssertEqual(session?.progressText(at: start), "1/3")
        XCTAssertEqual(session?.currentTask?.title, "Step t2")
    }

    func testTodoWriteReplacesTheTaskList() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0), to: store)
        deliver(event(.preToolUse, at: 1) {
            $0.toolName = "TodoWrite"
            $0.todos = [
                AgentTask(id: "todo-0", title: "Read the code", isCompleted: true),
                AgentTask(id: "todo-1", title: "Writing the fix", isCompleted: false, isActive: true),
            ]
        }, to: store)

        XCTAssertEqual(store.sessions.first?.progressText(at: start), "1/2")
        XCTAssertEqual(store.sessions.first?.currentTask?.title, "Writing the fix")
    }

    func testEndedAndDeadSessionsAreDropped() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0, session: "ended"), to: store)
        deliver(event(.userPromptSubmit, at: 0, session: "killed") { $0.agentPID = 4242 }, to: store)
        deliver(event(.userPromptSubmit, at: 0, session: "alive") { $0.agentPID = 4343 }, to: store)

        deliver(event(.sessionEnd, at: 1, session: "ended"), to: store)
        store.prune(now: start.addingTimeInterval(2)) { $0 == 4343 }

        XCTAssertEqual(store.sessions.map(\.id), ["alive"])
    }

    func testTheFirstPromptStandsInUntilClaudeNamesTheSession() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0) { $0.prompt = "Add a Claude Code tab" }, to: store)
        deliver(event(.userPromptSubmit, at: 5) { $0.prompt = "Now write the tests" }, to: store)
        XCTAssertEqual(store.sessions.first?.displayTitle, "Add a Claude Code tab")
        XCTAssertEqual(store.sessions.first?.prompt, "Now write the tests", "the row shows your latest prompt")

        deliver(event(.stop, at: 9) { $0.sessionTitle = "Claude Code in the notch" }, to: store)
        XCTAssertEqual(store.sessions.first?.displayTitle, "Claude Code in the notch")
    }

    func testStatusChangesAreReportedOnce() {
        let store = AgentSessionStore()
        var reported: [(AgentSession.Status, AgentSession.Status?)] = []
        store.onStatusChange = { session, previous in reported.append((session.status, previous)) }

        deliver(event(.userPromptSubmit, at: 0), to: store)
        deliver(event(.preToolUse, at: 1) { $0.toolName = "Bash"; $0.toolUseID = "a" }, to: store)
        deliver(event(.preToolUse, at: 2) { $0.toolName = "Read" }, to: store)
        deliver(event(.permissionRequest, at: 3) { $0.toolName = "Bash"; $0.toolUseID = "a" }, to: store)
        deliver(event(.postToolUse, at: 4) { $0.toolUseID = "a" }, to: store)
        deliver(event(.stop, at: 5), to: store)

        XCTAssertEqual(reported.map(\.0), [.working, .needsPermission, .working, .done])
        XCTAssertEqual(reported.map(\.1), [nil, .working, .needsPermission, .working])
        XCTAssertEqual(AgentAlertSound.soundName(for: .needsPermission), "Ping")
        XCTAssertNil(AgentAlertSound.soundName(for: .working), "no sound while Claude just works")
    }

    func testArchivingTakesASessionOffTheList() {
        let store = AgentSessionStore()
        deliver(event(.userPromptSubmit, at: 0, session: "a"), to: store)
        deliver(event(.userPromptSubmit, at: 0, session: "b"), to: store)
        XCTAssertEqual(store.activeSessionCount, 2)

        store.archive("a")
        XCTAssertEqual(store.sessions.map(\.id), ["b"])
        XCTAssertEqual(store.activeSessionCount, 1)

        deliver(event(.preToolUse, at: 1, session: "a") { $0.toolName = "Edit" }, to: store)
        XCTAssertEqual(store.sessions.count, 2, "it comes back when Claude Code reports on it again")
    }

    func testAgesReadAtAGlance() {
        XCTAssertEqual(AgentSession.formatAge(20), "now")
        XCTAssertEqual(AgentSession.formatAge(33 * 60), "33m")
        XCTAssertEqual(AgentSession.formatAge(5 * 3600 + 10), "5h")
        XCTAssertEqual(AgentSession.formatAge(3 * 86_400), "3d")
    }

    func testParsesWhatTheHelperForwards() throws {
        let header = #"{"time":"1800000000.5","agent_pid":"321","tty":"ttys004","app_bundle_id":"com.apple.Terminal"}"#
        let input = """
            {"session_id":"abc","hook_event_name":"PreToolUse","cwd":"/tmp/app","tool_name":"TodoWrite","tool_use_id":"t9",
             "tool_input":{"todos":[{"content":"Plan","status":"completed","activeForm":"Planning"},
                                    {"content":"Build","status":"in_progress","activeForm":"Building"}]}}
            """
        let event = try XCTUnwrap(ClaudeHookEvent(forwarded: Data((header + "\n" + input).utf8)))

        XCTAssertEqual(event.kind, .preToolUse)
        XCTAssertEqual(event.sessionID, "abc")
        XCTAssertEqual(event.time, Date(timeIntervalSince1970: 1_800_000_000.5))
        XCTAssertEqual(event.agentPID, 321)
        XCTAssertEqual(event.terminal, AgentTerminal(appBundleID: "com.apple.Terminal", tty: "ttys004"))
        XCTAssertEqual(event.todos?.map(\.title), ["Plan", "Building"], "the task in progress shows what Claude is doing")
        XCTAssertEqual(event.todos?.map(\.isCompleted), [true, false])

        XCTAssertNil(ClaudeHookEvent(forwarded: Data(#"{"hook_event_name":"Stop"}"#.utf8)), "no header line")
        XCTAssertNil(ClaudeHookEvent(forwarded: Data("{}\n{\"hook_event_name\":\"Stop\"}".utf8)), "no session")
    }
}
