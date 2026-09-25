import XCTest
@testable import Mac灵动岛

/// Installing the hooks into throwaway config files, never the real ones
final class AgentHookInstallerTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let home = home!
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
    }

    private func makeInstaller(_ agent: AgentKind = .claude) -> AgentHookInstaller {
        var installer = AgentHookInstaller.standard(agent)
        installer.homeURL = home
        installer.supportURL = home.appendingPathComponent("support")
        return installer
    }

    private func write(_ settings: [String: Any], to installer: AgentHookInstaller) throws {
        try FileManager.default.createDirectory(at: installer.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.settingsURL)
    }

    private func read(_ installer: AgentHookInstaller) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])
    }

    private func groups(for event: String, in table: [String: Any]?) -> [[String: Any]] {
        table?[event] as? [[String: Any]] ?? []
    }

    private func commands(for event: String, in table: [String: Any]?) -> [String] {
        groups(for: event, in: table).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "other-tool notify"]]]],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "guard.sh"]]]],
        ],
    ]

    func testInstallKeepsOtherHooksAndSettings() throws {
        let installer = makeInstaller()
        try write(existing, to: installer)

        try installer.install()

        let settings = try read(installer)
        let hooks = settings["hooks"] as? [String: Any]
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertEqual(commands(for: "Stop", in: hooks), ["other-tool notify", installer.command])
        XCTAssertEqual(commands(for: "PreToolUse", in: hooks), ["guard.sh", installer.command])
        for event in installer.events {
            XCTAssertTrue(commands(for: event, in: hooks).contains(installer.command(for: event)), "\(event) is hooked")
        }
        XCTAssertTrue(installer.command.hasSuffix(" claude"), "the helper is told which agent runs it")
        XCTAssertTrue(installer.isInstalled)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.helperURL.path), "the helper is copied out of the bundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.settingsURL.path + ".mac-island-backup"))
    }

    func testInstallingTwiceAddsNothing() throws {
        for agent in AgentKind.allCases {
            let installer = makeInstaller(agent)
            try write(existing, to: installer)

            try installer.install()
            let once = try read(installer)
            try installer.install()

            XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: once), "\(agent)")
        }
    }

    func testUninstallRestoresTheOriginalSettings() throws {
        for agent in AgentKind.allCases {
            let installer = makeInstaller(agent)
            try write(existing, to: installer)

            try installer.install()
            try installer.uninstall()

            XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: existing), "\(agent)")
            XCTAssertFalse(installer.isInstalled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: makeInstaller().helperURL.path))
    }

    func testInstallCreatesTheSettingsFile() throws {
        let installer = makeInstaller()

        try installer.install()

        XCTAssertEqual(commands(for: "Stop", in: try read(installer)["hooks"] as? [String: Any]), [installer.command])
    }

    func testUnreadableSettingsAreLeftAlone() throws {
        let installer = makeInstaller()
        try FileManager.default.createDirectory(at: installer.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: installer.settingsURL)

        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try String(contentsOf: installer.settingsURL, encoding: .utf8), "{ not json")
    }

    func testClaudesPermissionRequestHookWaitsForTheIslandsAnswer() throws {
        let installer = makeInstaller(.claude)
        try installer.install()

        let hooks = try read(installer)["hooks"] as? [String: Any]
        let handler = try XCTUnwrap((groups(for: "PermissionRequest", in: hooks).first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["command"] as? String, installer.command + " wait")
        XCTAssertNil(handler["async"], "Claude Code only reads the output of a hook it waits for")
        XCTAssertEqual(handler["timeout"] as? Int, AgentHookInstaller.replyTimeout)
        let stop = try XCTUnwrap((groups(for: "Stop", in: hooks).first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(stop["async"] as? Bool, true, "everything else stays in the background")
        XCTAssertEqual(makeInstaller(.zcode).command(for: "PermissionRequest"), makeInstaller(.zcode).command)
    }

    func testCodexHooksGoInHooksJSONWithoutAMatcher() throws {
        let installer = makeInstaller(.codex)
        XCTAssertEqual(installer.settingsURL.path, home.appendingPathComponent(".codex/hooks.json").path)

        try installer.install()

        let hooks = try read(installer)["hooks"] as? [String: Any]
        XCTAssertEqual(Set(hooks?.keys.map { $0 } ?? []), Set(installer.events))
        XCTAssertTrue(installer.events.contains("Interrupt"))
        XCTAssertFalse(installer.events.contains("Notification"), "Codex has no Notification event")
        let group = try XCTUnwrap(groups(for: "PreToolUse", in: hooks).first)
        XCTAssertNil(group["matcher"], "no matcher runs the hook for every tool")
        let handler = try XCTUnwrap((group["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["command"] as? String, installer.command)
        XCTAssertEqual(handler["timeout"] as? Int, 5)
        XCTAssertTrue(installer.command.hasSuffix(" codex"))
    }

    func testZCodeHooksAreNestedAndTurnedOn() throws {
        let installer = makeInstaller(.zcode)
        XCTAssertEqual(installer.settingsURL.path, home.appendingPathComponent(".zcode/cli/config.json").path)
        let original: [String: Any] = ["mcp": ["servers": ["docs": ["command": "docs-mcp"]]]]
        try write(original, to: installer)

        try installer.install()

        let settings = try read(installer)
        XCTAssertNotNil(settings["mcp"], "the rest of the config stays")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["enabled"] as? Bool, true, "ZCode skips config-file hooks unless they're enabled")
        let events = hooks["events"] as? [String: Any]
        XCTAssertEqual(Set(events?.keys.map { $0 } ?? []), Set(installer.events))
        XCTAssertEqual(commands(for: "Stop", in: events), [installer.command])
        XCTAssertNil(groups(for: "Stop", in: events).first?["matcher"], "\"*\" isn't a valid pattern to ZCode")
        XCTAssertTrue(installer.isInstalled)

        try installer.uninstall()
        XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: original))
    }

    func testZCodeKeepsItsOwnHooksOnUninstall() throws {
        let installer = makeInstaller(.zcode)
        let original: [String: Any] = [
            "hooks": ["enabled": true, "timeoutMs": 2000, "events": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]],
        ]
        try write(original, to: installer)

        try installer.install()
        let events = (try read(installer)["hooks"] as? [String: Any])?["events"] as? [String: Any]
        XCTAssertEqual(commands(for: "Stop", in: events), ["say done", installer.command])

        try installer.uninstall()
        XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: original))
    }

    func testTheHelperStaysWhileAnotherAgentUsesIt() throws {
        let claude = makeInstaller(.claude)
        let codex = makeInstaller(.codex)
        try claude.install()
        try codex.install()

        try codex.uninstall()
        XCTAssertTrue(FileManager.default.fileExists(atPath: claude.helperURL.path), "Claude Code still runs it")
        XCTAssertTrue(claude.isInstalled)

        try claude.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: claude.helperURL.path))
    }

    func testAnAgentIsPresentOnceItsFolderExists() throws {
        let zcode = makeInstaller(.zcode)
        XCTAssertFalse(zcode.isAgentPresent)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".zcode/cli"), withIntermediateDirectories: true)
        XCTAssertTrue(zcode.isAgentPresent)
    }
}

