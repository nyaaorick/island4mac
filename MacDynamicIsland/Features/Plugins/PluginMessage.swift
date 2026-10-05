import Foundation

/// One line a plugin writes to its stdout, telling the island what to show. The island draws it with its own
/// templates and look; the plugin never draws, and can't set colors, fonts or images. Each kind replaces what
/// the plugin showed of that kind before.
///
///     {"type":"compact","symbol":"timer","text":"04:59","progress":0.98}
///     {"type":"compact","symbol":"timer","until":1767225600,"total":300}     counted down by the island
///     {"type":"list","rows":[{"id":"r1","title":"5 min","subtitle":"Pomodoro","symbol":"play"}]}
///     {"type":"buttons","buttons":[{"id":"stop","title":"Stop","confirm":"Stop the timer?"}]}
///     {"type":"input","id":"minutes","placeholder":"Minutes","text":""}
///     {"type":"popup","symbol":"bell","text":"Time's up","seconds":3}
///     {"type":"open"}                                                        open the island on this plugin's tab
///     {"type":"clear","target":"compact"}
enum PluginMessage: Equatable {
    case compact(PluginCompact)
    case list([PluginRow])
    case buttons([PluginButton])
    case input(PluginInput)
    case popup(PluginPopup)
    case open
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
        case "input": return .input(try decoder.decode(PluginInput.self, from: line).trimmed)
        case "popup": return .popup(try decoder.decode(PluginPopup.self, from: line).trimmed)
        case "open": return .open
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
    /// A countdown the island runs itself, to this time (seconds since 1970): shown instead of `text`
    var until: Double?
    /// The countdown's whole length in seconds; with it, the ring shows the time left
    var total: Double?

    var trimmed: PluginCompact {
        PluginCompact(symbol: symbol, text: PluginMessage.cut(text), progress: progress.map { min(max($0, 0), 1) },
                      until: until, total: total.flatMap { $0 > 0 ? $0 : nil })
    }
}

/// The one text field a plugin's tab can have, above its buttons; Return sends it as PluginEvent.submit
struct PluginInput: Decodable, Equatable {
    var id: String
    var placeholder: String?
    /// Its starting text
    var text: String?

    static let maxLength = 1000

    var trimmed: PluginInput {
        PluginInput(id: id, placeholder: PluginMessage.cut(placeholder), text: text.map { String($0.prefix(Self.maxLength)) })
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
    /// Asked first, in the tab, before the tap goes to the plugin
    var confirm: String?

    var trimmed: PluginButton {
        PluginButton(id: id, title: PluginMessage.cut(title), symbol: symbol, confirm: PluginMessage.cut(confirm))
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
    case compact, list, buttons, input, all
}
