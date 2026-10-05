import Foundation
import AppKit
import Combine
import IslandKit

/// The file shelf in the island, as a plugin that ships inside the app. Its logic is the shared FilesCore (the
/// shelf and where it's kept); the island does the dragging (it opens on this tab, shows where to drop and hands
/// over what was dropped), and the shelf shows as a card per item that drags back out as the file
@main
struct FilesPlugin: IslandPlugin {
    static let id = "files"
    static let name = "Files"
    static let symbol = "tray"
    static let version = "1.0.0"
    static let description: String? = "Drop files, text and links on the island to keep them at hand"
    static let acceptsDrops = true

    private var store: ShelfStore { FilesService.shared.store }

    func onStart() {
        FilesService.shared.start()
    }

    var body: some IslandContent {
        if store.items.isEmpty {
            // Alone, the island draws it large in the middle of the tab
            Button("Drop files here", symbol: "tray.and.arrow.down") { FilesService.shared.chooseFiles() }
        } else {
            for item in store.items {
                card(for: item)
            }
            Button("Clear", symbol: "trash") { store.clearAll() }
        }
    }

    private func card(for item: ShelfItem) -> Card {
        let remove = RowAction("Remove", symbol: "xmark") { store.removeItem(item.id) }
        guard item.url.isFileURL else {
            return Card(item.displayName, symbol: "link", preview: .text(item.url.absoluteString), id: "open:\(item.id.uuidString)",
                        actions: [remove]) { NSWorkspace.shared.open(item.url) }
        }
        let reveal = RowAction("Show in Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        return Card(item.displayName, subtitle: Self.detail(of: item.url), symbol: item.iconName,
                    image: Self.appOpening(item.url).map(IslandImage.app), preview: .image(.file(item.url.path)), file: item.url.path,
                    id: "open:\(item.id.uuidString)", actions: [reveal, remove]) { NSWorkspace.shared.open(item.url) }
    }

    func onDrop(paths: [String], urls: [URL]) {
        store.add(paths: paths, urls: urls.map(\.absoluteString))
    }

    /// "Folder", or the file's size
    private static func detail(of url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
        if values.isDirectory == true { return "Folder" }
        return values.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }

    /// The bundle id of the app that opens this file by default
    private static func appOpening(_ url: URL) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// The shelf, for as long as the plugin runs
@MainActor
final class FilesService {
    static let shared = FilesService()

    let store = ShelfStore(
        folder: Island.dataDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("files"),
        // Where the app kept the shelf before; moved into the data folder once
        legacyFile: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDynamicIsland/shelf_items_v2.json"))
    private var changes: AnyCancellable?

    func start() {
        changes = store.objectWillChange.sink { _ in Island.refresh() }
    }

    /// The files you pick in an open panel go on the shelf, as if dropped there. The plugin is a plain program, so
    /// it becomes an app of its own just for the panel
    func chooseFiles() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        store.add(paths: panel.urls.map(\.path))
    }
}
