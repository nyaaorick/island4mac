import Foundation

/// Four-state interaction model for notch overlay
/// - idle: visible but non-interactive (compact)
/// - armed: hover detected, visual feedback only (still compact)
/// - active: expanded and fully functional (accepts input)
/// - pinned: stays active until explicit user close
enum IslandInteractionState: Equatable {
    case idle
    case armed
    case active
    case pinned
    
    /// Whether the overlay should be expanded (showing full UI)
    var isExpanded: Bool {
        switch self {
        case .idle, .armed:
            return false
        case .active, .pinned:
            return true
        }
    }
}
