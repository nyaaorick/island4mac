import Foundation
import OSLog

/// Receives Claude Code hook events from island-claude-hook on a Unix socket only this user can reach.
/// Each connection carries one event; they are parsed off the main thread.
nonisolated final class ClaudeHookServer: @unchecked Sendable {
    enum ServerError: Error {
        case pathTooLong
        case socket(Int32)
    }

    let socketURL: URL
    private let onEvent: @Sendable (ClaudeHookEvent) -> Void
    private let queue = DispatchQueue(label: "ClaudeHookServer")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "ClaudeHook")
    /// Only touched on `queue`
    private var listenSource: DispatchSourceRead?

    /// Largest event accepted; tool output can be big, but not this big
    private static let maxEventSize = 32 * 1024 * 1024
    /// Events after which the session's title is looked up in its transcript
    private static let titleEvents: Set<ClaudeHookEvent.Kind> = [.sessionStart, .userPromptSubmit, .stop, .postCompact]

    init(socketURL: URL, onEvent: @escaping @Sendable (ClaudeHookEvent) -> Void) {
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
            logger.info("Listening for Claude Code hooks")
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
                defer { close(client) }
                guard let data = Self.readAll(from: client) else { return }
                guard var event = ClaudeHookEvent(forwarded: data) else {
                    logger.debug("Ignored an unreadable hook event")
                    return
                }
                // Claude Code names a session a little after it starts, and the title can be renamed later
                if Self.titleEvents.contains(event.kind), let path = event.transcriptPath {
                    event.sessionTitle = ClaudeTranscript.title(at: URL(fileURLWithPath: path))
                }
                onEvent(event)
            }
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
