import Foundation
import AppKit
import Combine
import SwiftUI

// MARK: - ClipboardItem
struct ClipboardItem: Identifiable, Codable, Equatable {
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
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.id == rhs.id
    }

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

@MainActor
final class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = [] {
        didSet { syncImageFiles() }
    }

    private let defaults: UserDefaults
    /// Copied images as files, one per item (`<id>.png`), so the tab can show them as pictures (PluginImage)
    let imageFolder: URL

    init(defaults: UserDefaults = .standard, imageFolder: URL = ClipboardStore.defaultImageFolder) {
        self.defaults = defaults
        self.imageFolder = imageFolder
    }

    nonisolated static var defaultImageFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.macdynamicisland.app", isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    /// The file of an image item, once written
    func imageFile(for item: ClipboardItem) -> URL? {
        let url = imageFolder.appendingPathComponent("\(item.id.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes the images that have no file yet and removes the files of items that are gone
    private func syncImageFiles() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        var wanted = Set<String>()
        for item in items where item.type == .image {
            guard let data = item.imageData else { continue }
            let name = "\(item.id.uuidString).png"
            wanted.insert(name)
            let url = imageFolder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) { try? data.write(to: url, options: .atomic) }
        }
        for name in (try? fileManager.contentsOfDirectory(atPath: imageFolder.path)) ?? [] where !wanted.contains(name) {
            try? fileManager.removeItem(at: imageFolder.appendingPathComponent(name))
        }
    }

    // UI Settings
    @Published var maxItems: Int = 50
    @Published var ttlHours: Int = 24
    
    // Statistics
    var totalItemCount: Int { items.count }
    var imageItemCount: Int { items.filter { $0.type == .image }.count }
    var fileItemCount: Int { fileVaultCount() }
    
    private func fileVaultCount() -> Int {
        // Safe access to fileVault if it were here
        return 0 
    }
    
    func updateSettings(maxItems: Int? = nil, ttlHours: Int? = nil) {
        if let m = maxItems { self.maxItems = m }
        if let t = ttlHours { self.ttlHours = t }
        // Note: Real implementation would persist these to UserDefaults
    }
    
    func clearUnpinned() {
        // Simple implementation: clear all (since ClipboardItem doesn't have pinned state yet)
        clearAll()
    }
    
    func pruneExpiredItems() {
        let now = Date()
        withAnimation {
            items.removeAll { now.timeIntervalSince($0.timestamp) > Double(ttlHours * 3600) }
        }
    }
    
    func addItem(content: String, type: ClipboardItem.ItemType, sourceBundleID: String?, sourceAppName: String?, imageData: Data?) {
        // Skip consecutive duplicates. Images all share the "[Image]" placeholder
        // content, so their bytes must be compared as well.
        if let last = items.first, last.content == content, last.type == type, last.imageData == imageData { return }
        
        let newItem = ClipboardItem(
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
    func pasteItem(_ item: ClipboardItem, into app: NSRunningApplication?) {
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
            _ = await AppleScriptClient.execute(Self.pasteScript)
        }
    }

    private static let pasteScript = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
    
    func copyToClipboard(_ item: ClipboardItem) {
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
    
    func removeItem(_ item: ClipboardItem) {
        withAnimation {
            items.removeAll { $0.id == item.id }
        }
        saveToDisk()
    }
    
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: "mac_island_clipvault_v1")
        }
    }

    func loadFromDisk() {
        if let data = defaults.data(forKey: "mac_island_clipvault_v1"),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        }
    }
}
