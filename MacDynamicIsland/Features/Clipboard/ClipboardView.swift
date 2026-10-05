import SwiftUI

/// The Clipboard tab: a card per copied item, drawn from the plugin protocol (ClipboardStore+Island). Tapping one
/// pastes it into the app you were using and closes the island
struct ClipboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: ClipboardStore

    var body: some View {
        PluginContentView(content: store.islandContent, emptySymbol: "doc.on.clipboard", emptyTitle: L("tab.clipboard")) { event in
            if store.handle(event, pastingInto: IslandController.shared.previousApp) {
                // This island, which may not be the main one
                appState.deactivateIsland()
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
