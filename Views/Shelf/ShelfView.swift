import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel = ShelfStateViewModel.shared
    
    private var isDragging: Bool {
        appState.isDraggingOver || viewModel.isDraggingOver
    }
    
    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 12)
    ]
    
    var body: some View {
        ZStack {
            ZStack {
                // Solid black like the island around it; a material here would show the wallpaper through the panel
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)

                // Content Layer
                VStack(spacing: 0) {
                    if viewModel.isEmpty {
                        emptyStateView
                    } else {
                        VStack(spacing: 0) {
                            shelfHeaderView
                            itemsGridView
                        }
                    }
                }
                
                // PRO-LEVEL INTEGRATED DASHED BORDER
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.white.opacity(0.18),
                        style: StrokeStyle(
                            lineWidth: isDragging ? 4 : 1,
                            lineCap: .round,
                            dash: isDragging ? [15, 8] : []
                        )
                    )
                    .shadow(color: isDragging ? Color.accentColor.opacity(0.5) : Color.clear, radius: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDragging)
            }
            .padding(2) 
            
            // 🌟 AMBIENT GLOW ON DRAG
            if isDragging {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .blur(radius: 30)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .url, .item, .data], isTargeted: Binding(
            get: { isDragging },
            set: { dragging in
                viewModel.isDraggingOver = dragging
                appState.isDraggingOver = dragging
            }
        )) { providers in
            Task {
                await viewModel.handleDrop(providers: providers)
            }
            return true
        }
        .padding(6)
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isDragging ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 72, height: 72)
                    .blur(radius: isDragging ? 8 : 0)
                
                Circle()
                    .strokeBorder(isDragging ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                
                Image(systemName: isDragging ? "arrow.down.doc.fill" : "plus.square.dashed")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(isDragging ? .accentColor : .white.opacity(0.4))
                    .symbolEffect(.bounce, value: isDragging)
            }
            .scaleEffect(isDragging ? 1.15 : 1.0)
            
            VStack(spacing: 6) {
                Text(isDragging ? "Drop to Stash" : "Shelf is Empty")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(isDragging ? .accentColor : .white.opacity(0.9))
                
                Text(isDragging ? "Release your files here" : "Drag files, images, or links")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDragging)
    }
    
    private var shelfHeaderView: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 12, weight: .semibold))
            
            Text("Files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            
            Spacer()
            
            Text("\(viewModel.items.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            
            Text("items")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            
            if !viewModel.items.isEmpty {
                Button("Clear") {
                    viewModel.clearAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red.opacity(0.85))
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .bottom
        )
    }

    private var itemsGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(viewModel.items) { item in
                    ShelfItemCell(item: item)
                        .onDrag {
                            // ✅ Drag out as a real file URL for Finder/Desktop
                            guard let resolvedURL = viewModel.resolveFileURL(for: item) else {
                                print("❌ [ShelfView] Failed to resolve URL for drag: \(item.displayName)")
                                return NSItemProvider()
                            }

                            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                                print("❌ [ShelfView] File missing at path: \(resolvedURL.path)")
                                return NSItemProvider()
                            }

                            if let provider = NSItemProvider(contentsOf: resolvedURL) {
                                provider.suggestedName = item.displayName
                                return provider
                            }

                            // Fallback: URL object provider
                            let provider = NSItemProvider(object: resolvedURL as NSURL)
                            provider.suggestedName = item.displayName
                            return provider
                        }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Shelf Item Cell

struct ShelfItemCell: View {
    let item: ShelfItem
    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Shadow
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .blur(radius: isHovering ? 6 : 4)
                    .offset(y: isHovering ? 4 : 2)
                
                // Icon
                Group {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(
                                Image(systemName: item.iconName)
                                    .font(.system(size: 26))
                                    .foregroundColor(.white.opacity(0.8))
                            )
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
            }
            .scaleEffect(isHovering ? 1.08 : 1.0)
            
            Text(item.displayName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isHovering ? .white : .white.opacity(0.7))
                .lineLimit(1)
                .frame(width: 80)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
        .task {
            guard let resolvedURL = ShelfStateViewModel.shared.resolveFileURL(for: item) else { return }

            // ✅ For images, show a real thumbnail (preview) instead of only a JPG icon
            if item.isImage {
                let didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()

                ThumbnailGenerationService.shared.generateThumbnail(for: resolvedURL) { image in
                    if didStartAccessing {
                        resolvedURL.stopAccessingSecurityScopedResource()
                    }

                    if let image {
                        withAnimation(.easeIn(duration: 0.12)) {
                            self.thumbnail = image
                        }
                    } else {
                        // Fallback to the system icon
                        self.thumbnail = NSWorkspace.shared.icon(forFile: resolvedURL.path)
                    }
                }
            } else {
                // Non-image files keep using the system icon
                self.thumbnail = NSWorkspace.shared.icon(forFile: resolvedURL.path)
            }
        }
    }
}
