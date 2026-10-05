import Foundation

/// One line the app writes to a plugin's stdin
enum PluginEvent: Equatable {
    /// A row or button with this id was tapped
    case action(String)
    /// Whether the plugin's tab is open, so it can update often only while it shows
    case visible(Bool)

    var line: Data {
        let object: [String: Any] = switch self {
        case .action(let id): ["type": "action", "id": id]
        case .visible(let tab): ["type": "visible", "tab": tab]
        }
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
