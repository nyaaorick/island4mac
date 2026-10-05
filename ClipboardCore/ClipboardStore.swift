import Foundation
import AppKit
import Combine

/// Your clipboard history, newest first, kept in its own folder: `history.json` and a file per copied picture.
/// The folder is the Clipboard plugin's data folder (PluginData/clipboard). The Clipboard plugin's logic; also
/// compiled into the app, for its tests. No SwiftUI and no island in here
@MainActor
final class ClipboardStore: ObservableObject {
    /// What you can set: how many items it keeps and for how long
    struct Settings: Equatable {
        var maxItems = 50
        /// 0: forever
        var keepHours = 24
    }

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet { syncImageFiles() }
    }

    @Published var settings: Settings {
        didSet { applySettings() }
    }

    let folder: URL
    /// Copied pictures as files, one per item (`<id>.png`), so the tab can show them as pictures (PluginImage)
    var imageFolder: URL { folder.appendingPathComponent("Images", isDirectory: true) }
    private var historyFile: URL { folder.appendingPathComponent("history.json") }

    /// The app you were using: pasting goes into it. Ignores this process unless told otherwise (a plugin
    /// ignores the island app that runs it)
    let frontmostApps: FrontmostAppMonitor

    /// The app's own clipboard history before it moved into the folder (UserDefaults, `mac_island_clipvault_v1`)
    private let legacyDefaults: UserDefaults?
    static let legacyKey = "mac_island_clipvault_v1"

    init(folder: URL, settings: Settings = Settings(), legacyDefaults: UserDefaults? = .standard,
         frontmostApps: FrontmostAppMonitor? = nil) {
        self.folder = folder
        self.settings = settings
        self.legacyDefaults = legacyDefaults
        self.frontmostApps = frontmostApps ?? FrontmostAppMonitor(ignoring: ProcessInfo.processInfo.processIdentifier)
    }

    var imageItemCount: Int { items.filter { $0.type == .image }.count }

    // MARK: - Changing the history

    func addItem(content: String, type: ClipboardItem.ItemType, sourceBundleID: String?, sourceAppName: String?, imageData: Data?) {
        // Skip consecutive duplicates. Images all share the "[Image]" placeholder
        // content, so their bytes must be compared as well.
        if let last = items.first, last.content == content, last.type == type, last.imageData == imageData { return }
        let item = ClipboardItem(content: content, type: type, sourceBundleID: sourceBundleID, sourceAppName: sourceAppName,
                                 imageData: imageData)
        items = Array(([item] + items).prefix(settings.maxItems))
        save()
    }

    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    /// Drops what's older than you keep
    func pruneExpiredItems(now: Date = Date()) {
        guard settings.keepHours > 0 else { return }
        let kept = items.filter { now.timeIntervalSince($0.timestamp) <= Double(settings.keepHours * 3600) }
        guard kept.count != items.count else { return }
        items = kept
        save()
    }

    private func applySettings() {
        if items.count > settings.maxItems {
            items = Array(items.prefix(settings.maxItems))
            save()
        }
        pruneExpiredItems()
    }

    // MARK: - Pasting

    /// Pastes the item into `app`, the app you were using (by default the one before the island). Clicking the
    /// card brought the island to the front, so that app comes back first, or the ⌘V would land in the island
    func pasteItem(_ item: ClipboardItem, into app: NSRunningApplication? = nil) {
        copyToClipboard(item)
        guard let app = app ?? frontmostApps.previousApp, !app.isTerminated else { return }
        app.activate(options: [])
        Task {
            // Activating takes a moment (from a plugin, the island hands it back as it closes). If it doesn't come
            // forward the item stays on the clipboard, rather than being pasted into whatever is in front
            var isInFront: Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
            for _ in 0..<60 {
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.type {
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        default:
            pasteboard.setString(item.content, forType: .string)
        }
    }

    // MARK: - Pictures as files

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

    // MARK: - On disk

    private func save() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: historyFile, options: .atomic)
    }

    /// Reads the history, moving the app's old one (UserDefaults) into the folder the first time
    func load() {
        if let data = try? Data(contentsOf: historyFile),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        } else if let legacyDefaults, let data = legacyDefaults.data(forKey: Self.legacyKey),
                  let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
            save()
            // Only once the history is safely in the folder
            if (try? Data(contentsOf: historyFile)) != nil { legacyDefaults.removeObject(forKey: Self.legacyKey) }
        }
        pruneExpiredItems()
    }
}
