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
    /// Protocol 5, to a plugin whose plugin.json "accepts" files: what you dropped on its tab. Files and folders
    /// as paths; text the island saved as a file in the plugin's data folder (Drops/), also a path; links as URLs
    case drop(paths: [String], urls: [String])
    /// Protocol 5, to a plugin that sent `media`: a tap on the island's player ("playPause", "next", "previous")
    case control(String)
    /// Protocol 5: the progress bar was dragged to this many seconds into the track
    case seek(Double)

    var line: Data {
        let object: [String: Any] = switch self {
        case .action(let id): ["type": "action", "id": id]
        case .visible(let tab): ["type": "visible", "tab": tab]
        case .submit(let id, let text): ["type": "submit", "id": id, "text": text]
        case .preferences(let values): ["type": "preferences", "values": values.mapValues(\.object)]
        case .wake(let reason): ["type": "wake", "reason": reason]
        case .drop(let paths, let urls): ["type": "drop", "paths": paths, "urls": urls]
        case .control(let command): ["type": "control", "command": command]
        case .seek(let position): ["type": "seek", "position": position]
        }
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
