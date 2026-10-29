import Foundation

/// One line a plugin writes to its stdout, telling the island what to show. The island draws it with its own
/// templates and look; the plugin never draws, and can't set colors, fonts or images. Each kind replaces what
/// the plugin showed of that kind before.
///
///     {"type":"compact","symbol":"timer","text":"04:59","progress":0.98}
///     {"type":"compact","symbol":"timer","until":1767225600,"total":300}     counted down by the island
///     {"type":"list","rows":[{"id":"r1","title":"5 min","subtitle":"Pomodoro","symbol":"play"}]}
///     {"type":"list","rows":[{"title":"Tests","subtitle":"Running","state":"working","detail":"1:23"}]}   protocol 6: PluginItemState
///     {"type":"list","rows":[{"title":"Running","kind":"section"},{"id":"awake","title":"Keep awake","toggle":true},
///                            {"title":"Upgrading","progress":0.4}]}                                    protocol 7
///     {"type":"cards","cards":[{"id":"c1","title":"Safari","preview":{"text":"let x = 1"}}]}   protocol 5: PluginCard
///     {"type":"media","title":"Song","artist":"Artist","playing":true,"elapsed":42,"duration":215}   protocol 5: PluginMedia
///     {"type":"lyrics","lines":[{"time":12.3,"text":"…"}]}                  protocol 5: the track's lyrics
///     {"type":"buttons","buttons":[{"id":"stop","title":"Stop","confirm":"Stop the timer?"}]}
///     {"type":"input","id":"minutes","placeholder":"Minutes","text":""}
///     {"type":"popup","symbol":"bell","text":"Time's up","seconds":3}
///     {"type":"open"}                                                        open the island on this plugin's tab
///     {"type":"open","hold":true}                                            and keep it open until "close" (protocol 4)
///     {"type":"close"}                                                       close what "hold" kept open (protocol 4)
///     {"type":"clear","target":"compact"}
///     {"type":"status","state":"loading","text":"Updating"}                 one standard row; "idle" removes it
///     {"type":"timeline","entries":[…],"wake":1767229200}                    protocol 3: see PluginSchedule
///     {"type":"done"}                                                        protocol 3: nothing more to do, stop me
///     {"type":"sudo","id":"flush","command":["dscacheutil","-flushcache"]}  protocol 8: run this as an administrator
///                                                                            (PluginSudoRequest); the result is PluginEvent.sudo
enum PluginMessage: Equatable {
    case compact(PluginCompact)
    case list([PluginRow])
    /// Protocol 5: cards in a row you scroll sideways, above the rows
    case cards([PluginCard])
    /// Protocol 5: what's playing, drawn with the island's own player
    case media(PluginMedia)
    /// Protocol 5: the playing track's lyrics
    case lyrics([PluginLyricLine])
    case buttons([PluginButton])
    case input(PluginInput)
    case popup(PluginPopup)
    /// With `hold`, the island stays open (no auto-close) until the plugin says `close`, or you close it
    case open(hold: Bool)
    case close
    case clear(PluginClearTarget)
    /// Loading or failed, drawn as one standard row; nil: neither
    case status(PluginNotice?)
    case timeline(PluginSchedule)
    case done
    /// Protocol 8: run a command as an administrator, if the plugin declares `"needs":["admin"]` and the user allows it
    case sudo(PluginSudoRequest)

    /// Rows and buttons past this are dropped
    static let maxItems = 50
    /// Text past this is cut
    static let maxTextLength = 200
    /// A row's subtitle may run longer, over up to 3 lines (a command an agent wants to run)
    static let maxSubtitleLength = 600

    enum DecodeError: Error, Equatable {
        case unknownType(String)
    }

