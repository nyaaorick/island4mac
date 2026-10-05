import Foundation

/// Explicit reason why overlay is currently visible
/// Overlay is HIDDEN unless one of these reasons is active
enum OverlayVisibilityReason: Equatable {
    case clipboard          // Clipboard changed, showing preview
    case clipboardHistory   // Clipboard history picker
    case dragDetected       // Global drag detected (Boring Notch style)
    case userExpanded       // User explicitly clicked to expand
    case hotkey             // User triggered via hotkey
    case agentPrompt        // An agent asks you something you can answer in the island
    case none               // Hidden state
}
