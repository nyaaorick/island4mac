import Foundation

/// One line a plugin writes to its stdout, telling the island what to show. The island draws it with its own
/// templates; the plugin never draws. Each kind replaces what the plugin showed of that kind before.
///
///     {"type":"compact","symbol":"timer","text":"04:59","progress":0.98}
///     {"type":"list","rows":[{"id":"r1","title":"5 min","subtitle":"Pomodoro","symbol":"play"}]}
///     {"type":"buttons","buttons":[{"id":"stop","title":"Stop"}]}
///     {"type":"popup","symbol":"bell","text":"Time's up","seconds":3}
///     {"type":"clear","target":"compact"}
enum PluginMessage: Equatable {
    case compact(PluginCompact)
    case list([PluginRow])
    case buttons([PluginButton])
    case popup(PluginPopup)
    case clear(PluginClearTarget)

    /// Rows and buttons past this are dropped
    static let maxItems = 50
    /// Text past this is cut
    static let maxTextLength = 200

    enum DecodeError: Error, Equatable {
        case unknownType(String)
    }

    static func decode(_ line: Data) throws -> PluginMessage {
        let envelope = try JSONDecoder().decode(Envelope.self, from: line)
        let decoder = JSONDecoder()
        switch envelope.type {
        case "compact": return .compact(try decoder.decode(PluginCompact.self, from: line).trimmed)
        case "list": return .list(Array(try decoder.decode(ListBody.self, from: line).rows.prefix(maxItems)).map(\.trimmed))
        case "buttons": return .buttons(Array(try decoder.decode(ButtonsBody.self, from: line).buttons.prefix(maxItems)).map(\.trimmed))
        case "popup": return .popup(try decoder.decode(PluginPopup.self, from: line).trimmed)
        case "clear": return .clear(try decoder.decode(ClearBody.self, from: line).target)
        default: throw DecodeError.unknownType(envelope.type)
        }
    }

    private struct Envelope: Decodable { let type: String }
    private struct ListBody: Decodable { let rows: [PluginRow] }
    private struct ButtonsBody: Decodable { let buttons: [PluginButton] }
    private struct ClearBody: Decodable { let target: PluginClearTarget }

    static func cut(_ text: String) -> String { String(text.prefix(maxTextLength)) }
    static func cut(_ text: String?) -> String? { text.map(cut) }
}

/// Shown beside the notch while the island is collapsed
struct PluginCompact: Decodable, Equatable {
    var symbol: String?
    var text: String?
    /// 0...1, drawn as a ring
    var progress: Double?

    var trimmed: PluginCompact {
        PluginCompact(symbol: symbol, text: PluginMessage.cut(text), progress: progress.map { min(max($0, 0), 1) })
    }
}

/// A row in the plugin's tab; tapping one with an id sends it back as an action
struct PluginRow: Decodable, Equatable, Identifiable {
    var id: String?
    var title: String
    var subtitle: String?
    var symbol: String?

    var trimmed: PluginRow {
        PluginRow(id: id, title: PluginMessage.cut(title), subtitle: PluginMessage.cut(subtitle), symbol: symbol)
    }
}

/// A button under the rows in the plugin's tab
struct PluginButton: Decodable, Equatable, Identifiable {
    var id: String
    var title: String
    var symbol: String?

    var trimmed: PluginButton {
        PluginButton(id: id, title: PluginMessage.cut(title), symbol: symbol)
    }
}

/// Shown beside the notch for a few seconds, ahead of now playing
struct PluginPopup: Decodable, Equatable {
    var symbol: String?
    var text: String
    var seconds: Double?

    /// How long it shows: 3 seconds unless it says otherwise, never longer than 10
    var duration: TimeInterval { min(max(seconds ?? 3, 1), 10) }

    var trimmed: PluginPopup {
        PluginPopup(symbol: symbol, text: PluginMessage.cut(text), seconds: seconds)
    }
}

enum PluginClearTarget: String, Decodable {
    case compact, list, buttons, all
}
