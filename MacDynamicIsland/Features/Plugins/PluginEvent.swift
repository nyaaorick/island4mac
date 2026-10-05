import Foundation

/// One line the app writes to a plugin's stdin
enum PluginEvent: Equatable {
    /// A row or button with this id was tapped
    case action(String)
    /// Whether the plugin's tab is open, so it can update often only while it shows. Also sent right after it starts
    case visible(Bool)
    /// Return was pressed in its text field (PluginInput)
    case submit(id: String, text: String)

    var line: Data {
        let object: [String: Any] = switch self {
        case .action(let id): ["type": "action", "id": id]
        case .visible(let tab): ["type": "visible", "tab": tab]
        case .submit(let id, let text): ["type": "submit", "id": id, "text": text]
        }
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
