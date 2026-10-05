import SwiftUI

/// A capsule button in a plugin's tab (PluginButton), also used by the tab's own states (Restart, Open Settings)
struct PluginButtonView: View {
    let title: String
    let symbol: String?
    /// Larger, for a tab that shows nothing but its buttons (PluginContentView)
    var isProminent = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: isProminent ? 8 : 6) {
            if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.system(size: isProminent ? 13 : 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.vertical, isProminent ? 10 : 6)
        .padding(.horizontal, isProminent ? 18 : 12)
        .islandTile(cornerRadius: 999, highlighted: isHovered)
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
    }
}
