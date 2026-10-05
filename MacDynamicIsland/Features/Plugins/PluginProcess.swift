import Foundation
import Darwin

/// One running plugin program, in a process group of its own so it and anything it starts can be ended together.
/// Writing to it never blocks the caller: lines queue on a background queue and are dropped once too many wait,
/// so a plugin that stops reading its input can't freeze the island. PluginClient decides when to start and stop
final class PluginProcess: @unchecked Sendable {
    /// Also the process group id
    let pid: pid_t

    /// Bytes waiting to be written past this are dropped
    static let maxPendingInput = 64 * 1024

    private let inputFD: Int32
    private let output: FileHandle
    private let errors: FileHandle
    private let writeQueue: DispatchQueue
    private let lock = NSLock()
    private var pendingInput = 0
    private var inputClosed = false
    private var hasExited = false
    private var exitSource: DispatchSourceProcess?

    enum SpawnError: Error, CustomStringConvertible {
        case pipe(Int32)
        case spawn(Int32)

        var description: String {
            switch self {
            case .pipe(let code): return "couldn't create a pipe: \(String(cString: strerror(code)))"
            case .spawn(let code): return "couldn't start: \(String(cString: strerror(code)))"
            }
        }
    }

    /// Starts the program. The callbacks run on a background queue; `onExit` gets the exit status, or 128 plus
    /// the signal that ended it
    static func spawn(
        executable: URL,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        onOutput: @escaping @Sendable (Data) -> Void,
        onError: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) throws -> PluginProcess {
        let stdin = try makePipe()
        let stdout = try makePipe()
        let stderr = try makePipe()
        // The app's own ends stay out of every other child it starts (the now-playing helper, ditto): an inherited
        // copy of the input's write end would keep the plugin from ever seeing end of file
        for fd in [stdin.write, stdout.read, stderr.read] { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        // Writing to a plugin that has quit fails with EPIPE instead of raising SIGPIPE, which would end the app
        _ = fcntl(stdin.write, F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdin.read, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout.write, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr.write, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Its own process group (id = its pid); only stdin, stdout and stderr open; signals as a fresh program
        // has them, whatever the app does with its own
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                    | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))

        let argv = [executable.path] + arguments
        let envp = environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let status = withCStrings(argv) { argvPointers in
            withCStrings(envp) { envpPointers in
                posix_spawn(&pid, executable.path, &actions, &attributes, argvPointers, envpPointers)
            }
        }
        // The child has its copies now
        close(stdin.read)
        close(stdout.write)
        close(stderr.write)
        guard status == 0 else {
            close(stdin.write)
            close(stdout.read)
            close(stderr.read)
            throw SpawnError.spawn(status)
        }

        let process = PluginProcess(
            pid: pid,
            inputFD: stdin.write,
            output: FileHandle(fileDescriptor: stdout.read, closeOnDealloc: true),
            errors: FileHandle(fileDescriptor: stderr.read, closeOnDealloc: true)
        )
        process.listen(process.output, onData: onOutput)
        process.listen(process.errors, onData: onError)
        process.watchExit(onExit: onExit)
        return process
    }

    private init(pid: pid_t, inputFD: Int32, output: FileHandle, errors: FileHandle) {
        self.pid = pid
        self.inputFD = inputFD
        self.output = output
        self.errors = errors
        writeQueue = DispatchQueue(label: "plugin-input-\(pid)")
    }

    var exited: Bool {
        lock.lock(); defer { lock.unlock() }
        return hasExited
    }

    /// Queues `data` for the plugin's stdin. False when it was dropped: the plugin isn't reading, or input is closed
    @discardableResult
    func write(_ data: Data) -> Bool {
        lock.lock()
        guard !inputClosed, pendingInput + data.count <= Self.maxPendingInput else {
            lock.unlock()
            return false
        }
        pendingInput += data.count
        lock.unlock()

        writeQueue.async { [self] in
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = Darwin.write(inputFD, buffer.baseAddress! + offset, buffer.count - offset)
                    if written > 0 {
                        offset += written
                    } else if errno != EINTR {
                        break // EPIPE: the plugin is gone (F_SETNOSIGPIPE, so no signal)
                    }
                }
            }
            lock.lock()
            pendingInput -= data.count
            lock.unlock()
        }
        return true
    }

    /// End of input, which tells a plugin to quit. Queued behind pending writes, so it never closes the descriptor
    /// under a write in progress; a write stuck on a plugin that doesn't read ends once the plugin is killed
    func closeInput() {
        lock.lock()
        let alreadyClosed = inputClosed
        inputClosed = true
        lock.unlock()
        guard !alreadyClosed else { return }
        writeQueue.async { [inputFD] in close(inputFD) }
    }

    /// Signals the plugin and everything it started
    func signalGroup(_ signal: Int32) {
        _ = kill(-pid, signal)
    }

    /// Asks the plugin to quit, then kills its whole group if it's still there after `grace` seconds
    func terminate(grace: TimeInterval) {
        closeInput()
        signalGroup(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [self] in
            // Its children too, even if the plugin itself already quit
            signalGroup(SIGKILL)
        }
    }

    // MARK: - Helpers

    private func listen(_ handle: FileHandle, onData: @escaping @Sendable (Data) -> Void) {
        handle.readabilityHandler = { handle in
            let chunk = handle.availableData
            // End of file: stop listening, or this is called again at once, forever
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            onData(chunk)
        }
    }

    private func watchExit(onExit: @escaping @Sendable (Int32) -> Void) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { [self] in
            // Whatever it started goes with it. Still a zombie here, so its group id can't have been reused
            signalGroup(SIGKILL)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            lock.lock()
            hasExited = true
            lock.unlock()
            exitSource?.cancel()
            // A normal exit keeps its code; a signal reads as 128 plus the signal, like a shell reports it
            let signal = status & 0x7f
            onExit(signal == 0 ? (status >> 8) & 0xff : 128 + signal)
        }
        exitSource = source
        source.resume()
    }

    /// Waits up to `timeout` seconds for the process to end, reaping it. For quitting the app, when the main queue
    /// that would hear about the exit doesn't run again
    func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return true }
            usleep(10_000)
        }
        return false
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw SpawnError.pipe(errno) }
        return (fds[0], fds[1])
    }

    /// A NULL-terminated array of C strings, for posix_spawn
    private static func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return body(pointers)
    }
}
