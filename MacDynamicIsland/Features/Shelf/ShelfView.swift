import SwiftUI
import UniformTypeIdentifiers

/// The Files tab: a card per item on the shelf, drawn from the plugin protocol (ShelfStore+Island). Drop files,
/// images or links anywhere on it to add them; drag a card out to take the file with you
struct ShelfView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store = ShelfStore.shared

    var body: some View {
        PluginContentView(content: store.islandContent, emptySymbol: "tray", emptyTitle: L("tab.files")) { store.handle($0) }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .url, .item, .data], isTargeted: Binding(
                get: { appState.isDraggingOver || store.isDraggingOver },
                set: { dragging in
                    store.isDraggingOver = dragging
                    appState.isDraggingOver = dragging
                }
            )) { providers in
                Task { await store.handleDrop(providers: providers) }
                return true
            }
    }
}
