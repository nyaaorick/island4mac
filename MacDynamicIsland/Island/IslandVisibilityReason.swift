import Foundation

/// Explicit reason why the island is currently visible
/// The island is HIDDEN unless one of these reasons is active
enum IslandVisibilityReason: Equatable {
    case clipboard          // Clipboard changed, showing preview
    case clipboardHistory   // Clipboard history picker
    case dragDetected       // Global drag detected (Boring Notch style)
    case userExpanded       // User explicitly clicked to expand
    case hotkey             // User triggered via hotkey
    case agentPrompt        // An agent asks you something you can answer in the island
    case plugin             // A plugin asked to show its tab ({"type":"open"})
    case none               // Hidden state
}
