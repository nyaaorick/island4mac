import SwiftUI

// MARK: - ClipboardHubView (The Island functional zone)
struct ClipboardHubView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var vault: IslandClipVault
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                Button(action: { vault.clearAll() }) {
                    Image(systemName: "trash").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.4))
                .padding(14)
                Spacer()
            }
            .frame(width: 44)
            
            // THE CARDS REEL
            if vault.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 32)).foregroundColor(.gray.opacity(0.3))
                    Text("Clipboard is Empty").font(.system(size: 14)).foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(vault.items) { item in
                            ClipboardCardView(item: item) {
                                vault.pasteItem(item, into: OverlayWindowController.shared.previousApp)
                                // This island, which may not be the main one
                                appState.deactivateOverlay()
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
