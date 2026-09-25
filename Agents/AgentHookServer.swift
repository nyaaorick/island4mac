import Foundation
import OSLog

/// The open connection of a hook that waits for the island's reply: Claude Code's PermissionRequest
/// hook, asking one of Claude's questions. Closing it without a reply leaves the question to the terminal.
nonisolated final class AgentHookReply: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32

    init(fd: Int32) {
        self.fd = fd
        // A hook the agent has already given up on mustn't take the app down with SIGPIPE
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { close() }

    /// Sends the hook's output and closes the connection
    func send(_ output: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        output.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.send(fd, bytes.baseAddress! + offset, bytes.count - offset, 0)
                if written < 0 {
                    if errno == EINTR { continue }
                    break
                }
                offset += written
            }
        }
        Darwin.close(fd)
        fd = -1
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }
}

/// Receives agent hook events from island-claude-hook on a Unix socket only this user can reach.
/// Each connection carries one event; they are parsed off the main thread.
nonisolated final class AgentHookServer: @unchecked Sendable {
    enum ServerError: Error {
        case pathTooLong
        case socket(Int32)
    }

    let socketURL: URL
    /// Given the connection to reply on when the hook waits for an answer to Claude's question
    private let onEvent: @Sendable (AgentHookEvent, AgentHookReply?) -> Void
    private let queue = DispatchQueue(label: "AgentHookServer")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "AgentHook")
    /// Only touched on `queue`
    private var listenSource: DispatchSourceRead?

    /// Largest event accepted; tool output can be big, but not this big
    private static let maxEventSize = 32 * 1024 * 1024
    /// Events after which the session's title is looked up
    private static let titleEvents: Set<AgentHookEvent.Kind> = [.sessionStart, .userPromptSubmit, .stop, .postCompact]

    init(socketURL: URL, onEvent: @escaping @Sendable (AgentHookEvent, AgentHookReply?) -> Void) {
        self.socketURL = socketURL
        self.onEvent = onEvent
    }

    func start() throws {
        try queue.sync {
            guard listenSource == nil else { return }
            try FileManager.default.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let path = Array(socketURL.path.utf8)
            guard path.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ServerError.pathTooLong }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw ServerError.socket(errno) }
            // A socket left by an earlier run (or another copy of the app) would block the bind
            unlink(socketURL.path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, chmod(socketURL.path, 0o600) == 0, listen(fd, 64) == 0 else {
                let error = errno
                close(fd)
                throw ServerError.socket(error)
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptConnections(on: fd) }
            source.setCancelHandler { close(fd) }
            source.resume()
            listenSource = source
            logger.info("Listening for agent hooks")
        }
    }

    func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
        }
    }

    private func acceptConnections(on fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return } // No more pending connections
            // Accepted sockets inherit O_NONBLOCK; read this one blocking, with a timeout instead
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            DispatchQueue.global(qos: .utility).async { [onEvent, logger] in
                guard let data = Self.readAll(from: client), var event = AgentHookEvent(forwarded: data) else {
                    logger.debug("Ignored an unreadable hook event")
                    close(client)
                    return
                }
                // Agents name a session a little after it starts, and the title can be renamed later
                if Self.titleEvents.contains(event.kind) {
                    event.sessionTitle = Self.title(of: event)
                }
                // Keep the connection only while there's a question the island can answer
                if event.canReply, event.kind == .permissionRequest, event.questions != nil {
                    onEvent(event, AgentHookReply(fd: client))
                } else {
                    close(client)
                    onEvent(event, nil)
                }
            }
        }
    }

    private static func title(of event: AgentHookEvent) -> String? {
        switch event.agent {
        case .claude:
            return event.transcriptPath.flatMap { ClaudeTranscript.title(at: URL(fileURLWithPath: $0)) }
        case .codex:
            return CodexSessionIndex.title(forSession: event.sessionID, in: CodexSessionIndex.indexURL(forTranscript: event.transcriptPath))
        case .zcode:
            // ZCode's transcript_path is a throwaway file holding only the latest message
            return nil
        }
    }

    private static func readAll(from fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            data.append(buffer, count: count)
            if data.count > maxEventSize { return nil }
        }
    }
}