/// Session titles from Claude Code transcripts
final class ClaudeTranscriptTests: XCTestCase {

    private func transcript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let message = #"{"type":"assistant","message":{"content":"Working on it"}}"#

    func testATitleYouSetBeatsTheGeneratedOne() throws {
        let url = try transcript([
            #"{"type":"custom-title","customTitle":"Old name","sessionId":"s"}"#,
            message,
            #"{"type":"custom-title","customTitle":"Notch progress","sessionId":"s"}"#,
            #"{"type":"ai-title","aiTitle":"Generated title","sessionId":"s"}"#,
        ])
        XCTAssertEqual(ClaudeTranscript.title(at: url), "Notch progress")
    }

    func testTheGeneratedTitleWhenThereIsNoOther() throws {
        let url = try transcript([message, #"{"type":"ai-title","aiTitle":"Fix the build","sessionId":"s"}"#, message])
        XCTAssertEqual(ClaudeTranscript.title(at: url), "Fix the build")
        XCTAssertNil(ClaudeTranscript.title(at: try transcript([message, message])))
        XCTAssertNil(ClaudeTranscript.title(at: URL(fileURLWithPath: "/nonexistent/transcript.jsonl")))
    }

    func testOnlyTheEndOfALongTranscriptIsRead() throws {
        let filler = String(repeating: message + "\n", count: 20_000) // ~1 MB of conversation
        let url = try transcript([#"{"type":"custom-title","customTitle":"Early","sessionId":"s"}"#, filler + #"{"type":"custom-title","customTitle":"Late","sessionId":"s"}"#])
        XCTAssertEqual(ClaudeTranscript.title(at: url), "Late")
    }
}

/// Session names from Codex's session index
final class CodexSessionIndexTests: XCTestCase {

    func testTheLatestNameForTheSessionWins() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("session_index.jsonl")
        try Data([
            #"{"id":"s1","thread_name":"First name","updated_at":"2026-01-01T00:00:00Z"}"#,
            #"{"id":"s2","thread_name":"Another thread","updated_at":"2026-01-01T00:01:00Z"}"#,
            #"{"id":"s1","thread_name":"Renamed","updated_at":"2026-01-01T00:02:00Z"}"#,
        ].joined(separator: "\n").utf8).write(to: index)

        XCTAssertEqual(CodexSessionIndex.title(forSession: "s1", in: index), "Renamed")
        XCTAssertEqual(CodexSessionIndex.title(forSession: "s2", in: index), "Another thread")
        XCTAssertNil(CodexSessionIndex.title(forSession: "s3", in: index))
    }

    func testTheIndexSitsNextToTheSessionsFolder() {
        XCTAssertEqual(
            CodexSessionIndex.indexURL(forTranscript: "/Users/me/.codex/sessions/2026/02/15/rollout-x.jsonl").path,
            "/Users/me/.codex/session_index.jsonl"
        )
        XCTAssertTrue(CodexSessionIndex.indexURL(forTranscript: nil).path.hasSuffix("/.codex/session_index.jsonl"))
    }
}

/// The bundled island-claude-hook talking to AgentHookServer, as an agent would run it
final class AgentHookBridgeTests: XCTestCase {

    private final class Received: @unchecked Sendable {
        var event: AgentHookEvent?
    }

    private var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/island-claude-hook")
    }

    /// Unix socket paths are limited to 104 bytes, so keep this one short
    private func makeSocketURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hk-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("h.sock")
    }

    private func runHelper(
        socket: URL,
        agent: String? = nil,
        wait: Bool = false,
        input: String,
        environment: [String: String] = [:],
        directory: URL? = nil
    ) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [socket.path] + (agent.map { [$0] } ?? []) + (wait ? ["wait"] : [])
        process.environment = environment
        process.currentDirectoryURL = directory
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return (process.terminationStatus, stdout.fileHandleForReading.readDataToEndOfFile())
    }

