//
//  main.swift
//  island-claude-hook
//
//  Claude Code, Codex and ZCode run this for every hook event (AgentHookInstaller registers it
//  in each agent's config file). It forwards the event JSON from stdin to Mac Dynamic Island over the
//  Unix socket given as the first argument, prefixed with one JSON line saying which agent ran
//  it (the second argument) and where the session runs, so the island can bring its terminal
//  to the front.
//
//  Given "wait" as the third argument (Claude Code's PermissionRequest hook, which Claude Code
//  runs in the foreground), it then waits for the island to reply and prints the reply as the
//  hook's output: that is how you answer Claude's questions from the island. The island closes
//  the connection without a reply for everything else.
//
//  Otherwise it prints nothing, and it always exits 0: stdout is read by the agent as hook
//  output, a non-zero exit shows a "hook error" notice, and the island may not be running.
//
//  Only Darwin is imported on purpose: this runs on every hook event, so it has to start fast.
//

import Darwin

private let maxPayload = 16 * 1024 * 1024
private let maxReply = 1024 * 1024
/// How long a waiting hook waits for an answer; as long as its hook timeout
private let waitSeconds: UInt32 = 24 * 60 * 60

private func readStdin() -> [UInt8]? {
    var capacity = 64 * 1024
    var buffer = [UInt8](repeating: 0, count: capacity)
    var length = 0
    while true {
        if length == capacity {
            if capacity >= maxPayload { return nil }
            capacity *= 2
            buffer.append(contentsOf: [UInt8](repeating: 0, count: capacity - buffer.count))
        }
        let count = buffer.withUnsafeMutableBytes {
            read(STDIN_FILENO, $0.baseAddress! + length, capacity - length)
        }
        if count == 0 { break }
        if count < 0 {
            if errno == EINTR { continue }
            break
        }
        length += count
    }
    return Array(buffer[..<length])
}

private func parent(of pid: pid_t) -> pid_t {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
    return pid_t(info.pbi_ppid)
}

/// The agent process: the first ancestor that isn't a shell wrapping the hook command.
private func agentProcess() -> pid_t {
    let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    var pid = getppid()
    var depth = 0
    while pid > 1 && depth < 4 {
        var name = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        proc_name(pid, &name, UInt32(name.count))
        if !shells.contains(String(cString: name)) { return pid }
        pid = parent(of: pid)
        depth += 1
    }
    return 0
}

/// Name of the controlling terminal, e.g. "ttys003" (Terminal and iTerm2 report it per tab).
private func controllingTTY() -> String? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size != 0 else { return nil }
    let device = info.kp_eproc.e_tdev
    if device == -1 { return nil } // NODEV
    guard let name = devname(device, mode_t(S_IFCHR)) else { return nil }
    return String(cString: name)
}

private func environment(_ name: String) -> String? {
    getenv(name).map { String(cString: $0) }
}

/// The header object, built up one `"key":"value"` pair at a time.
private struct Header {
    private var bytes = Array("{".utf8)
    private static let hex = Array("0123456789abcdef".utf8)

    /// Adds the pair with the value JSON-escaped; skips missing and empty values.
    mutating func add(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        if bytes.count > 1 { bytes.append(UInt8(ascii: ",")) }
        bytes.append(contentsOf: "\"\(key)\":\"".utf8)
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                bytes.append(UInt8(ascii: "\\"))
                bytes.append(byte)
            case ..<0x20:
                bytes.append(contentsOf: "\\u00".utf8)
                bytes.append(Header.hex[Int(byte >> 4)])
                bytes.append(Header.hex[Int(byte & 0xf)])
            default:
                bytes.append(byte)
            }
        }
        bytes.append(UInt8(ascii: "\""))
    }

    /// The finished header line.
    var line: [UInt8] { bytes + Array("}\n".utf8) }
}

@discardableResult
private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + offset, bytes.count - offset) }
        if written < 0 {
            if errno == EINTR { continue }
            return false
        }
        offset += written
    }
    return true
}

/// Reads the island's reply, up to the island closing the connection.
/// Returns nothing when there's no reply, or it's too big to be one.
private func readReply(_ fd: Int32) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: maxReply)
    var length = 0
    while length < maxReply {
        let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress! + length, maxReply - length) }
        if count == 0 { return Array(buffer[..<length]) }
        if count < 0 {
            if errno == EINTR { continue }
            return []
        }
        length += count
    }
    return []
}

private func connectToIsland(at path: String) -> Int32? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else { return nil }
    withUnsafeMutablePointer(to: &address.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
    }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return nil }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if connected != 0 { // Island not running
        close(fd)
        return nil
    }
    return fd
}

private func run() {
    // Never hold the agent up, and never die of a closed socket
    signal(SIGALRM) { _ in _exit(0) }
    signal(SIGPIPE, SIG_IGN)
    alarm(3)

    let arguments = CommandLine.arguments
    guard let payload = readStdin(), arguments.count >= 2, !payload.isEmpty else { return }
    guard let fd = connectToIsland(at: arguments[1]) else { return }
    defer { close(fd) }

    var now = timespec()
    clock_gettime(CLOCK_REALTIME, &now)
    let micros = String(now.tv_nsec / 1000)
    let time = "\(now.tv_sec)." + String(repeating: "0", count: 6 - micros.count) + micros
    let waitsForReply = arguments.count > 3 && arguments[3] == "wait"

    var cwd = [CChar](repeating: 0, count: Int(PATH_MAX))
    var header = Header()
    header.add("time", time)
    header.add("agent", arguments.count > 2 ? arguments[2] : nil)
    if waitsForReply { header.add("can_reply", "1") }
    header.add("agent_pid", String(agentProcess()))
    header.add("tty", controllingTTY())
    header.add("app_bundle_id", environment("__CFBundleIdentifier"))
    header.add("term_program", environment("TERM_PROGRAM"))
    header.add("iterm_session_id", environment("ITERM_SESSION_ID"))
    // Agents run hooks in the session's directory; not every agent puts it in the event
    header.add("cwd", getcwd(&cwd, cwd.count) != nil ? String(cString: cwd) : nil)

    guard writeAll(fd, header.line), writeAll(fd, payload) else { return }
    // The island reads up to the end of the event
    shutdown(fd, SHUT_WR)

    if waitsForReply {
        alarm(waitSeconds)
        let reply = readReply(fd)
        if !reply.isEmpty { writeAll(STDOUT_FILENO, reply) }
    }
}

run()
exit(0)
