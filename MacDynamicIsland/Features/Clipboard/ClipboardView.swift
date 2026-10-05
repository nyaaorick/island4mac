import SwiftUI

// MARK: - ClipboardView (The Island functional zone)
struct ClipboardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: ClipboardStore
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                Button(action: { store.clearAll() }) {
                    Image(systemName: "trash").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.4))
                .padding(14)
                Spacer()
            }
            .frame(width: 44)
            
            // THE CARDS REEL
            if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 32)).foregroundColor(.gray.opacity(0.3))
                    Text("Clipboard is Empty").font(.system(size: 14)).foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(store.items) { item in
                            ClipboardCardView(item: item) {
                                store.pasteItem(item, into: IslandController.shared.previousApp)
                                // This island, which may not be the main one
                                appState.deactivateIsland()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Color.clear)
    }
}