    func testHelperForwardsAnEventToTheIsland() throws {
        let socket = try makeSocketURL()
        let received = Received()
        let arrived = expectation(description: "event arrived")
        let server = AgentHookServer(socketURL: socket) { event, _ in
            received.event = event
            arrived.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let input = """
            {"session_id":"abc","hook_event_name":"PermissionRequest","cwd":"/tmp/project","tool_name":"Bash",\
            "tool_use_id":"t1","tool_input":{"command":"rm -rf build","description":"Clean the build"}}
            """
        let result = try runHelper(socket: socket, input: input, environment: [
            "__CFBundleIdentifier": "com.googlecode.iterm2",
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t1p0:ABC",
        ])
        wait(for: [arrived], timeout: 5)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.isEmpty, "agents read a hook's stdout, so the helper prints nothing")
        let event = try XCTUnwrap(received.event)
        XCTAssertEqual(event.kind, .permissionRequest)
        XCTAssertEqual(event.sessionID, "abc")
        XCTAssertEqual(event.cwd, "/tmp/project")
        XCTAssertEqual(event.toolActivity, "Bash · Clean the build")
        XCTAssertEqual(event.terminal.appBundleID, "com.googlecode.iterm2")
        XCTAssertEqual(event.terminal.itermSessionID, "w0t1p0:ABC")
        XCTAssertEqual(event.agent, .claude, "hooks installed before other agents were supported name none")
        XCTAssertEqual(event.agentPID, getpid(), "the test process stands in for the agent")
        XCTAssertEqual(event.time.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testHelperSaysWhichAgentRanItAndWhere() throws {
        let socket = try makeSocketURL()
        let received = Received()
        let arrived = expectation(description: "event arrived")
        let server = AgentHookServer(socketURL: socket) { event, _ in
            received.event = event
            arrived.fulfill()
        }
        try server.start()
        defer { server.stop() }

        // ZCode's input has no snake_case cwd; the hook runs in the session's directory
        let project = socket.deletingLastPathComponent()
        let input = #"{"sessionId":"z1","session_id":"z1","hook_event_name":"UserPromptSubmit","prompt":"Add a README"}"#
        let result = try runHelper(socket: socket, agent: "zcode", input: input, environment: ["__CFBundleIdentifier": "dev.zcode.app"], directory: project)
        wait(for: [arrived], timeout: 5)

        XCTAssertEqual(result.status, 0)
        let event = try XCTUnwrap(received.event)
        XCTAssertEqual(event.agent, .zcode)
        XCTAssertEqual(event.kind, .userPromptSubmit)
        XCTAssertEqual(event.prompt, "Add a README")
        XCTAssertEqual(event.cwd.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, project.resolvingSymlinksInPath().path)
        XCTAssertEqual(event.terminal.appBundleID, "dev.zcode.app")
    }

    private let question = """
        {"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion",\
        "tool_input":{"questions":[{"question":"Which layout?","header":"Layout","multiSelect":false,\
        "options":[{"label":"Grid","description":"Cards in rows"},{"label":"List"}]}]}}
        """

    func testTheIslandsAnswerBecomesTheHooksOutput() throws {
        let socket = try makeSocketURL()
        let arrived = expectation(description: "question arrived")
        let received = Received()
        let server = AgentHookServer(socketURL: socket) { event, reply in
            received.event = event
            // Answer the way the store does
            if let reply, let output = AgentHookEvent.answerOutput(toolInput: event.toolInputJSON, answers: ["Which layout?": "Grid"]) {
                reply.send(output)
            }
            arrived.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let result = try runHelper(socket: socket, agent: "claude", wait: true, input: question)
        wait(for: [arrived], timeout: 5)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(received.event?.canReply, true)
        let output = try XCTUnwrap(JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        let specific = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(specific["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let updatedInput = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        XCTAssertEqual(updatedInput["answers"] as? [String: String], ["Which layout?": "Grid"])
        XCTAssertEqual((updatedInput["questions"] as? [[String: Any]])?.count, 1, "the questions go back as they came")
    }

    func testAPermissionTheIslandCantAnswerLetsTheHookGoAtOnce() throws {
        let socket = try makeSocketURL()
        let arrived = expectation(description: "event arrived")
        let server = AgentHookServer(socketURL: socket) { _, reply in
            XCTAssertNil(reply, "only questions keep the hook waiting")
            arrived.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let started = Date()
        let input = #"{"session_id":"abc","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"make"}}"#
        let result = try runHelper(socket: socket, agent: "claude", wait: true, input: input)
        wait(for: [arrived], timeout: 5)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.isEmpty, "no output leaves the decision to Claude Code's own prompt")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testHelperExitsQuietlyWhenTheIslandIsNotRunning() throws {
        let result = try runHelper(socket: try makeSocketURL(), input: #"{"session_id":"abc","hook_event_name":"Stop"}"#)

        XCTAssertEqual(result.status, 0, "a failing hook would show an error in the agent")
        XCTAssertTrue(result.output.isEmpty)
    }
}
