import SwiftUI

/// Makes a tab that takes drops (IslandDropTarget) a place to drop: while something is dragged over it, or over
/// the island near the notch, the tab shows a dashed accent outline and a "Drop to add" capsule over what it
/// shows. The same for every such tab, built-in or plugin, so a plugin never draws its own
struct IslandDropZone: ViewModifier {
    let tab: IslandTab
    @EnvironmentObject private var appState: AppState
    @State private var isTargeted = false

    private var isShowing: Bool { isTargeted || appState.isDraggingOver }

    func body(content: Content) -> some View {
        if IslandDropTarget.accepts(tab) {
            content
                .overlay {
                    if isShowing {
                        highlight
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isShowing)
                .contentShape(Rectangle())
                .onDrop(of: IslandDrop.types, isTargeted: $isTargeted) { providers in
                    let tab = tab
                    Task { @MainActor in
                        let drop = await IslandDrop.read(providers, savingTextIn: IslandDropTarget.textFolder(for: tab))
                        IslandDropTarget.deliver(drop, to: tab)
                        appState.isDraggingOver = false
                    }
                    return true
                }
        } else {
            content
        }
    }

    private var highlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 6]))
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .symbolEffect(.bounce, value: isShowing)
                Text(L("island.drop"))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .islandTile(cornerRadius: 999, tint: .accentColor)
        }
        .padding(6)
    }
}

extension View {
    /// Lets you drop files, text and links on this tab if it takes them (IslandDropTarget)
    func islandDropZone(for tab: IslandTab) -> some View {
        modifier(IslandDropZone(tab: tab))
    }
}
