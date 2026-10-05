import Foundation

/// One of a row's secondary actions (protocol 4): shown on hover and in its context menu. A tap sends its id
/// back as an action, like tapping a row
struct PluginRowAction: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    var symbol: String?

    /// A row has at most this many
    static let maxCount = 4

    var trimmed: PluginRowAction {
        PluginRowAction(id: id, title: PluginMessage.cut(title), symbol: symbol)
    }
}

/// Where a plugin's compact content goes beside the notch (protocol 4, plugin.json "priority")
enum PluginPriority: String, Decodable {
    /// Ahead of popups and now playing: something you should see while music plays (an agent at work)
    case high
    /// After now playing (the default)
    case normal
}
