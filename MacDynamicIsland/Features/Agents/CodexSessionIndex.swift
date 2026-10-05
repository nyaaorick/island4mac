import Foundation

/// Reads a Codex session's name from session_index.jsonl in the Codex home (~/.codex), where Codex appends
/// `{"id": …, "thread_name": …}` each time it names or renames a thread. Newest records are last.
nonisolated enum CodexSessionIndex {
    private static let tailSize: UInt64 = 512 * 1024

    /// The index next to the sessions folder the transcript is in, else the one in ~/.codex
    static func indexURL(forTranscript transcriptPath: String?) -> URL {
        if let transcriptPath, let range = transcriptPath.range(of: "/sessions/", options: .backwards) {
            return URL(fileURLWithPath: String(transcriptPath[..<range.lowerBound])).appendingPathComponent("session_index.jsonl")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/session_index.jsonl")
    }

    static func title(forSession sessionID: String, in indexURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: indexURL) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > tailSize ? size - tailSize : 0)
        guard let tail = try? handle.readToEnd() else { return nil }

        let marker = Data(sessionID.utf8)
        // The first chunk may start mid-line and simply won't parse
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: marker) != nil {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  record["id"] as? String == sessionID,
                  let name = (record["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            return name
        }
        return nil
    }
}
