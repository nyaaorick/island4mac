import Foundation
import AppKit

/// The Files tab in the plugin protocol: what it shows, as PluginStore.Content, and what a tap does, as a
/// PluginEvent. It is what the Files plugin will send and hear, drawn by the same PluginContentView
extension ShelfStore {
    /// The app's shelf, in the Files plugin's data folder
    static let shared = ShelfStore(
        folder: PluginStore.defaultDataFolder.appendingPathComponent("files", isDirectory: true),
        legacyFile: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacDynamicIsland/shelf_items_v2.json"))

    /// A card per item, newest first: its thumbnail, name, size and the app that opens it; it drags out as the file
    var islandContent: PluginStore.Content {
        var content = PluginStore.Content()
        guard !items.isEmpty else {
            // Nothing yet: say what the tab is for. Alone, the button is drawn large in the middle of the tab
            content.buttons = [PluginButton(id: "choose", title: "Drop files here", symbol: "tray.and.arrow.down")]
            return content
        }
        content.cards = items.prefix(PluginMessage.maxItems).map { item in
            let id = item.id.uuidString
            var actions = [PluginRowAction(id: "remove:\(id)", title: "Remove", symbol: "xmark")]
            guard item.url.isFileURL else {
                return PluginCard(id: "open:\(id)", title: item.displayName, symbol: "link",
                                  preview: .text(item.url.absoluteString), actions: actions).trimmed
            }
            actions.insert(PluginRowAction(id: "reveal:\(id)", title: "Show in Finder", symbol: "folder"), at: 0)
            return PluginCard(id: "open:\(id)", title: item.displayName, subtitle: Self.detail(of: item.url), symbol: item.iconName,
                              image: Self.appOpening(item.url).map(PluginImage.app), preview: .image(.file(item.url.path)),
                              file: item.url.path, actions: actions).trimmed
        }
        content.buttons = [PluginButton(id: "clear", title: "Clear", symbol: "trash")]
        return content
    }

    /// A tap in the tab: open a card's item, show it in Finder, remove it, clear them all, or choose files to add
    func handle(_ event: PluginEvent) {
        guard case .action(let id) = event else { return }
        switch id {
        case "clear":
            clearAll()
            return
        case "choose":
            chooseFiles()
            return
        default:
            break
        }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let itemID = UUID(uuidString: parts[1]),
              let item = items.first(where: { $0.id == itemID }) else { return }
        switch parts[0] {
        case "open": NSWorkspace.shared.open(item.url)
        case "reveal": NSWorkspace.shared.activateFileViewerSelecting([item.url])
        case "remove": removeItem(itemID)
        default: break
        }
    }

    /// The files you pick in an open panel go on the shelf, as if dropped there
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated { self?.add(paths: panel.urls.map(\.path)) }
        }
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
