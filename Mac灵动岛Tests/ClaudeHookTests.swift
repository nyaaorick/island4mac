import XCTest
@testable import Mac灵动岛

/// Installing the hooks into a throwaway settings.json, never the real one
final class ClaudeHookInstallerTests: XCTestCase {

    private func makeInstaller() throws -> ClaudeHookInstaller {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeHookInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        var installer = ClaudeHookInstaller.standard
        installer.settingsURL = directory.appendingPathComponent(".claude/settings.json")
        installer.helperURL = directory.appendingPathComponent("support/island-claude-hook")
        installer.socketURL = directory.appendingPathComponent("support/hook.sock")
        return installer
    }

    private func write(_ settings: [String: Any], to installer: ClaudeHookInstaller) throws {
        try FileManager.default.createDirectory(at: installer.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: installer.settingsURL)
    }

    private func read(_ installer: ClaudeHookInstaller) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])
    }

    private func commands(for event: String, in settings: [String: Any]) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "other-tool notify"]]]],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "guard.sh"]]]],
        ],
    ]

    func testInstallKeepsOtherHooksAndSettings() throws {
        let installer = try makeInstaller()
        try write(existing, to: installer)

        try installer.install()

        let settings = try read(installer)
        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertEqual(commands(for: "Stop", in: settings), ["other-tool notify", installer.command])
        XCTAssertEqual(commands(for: "PreToolUse", in: settings), ["guard.sh", installer.command])
        for event in ClaudeHookInstaller.events {
            XCTAssertTrue(commands(for: event, in: settings).contains(installer.command), "\(event) is hooked")
        }
        XCTAssertTrue(installer.isInstalled)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.helperURL.path), "the helper is copied out of the bundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.settingsURL.path + ".mac-island-backup"))
    }

    func testInstallingTwiceAddsNothing() throws {
        let installer = try makeInstaller()
        try write(existing, to: installer)

        try installer.install()
        let once = try read(installer)
        try installer.install()

        XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: once))
    }

    func testUninstallRestoresTheOriginalSettings() throws {
        let installer = try makeInstaller()
        try write(existing, to: installer)

        try installer.install()
        try installer.uninstall()

        XCTAssertEqual(NSDictionary(dictionary: try read(installer)), NSDictionary(dictionary: existing))
        XCTAssertFalse(installer.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.helperURL.path))
    }

    func testInstallCreatesTheSettingsFile() throws {
        let installer = try makeInstaller()

        try installer.install()

        XCTAssertEqual(commands(for: "Stop", in: try read(installer)), [installer.command])
    }

    func testUnreadableSettingsAreLeftAlone() throws {
        let installer = try makeInstaller()
        try FileManager.default.createDirectory(at: installer.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: installer.settingsURL)

        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try String(contentsOf: installer.settingsURL, encoding: .utf8), "{ not json")
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

/// The bundled island-claude-hook talking to ClaudeHookServer, as Claude Code would run it
final class ClaudeHookBridgeTests: XCTestCase {

    private final class Received: @unchecked Sendable {
        var event: ClaudeHookEvent?
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

    private func runHelper(socket: URL, input: String, environment: [String: String] = [:]) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = helperURL
        process.arguments = [socket.path]
        process.environment = environment
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
        let server = ClaudeHookServer(socketURL: socket) { event in
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
        XCTAssertTrue(result.output.isEmpty, "Claude Code reads a hook's stdout, so the helper prints nothing")
        let event = try XCTUnwrap(received.event)
        XCTAssertEqual(event.kind, .permissionRequest)
        XCTAssertEqual(event.sessionID, "abc")
        XCTAssertEqual(event.cwd, "/tmp/project")
        XCTAssertEqual(event.toolActivity, "Bash · Clean the build")
        XCTAssertEqual(event.terminal.appBundleID, "com.googlecode.iterm2")
        XCTAssertEqual(event.terminal.itermSessionID, "w0t1p0:ABC")
        XCTAssertEqual(event.agentPID, getpid(), "the test process stands in for Claude Code")
        XCTAssertEqual(event.time.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func testHelperExitsQuietlyWhenTheIslandIsNotRunning() throws {
        let result = try runHelper(socket: try makeSocketURL(), input: #"{"session_id":"abc","hook_event_name":"Stop"}"#)

        XCTAssertEqual(result.status, 0, "a failing hook would show an error in Claude Code")
        XCTAssertTrue(result.output.isEmpty)
    }
}
