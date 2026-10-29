import SwiftUI

// How the island draws a state (PluginItemState): the one place its colors live, so every plugin's rows, cards
// and compact content say "working", "needs you", "done" and "failed" the same way

extension PluginItemState {
    var color: Color {
        switch self {
        case .working: return .orange
        case .attention: return .yellow
        case .done: return .green
        case .failed: return .red
        }
    }

    /// The symbol drawn when the plugin gave none
    var fallbackSymbol: String {
        switch self {
        case .working: return "ellipsis.circle"
        case .attention: return "exclamationmark.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
