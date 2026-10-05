import SwiftUI

/// The Files tab: a card per item on the shelf, drawn from the plugin protocol (ShelfStore+Island). Dropping on it
/// is the island's (IslandDropZone); drag a card out to take the file with you
struct ShelfView: View {
    @ObservedObject var store = ShelfStore.shared

    var body: some View {
        PluginContentView(content: store.islandContent, emptySymbol: "tray", emptyTitle: L("tab.files")) { store.handle($0) }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.items.map(\.id))
    }
}