    static func decode(_ line: Data) throws -> PluginMessage {
        let envelope = try JSONDecoder().decode(Envelope.self, from: line)
        let decoder = JSONDecoder()
        switch envelope.type {
        case "compact": return .compact(try decoder.decode(PluginCompact.self, from: line).trimmed)
        case "list": return .list(Array(try decoder.decode(ListBody.self, from: line).rows.prefix(maxItems)).map(\.trimmed))
        case "cards": return .cards(Array(try decoder.decode(CardsBody.self, from: line).cards.prefix(maxItems)).map(\.trimmed))
        case "media":
            var media = try decoder.decode(PluginMedia.self, from: line).trimmed
            // A position needs its time: now, if the plugin didn't say
            if media.at == nil { media.at = Date().timeIntervalSince1970 }
            return .media(media)
        case "lyrics": return .lyrics(Array(try decoder.decode(LyricsBody.self, from: line).lines.prefix(PluginLyricLine.maxCount)).map(\.trimmed))
        case "buttons": return .buttons(Array(try decoder.decode(ButtonsBody.self, from: line).buttons.prefix(maxItems)).map(\.trimmed))
        case "input": return .input(try decoder.decode(PluginInput.self, from: line).trimmed)
        case "popup": return .popup(try decoder.decode(PluginPopup.self, from: line).trimmed)
        case "open": return .open(hold: (try? decoder.decode(OpenBody.self, from: line).hold) ?? false)
        case "close": return .close
        case "clear": return .clear(try decoder.decode(ClearBody.self, from: line).target)
        case "status":
            let body = try decoder.decode(StatusBody.self, from: line)
            guard let state = PluginNotice.State(rawValue: body.state) else { return .status(nil) }
            return .status(PluginNotice(state: state, text: cut(body.text)))
        case "timeline": return .timeline(try PluginSchedule.decode(line))
        case "done": return .done
        case "sudo": return .sudo(try decoder.decode(PluginSudoRequest.self, from: line).trimmed)
        default: throw DecodeError.unknownType(envelope.type)
        }
    }

    private struct Envelope: Decodable { let type: String }
    private struct ListBody: Decodable { let rows: [PluginRow] }
    private struct CardsBody: Decodable { let cards: [PluginCard] }
    private struct LyricsBody: Decodable { let lines: [PluginLyricLine] }
    private struct ButtonsBody: Decodable { let buttons: [PluginButton] }
    private struct ClearBody: Decodable { let target: PluginClearTarget }
    private struct StatusBody: Decodable { let state: String; let text: String? }
    private struct OpenBody: Decodable { let hold: Bool? }

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
    /// Shown in place of the symbol (protocol 4)
    var image: PluginImage?
    /// What it's up to, drawn as the island's status glyph (protocol 6)
    var state: PluginItemState?

    var trimmed: PluginCompact {
        PluginCompact(symbol: symbol, text: PluginMessage.cut(text), progress: progress.map { min(max($0, 0), 1) },
                      until: until, total: total.flatMap { $0 > 0 ? $0 : nil }, image: image, state: state)
    }
}

/// What a row, a card or the compact content is up to (protocol 6). The island draws it: a turning arc for
/// `working`, a pulsing symbol for `attention`, and the colors every tab uses for done and failed. A plugin says
/// only the state, never a color, so every plugin's "needs you" looks the same
enum PluginItemState: String, Equatable {
    case working, attention, done, failed
}

extension KeyedDecodingContainer {
    /// A state this app doesn't know, from a plugin written for a newer one, reads as none rather than failing
    /// the whole message
    func decodeState(forKey key: Key) throws -> PluginItemState? {
        try decodeIfPresent(String.self, forKey: key).flatMap(PluginItemState.init(rawValue:))
    }
}

extension PluginCompact {
    private enum CodingKeys: String, CodingKey { case symbol, text, progress, until, total, image, state }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(symbol: try container.decodeIfPresent(String.self, forKey: .symbol),
                  text: try container.decodeIfPresent(String.self, forKey: .text),
                  progress: try container.decodeIfPresent(Double.self, forKey: .progress),
                  until: try container.decodeIfPresent(Double.self, forKey: .until),
                  total: try container.decodeIfPresent(Double.self, forKey: .total),
                  image: try container.decodeIfPresent(PluginImage.self, forKey: .image),
                  state: try container.decodeState(forKey: .state))
    }
}

