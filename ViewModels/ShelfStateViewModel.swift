import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

/// Central state manager for the shelf system
/// Robust logic inspired by Boring Notch
@MainActor
class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()
    
    @Published var items: [ShelfItem] = []
    @Published var isDraggingOver: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let persistenceService = ShelfPersistenceService.shared
    private let maxItems = 50
    
    private init() {
        loadItems()
    }
    
    var filteredItems: [ShelfItem] { items } 
    var isEmpty: Bool { items.isEmpty }
    var itemCount: Int { items.count }

    // MARK: - Core Logic (Boring Style)

    func handleDrop(providers: [NSItemProvider]) async {
        print("💥 [ShelfState] handleDrop: providers=\(providers.count)")
        for (idx, provider) in providers.enumerated() {
            print("   • provider[\(idx)] types=\(provider.registeredTypeIdentifiers)")
        }
        
        await MainActor.run {
            self.isDraggingOver = false
            self.isLoading = true
        }
        
        var newItems: [ShelfItem] = []
        
        for provider in providers {
            // Robust extraction
            if let fileURL = await provider.extractFileURL() {
                print("✅ [ShelfState] extracted fileURL: \(fileURL.path)")
                // IMPORTANT: Create bookmark WHILE we have the drop permission
                do {
                    let bookmarkData = try fileURL.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    let item = ShelfItem(url: fileURL, bookmarkData: bookmarkData)
                    newItems.append(item)
                } catch {
                    print("❌ [ShelfState] Bookmark error: \(error)")
                    newItems.append(ShelfItem(url: fileURL))
                }
            } else if let url = await provider.extractURL() {
                print("✅ [ShelfState] extracted url: \(url.absoluteString)")
                newItems.append(ShelfItem(url: url))
            } else if let text = await provider.extractText() {
                print("✅ [ShelfState] extracted text (len=\(text.count))")
                if let tempURL = try? TemporaryFileStorageService.shared.createTemporary(content: text, filename: "Note_\(Int(Date().timeIntervalSince1970)).txt") {
                    newItems.append(ShelfItem(url: tempURL))
                }
            } else {
                print("⚠️ [ShelfState] provider produced no extractable content")
            }
        }
        
        print("📦 [ShelfState] newItems=\(newItems.count)")
        
        await MainActor.run {
            for item in newItems {
                if !self.items.contains(where: { $0.url == item.url }) {
                    self.items.insert(item, at: 0)
                }
            }
            if self.items.count > maxItems {
                self.items = Array(self.items.prefix(maxItems))
            }
            self.isLoading = false
            self.saveItems()
            print("📊 [ShelfState] items now=\(self.items.count)")
        }
    }
    
    func removeItems(_ itemIDs: [UUID]) {
        items.removeAll { itemIDs.contains($0.id) }
        saveItems()
    }
    
    func removeItem(_ itemID: UUID) {
        removeItems([itemID])
    }
    
    func clearAll() {
        items.removeAll()
        saveItems()
    }

    // MARK: - Persistence
    
    func loadItems() {
        Task {
            do {
                let loaded = try await persistenceService.loadItems()
                await MainActor.run {
                    self.items = loaded
                }
            } catch {
                print("❌ [ShelfState] Load failed: \(error)")
            }
        }
    }
    
    func saveItems() {
        let currentItems = items
        Task {
            try? await persistenceService.saveItems(currentItems)
        }
    }
    
    // Helper to resolve URL (Important for Drags and Reveals)
    func resolveFileURL(for item: ShelfItem) -> URL? {
        if let data = item.bookmarkData {
            var isStale = false
            let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if resolved != nil { return resolved }
        }
        return item.url
    }
    
    // MARK: - Statistics
    
    var totalSizeFormatted: String {
        let total = items.reduce(0) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    var imageCount: Int { items.filter { $0.isImage }.count }
    var videoCount: Int { items.filter { $0.isVideo }.count }
    var documentCount: Int { items.filter { $0.isPDF || $0.isText }.count }

    // MARK: - Legacy UI & Interaction Support
    
    @Published var searchQuery: String = ""
    @Published var sortOrder: SortOrder = .dateAdded
    @Published var selectedItems: Set<UUID> = []
    
    func deselectAll() {
        selectedItems.removeAll()
    }
    
    func removeItemsAndClearSelection(_ items: [UUID]) {
         self.items.removeAll { items.contains($0.id) }
         saveItems()
         selectedItems.removeAll()
    }

    // MARK: - Compatibility
    
    func addItems(urls: [URL]) {
        for url in urls {
             if !items.contains(where: { $0.url == url }) {
                 let item = ShelfItem(url: url)
                 try? _ = item.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                 items.insert(item, at: 0)
             }
        }
        if items.count > maxItems {
             items = Array(items.prefix(maxItems))
        }
        saveItems()
    }
}

// MARK: - Enums (Simplified for now)

enum SortOrder: String, CaseIterable {
    case dateAdded = "Date Added", name = "Name", size = "Size", type = "Type"
}
