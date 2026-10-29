import Foundation

/// Explicit reason why the island is currently visible
/// The island is HIDDEN unless one of these reasons is active
enum IslandVisibilityReason: Equatable {
    case clipboard          // Clipboard changed, showing preview
    case clipboardHistory   // Clipboard history picker
    case dragDetected       // Global drag detected (Boring Notch style)
    case userExpanded       // User explicitly clicked to expand
    case hotkey             // User triggered via hotkey
    case plugin             // A plugin asked to show its tab ({"type":"open"})
    case heldByPlugin       // A plugin opened its tab until it says it's done ({"type":"open","hold":true}), e.g. an agent's question
    case none               // Hidden state
}
