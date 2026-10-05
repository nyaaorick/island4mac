import Foundation

/// Reads a session's title from its Claude Code transcript (the JSONL file at the hook's `transcript_path`).
/// Claude Code keeps re-appending small title records as the session goes on, so the end of the file is enough.
nonisolated enum ClaudeTranscript {
    private static let tailSize: UInt64 = 512 * 1024
    private static let customTitleMarker = Data(#""type":"custom-title""#.utf8)
    private static let aiTitleMarker = Data(#""type":"ai-title""#.utf8)

    /// The title set with /rename or by the Claude app, else the one Claude generated
    static func title(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > tailSize ? size - tailSize : 0)
        guard let tail = try? handle.readToEnd() else { return nil }

        var aiTitle: String?
        // Newest records last; the first chunk may start mid-line and simply won't parse
        for line in tail.split(separator: UInt8(ascii: "\n")).reversed() {
            let isCustom = line.range(of: customTitleMarker) != nil
            guard isCustom || (aiTitle == nil && line.range(of: aiTitleMarker) != nil),
                  let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            if isCustom, let title = cleaned(record["customTitle"]) {
                return title
            }
            aiTitle = aiTitle ?? cleaned(record["aiTitle"])
        }
        return aiTitle
    }

    private static func cleaned(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
