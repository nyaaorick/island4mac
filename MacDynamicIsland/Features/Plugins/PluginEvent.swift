import Foundation

/// One line the app writes to a plugin's stdin
enum PluginEvent: Equatable {
    /// A row or button with this id was tapped
    case action(String)
    /// Whether the plugin's tab is open, so it can update often only while it shows. Also sent right after it starts
    case visible(Bool)
    /// Return was pressed in its text field (PluginInput)
    case submit(id: String, text: String)
    /// The values of its preferences (PluginManifest.preferences), by key: sent right after it starts, before
    /// `visible`, and again when you change one
    case preferences([String: PluginPreferenceValue])
    /// Protocol 3, to a plugin that runs on demand: why it was started (launch, visible, action, timeline,
    /// preferences). Sent after its preferences, visibility and the event that woke it
    case wake(reason: String)

    var line: Data {
        let object: [String: Any] = switch self {
        case .action(let id): ["type": "action", "id": id]
        case .visible(let tab): ["type": "visible", "tab": tab]
        case .submit(let id, let text): ["type": "submit", "id": id, "text": text]
        case .preferences(let values): ["type": "preferences", "values": values.mapValues(\.object)]
        case .wake(let reason): ["type": "wake", "reason": reason]
        }
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
