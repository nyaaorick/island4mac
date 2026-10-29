import Foundation

/// What a plugin leaves the island to do while it isn't running (protocol 3): content to switch to at given
/// times, and when to start it again.
///
///     {"type":"timeline","entries":[{"at":1767225600,"show":[{"type":"compact","symbol":"fork.knife","text":"Lunch"}]}],
///      "wake":1767229200}
///
/// An entry shows only what a plugin's tab or compact content can (compact, list, buttons, input, status, clear);
/// popups and opening the island need the plugin running, so it asks to be woken for those
struct PluginSchedule: Equatable {
    struct Entry: Equatable {
        let at: Date
        let messages: [PluginMessage]
    }

    /// Sorted by time
    private(set) var entries: [Entry]
    private(set) var wake: Date?

    static let maxEntries = 50
    static let maxMessagesPerEntry = 10

    init(entries: [Entry], wake: Date?) {
        self.entries = Array(entries.sorted { $0.at < $1.at }.prefix(Self.maxEntries))
        self.wake = wake
    }

    static func decode(_ line: Data) throws -> PluginSchedule {
        let body = try JSONDecoder().decode(Body.self, from: line)
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw DecodeError.notAnObject }
        let rawEntries = (object["entries"] as? [[String: Any]]) ?? []
        var entries: [Entry] = []
        for (index, raw) in rawEntries.enumerated() where index < body.entries.count {
            let messages = ((raw["show"] as? [[String: Any]]) ?? []).prefix(maxMessagesPerEntry).compactMap { message -> PluginMessage? in
                guard let data = try? JSONSerialization.data(withJSONObject: message),
                      let decoded = try? PluginMessage.decode(data), decoded.canBeScheduled else { return nil }
                return decoded
            }
            entries.append(Entry(at: Date(timeIntervalSince1970: body.entries[index].at), messages: messages))
        }
        return PluginSchedule(entries: entries, wake: body.wake.map { Date(timeIntervalSince1970: $0) })
    }

    enum DecodeError: Error { case notAnObject }

    private struct Body: Decodable {
        struct EntryTime: Decodable { let at: Double }
        let entries: [EntryTime]
        let wake: Double?
    }

    /// The soonest time something is due
    var nextDate: Date? {
        [entries.first?.at, wake].compactMap { $0 }.min()
    }

    /// Takes out what is due at `now`: the messages to show, in order, and whether the plugin is to be woken
    mutating func takeDue(at now: Date) -> (messages: [PluginMessage], wake: Bool) {
        let due = entries.prefix { $0.at <= now }
        entries.removeFirst(due.count)
        let wakes = wake.map { $0 <= now } ?? false
        if wakes { wake = nil }
        return (due.flatMap(\.messages), wakes)
    }

    var isEmpty: Bool { entries.isEmpty && wake == nil }

    /// Wake no sooner than `date`
    mutating func postponeWake(to date: Date) {
        wake = max(wake ?? date, date)
    }
}

extension PluginMessage {
    /// Whether it can be shown later, from a schedule, without the plugin running
    var canBeScheduled: Bool {
        switch self {
        case .compact, .list, .cards, .media, .lyrics, .buttons, .input, .clear, .status: return true
        case .popup, .open, .close, .timeline, .done, .sudo: return false
        }
    }
}
