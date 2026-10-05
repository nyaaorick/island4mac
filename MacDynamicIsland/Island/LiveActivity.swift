import Foundation

/// What the collapsed island shows beside the notch. IslandWindow picks it when it sizes the panel and stores
/// it in AppState; CompactIslandRegion only draws it, so the wings and what fills them never disagree
enum LiveActivity: Equatable {
    case none
    /// A high-priority plugin's compact content (plugin.json "priority": "high"): an agent at work
    case priorityPlugin
    /// A plugin's popup, for its few seconds
    case pluginPopup
    /// Now playing: while it plays, or paused while the pointer rests on the notch
    case music
    /// A plugin's countdown or status
    case pluginCompact

    /// A high-priority plugin (Agents) first, then a plugin's popup, then music, then a plugin's compact content
    static func pick(priorityPlugin: Bool, pluginPopup: Bool, music: Bool, pluginCompact: Bool) -> LiveActivity {
        if priorityPlugin { return .priorityPlugin }
        if pluginPopup { return .pluginPopup }
        if music { return .music }
        if pluginCompact { return .pluginCompact }
        return .none
    }
}