extension PluginRow {
    private enum CodingKeys: String, CodingKey { case id, title, subtitle, symbol, image, actions, state, detail, kind, progress, toggle }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(String.self, forKey: .id),
                  title: try container.decode(String.self, forKey: .title),
                  subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle),
                  symbol: try container.decodeIfPresent(String.self, forKey: .symbol),
                  image: try container.decodeIfPresent(PluginImage.self, forKey: .image),
                  actions: try container.decodeIfPresent([PluginRowAction].self, forKey: .actions),
                  state: try container.decodeState(forKey: .state),
                  detail: try container.decodeIfPresent(String.self, forKey: .detail),
                  kind: try container.decodeIfPresent(String.self, forKey: .kind).flatMap(PluginRowKind.init(rawValue:)) ?? .row,
                  progress: try container.decodeIfPresent(Double.self, forKey: .progress),
                  toggle: try container.decodeIfPresent(Bool.self, forKey: .toggle))
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
    /// Up to 3 lines show
    var subtitle: String?
    var symbol: String?
    /// Shown in place of the symbol (protocol 4)
    var image: PluginImage?
    /// Secondary actions, on hover and in its context menu (protocol 4)
    var actions: [PluginRowAction]?
    /// What it's up to: colors its symbol and the subtitle's first line (protocol 6)
    var state: PluginItemState?
    /// Short text at the row's right edge, such as a time or a count (protocol 6)
    var detail: String?
    /// A section heading over the rows that follow, rather than a row (protocol 7)
    var kind: PluginRowKind = .row
    /// 0...1, drawn as a ring around the symbol (protocol 7)
    var progress: Double?
    /// Drawn as a switch at the row's right edge; a tap on it, or on the row, sends the row's action and the
    /// plugin flips it (protocol 7)
    var toggle: Bool?

    var trimmed: PluginRow {
        PluginRow(id: id, title: PluginMessage.cut(title), subtitle: subtitle.map { String($0.prefix(PluginMessage.maxSubtitleLength)) },
                  symbol: symbol, image: image, actions: actions.map { Array($0.prefix(PluginRowAction.maxCount)).map(\.trimmed) },
                  state: state, detail: PluginMessage.cut(detail), kind: kind, progress: progress.map { min(max($0, 0), 1) }, toggle: toggle)
    }
}

/// What a line in a plugin's list is (protocol 7). A kind this app doesn't know reads as a row
enum PluginRowKind: String, Equatable {
    case row
    /// A heading over the rows after it: a caption, not a pane, and never tapped
    case section
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

/// A plugin's "loading" or "couldn't load" line, drawn the same way for every plugin
struct PluginNotice: Equatable {
    enum State: String {
        case loading, error
    }

    let state: State
    let text: String?
}

enum PluginClearTarget: String, Decodable {
    case compact, list, cards, media, lyrics, buttons, input, all
}

/// A command a plugin asks the island to run as an administrator (protocol 8). The island runs it through sudo with
/// the password the user saved under Settings > Plugins, and answers with PluginEvent.sudo under the same id
struct PluginSudoRequest: Decodable, Equatable {
    var id: String
    /// Program and arguments; the program is a path, or a name sudo finds on its secure path
    var command: [String]
    /// Text for the program's stdin
    var input: String?
    /// Seconds before the island gives up and kills it; 60 unless said, never more than 600
    var timeout: Double?

    var duration: TimeInterval { min(max(timeout ?? 60, 1), 600) }

    var trimmed: PluginSudoRequest {
        PluginSudoRequest(id: PluginMessage.cut(id), command: Array(command.prefix(200)), input: input, timeout: timeout)
    }
}
