import Foundation

/// Explicit reason why overlay is currently visible
/// Overlay is HIDDEN unless one of these reasons is active
enum OverlayVisibilityReason: Equatable {
    case clipboard          // Clipboard changed, showing preview
    case clipboardHistory   // Clipboard history picker
    case dragHover          // File being dragged over overlay
    case dragDetected       // Global drag detected (Boring Notch style)
    case dropComplete       // Files dropped, showing actions
    case nowPlaying         // Media playing, showing controls
    case userExpanded       // User explicitly clicked to expand
    case hotkey             // User triggered via hotkey
    case agentQuestion      // An agent asked you a question you can answer in the island
    case none               // Hidden state
    
    var shouldAutoHide: Bool {
        switch self {
        case .clipboard, .dropComplete:
            return true
        case .clipboardHistory, .dragHover, .dragDetected, .nowPlaying, .userExpanded, .hotkey, .agentQuestion:
            return false
        case .none:
            return false
        }
    }
    
    var autoHideDelay: TimeInterval {
        switch self {
        case .clipboard:
            return 1.5
        case .dropComplete:
            return 4.0
        case .nowPlaying:
            return 2.0  // Show for 2s on track change
        default:
            return 0
        }
    }
}
