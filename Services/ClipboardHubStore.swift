import Foundation
import AppKit
import Combine
import SwiftUI

// MARK: - IslandClipItem
struct IslandClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let type: ItemType
    let timestamp: Date
    let sourceBundleID: String?
    let sourceAppName: String?
    let imageData: Data?
    
    enum ItemType: String, Codable {
        case text, image, url, code
    }
    
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var sourceIcon: NSImage {
        if let bundleID = sourceBundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) ?? NSImage()
    }

    static func == (lhs: IslandClipItem, rhs: IslandClipItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    var isPinned: Bool { false } // TODO: Add persistence for pinning
    var relativeTimeString: String { relativeTime }

    init(id: UUID = UUID(), content: String, type: ItemType, timestamp: Date = Date(), sourceBundleID: String?, sourceAppName: String?, imageData: Data?) {
        self.id = id
        self.content = content
        self.type = type
        self.timestamp = timestamp
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.imageData = imageData
    }
}

typealias IslandClipVault = ClipboardHubStore

// MARK: - ClipboardHubStore (The Island functional vault)
// Migrated from IslandClipVault to support advanced settings
@MainActor
final class ClipboardHubStore: ObservableObject {
    @Published var items: [IslandClipItem] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // UI Settings
    enum DisplayMode: String, Codable { case grid, reel }
    @Published var displayMode: DisplayMode = .grid
    @Published var maxItems: Int = 50
    @Published var ttlHours: Int = 24
    
    // Security & Privacy
    @Published var encryptionEnabled: Bool = false
    @Published var touchIDEnabled: Bool = false
    @Published var sessionTimeoutMinutes: Int = 5
    
    // NATIVE LIST SEARCH & FILTER
    @Published var searchQuery: String = ""
    @Published var currentFilter: SearchEngine.ContentFilter = .all
    @Published var selectedItemID: UUID? = nil
    
    // Statistics
    var totalItemCount: Int { items.count }
    var imageItemCount: Int { items.filter { $0.type == .image }.count }
    var fileItemCount: Int { fileVaultCount() }
    
    private func fileVaultCount() -> Int {
        // Safe access to fileVault if it were here
        return 0 
    }
    
    var displayItems: [IslandClipItem] {
        items.filter { item in
            let matchesFilter = currentFilter == .all || currentFilter.matches_v1(item)
            let matchesSearch = searchQuery.isEmpty || item.content.localizedCaseInsensitiveContains(searchQuery)
            return matchesFilter && matchesSearch
        }
    }
    
    func updateSettings(maxItems: Int? = nil, ttlHours: Int? = nil, encryptionEnabled: Bool? = nil, touchIDEnabled: Bool? = nil, sessionTimeout: Int? = nil) {
        if let m = maxItems { self.maxItems = m }
        if let t = ttlHours { self.ttlHours = t }
        if let e = encryptionEnabled { self.encryptionEnabled = e }
        if let tid = touchIDEnabled { self.touchIDEnabled = tid }
        if let s = sessionTimeout { self.sessionTimeoutMinutes = s }
        // Note: Real implementation would persist these to UserDefaults
    }
    
    func clearUnpinned() {
        // Simple implementation: clear all (since IslandClipItem doesn't have pinned state yet)
        clearAll()
    }
    
    func pruneExpiredItems() {
        let now = Date()
        withAnimation {
            items.removeAll { now.timeIntervalSince($0.timestamp) > Double(ttlHours * 3600) }
        }
    }
    
    // Original Logic
    // private let maxItemsLimit = 20 // Using maxItems instead
    
    func addItem(content: String, type: IslandClipItem.ItemType, sourceBundleID: String?, sourceAppName: String?, imageData: Data?) {
        // Skip consecutive duplicates. Images all share the "[Image]" placeholder
        // content, so their bytes must be compared as well.
        if let last = items.first, last.content == content, last.type == type, last.imageData == imageData { return }
        
        let newItem = IslandClipItem(
            id: UUID(),
            content: content,
            type: type,
            timestamp: Date(),
            sourceBundleID: sourceBundleID,
            sourceAppName: sourceAppName,
            imageData: imageData
        )
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            items.insert(newItem, at: 0)
            if items.count > maxItems { items.removeLast() }
        }
        saveToDisk()
    }
    
    func clearAll() {
        withAnimation { items.removeAll() }
        saveToDisk()
    }
    
    /// Pastes the item into `app`, the app you were using. Clicking the card brought this app to the front,
    /// so that one comes back first, or the ⌘V would land in the island
    func pasteItem(_ item: IslandClipItem, into app: NSRunningApplication?) {
        copyToClipboard(item)
        guard let app, !app.isTerminated else { return }
        app.activate(options: [])
        Task {
            // Activating takes a moment. If it doesn't come forward the item stays on the clipboard,
            // rather than being pasted into whatever is in front
            var isInFront: Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
            for _ in 0..<20 {
                if isInFront { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard isInFront else { return }
            // Its window becomes key just after
            try? await Task.sleep(for: .milliseconds(50))
            // Off the main thread: an Apple Event can wait on a permission prompt
            _ = await AppleScriptHelper.execute(Self.pasteScript)
        }
    }

    private static let pasteScript = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
    
    func copyToClipboard(_ item: IslandClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .image:
            if let data = item.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        default:
            pb.setString(item.content, forType: .string)
        }
    }
    
    func setFilter(_ filter: SearchEngine.ContentFilter) {
        withAnimation {
            currentFilter = filter
        }
    }
    
    func togglePin(for item: IslandClipItem) {
        // pinning logic placeholder
    }
    
    func removeItem(_ item: IslandClipItem) {
        withAnimation {
            items.removeAll { $0.id == item.id }
        }
        saveToDisk()
    }
    
    func clearSearch() {
        searchQuery = ""
    }
    
    func recordActivity() {
        // Placeholder for activity tracking or session update
    }
    
    func selectItem(_ id: UUID?) {
        selectedItemID = id
    }
    
    func getSelectedItem() -> IslandClipItem? {
        guard let id = selectedItemID else { return nil }
        return items.first(where: { $0.id == id })
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: "mac_island_clipvault_v1")
        }
    }

    func loadFromDisk() {
        if let data = defaults.data(forKey: "mac_island_clipvault_v1"),
           let decoded = try? JSONDecoder().decode([IslandClipItem].self, from: data) {
            items = decoded
        }
    }
}
