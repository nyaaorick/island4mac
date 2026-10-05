import Foundation
import AppKit

/// The Clipboard tab in the plugin protocol: what it shows, as PluginStore.Content, and what a tap does, as a
/// PluginEvent. It is what the Clipboard plugin will send and hear, drawn by the same PluginContentView
extension ClipboardStore {
    /// A card per item, newest first: the app it came from, when, and the text or picture
    var islandContent: PluginStore.Content {
        var content = PluginStore.Content()
        content.cards = items.prefix(PluginMessage.maxItems).map { item in
            let preview: PluginCardPreview = if item.type == .image, let file = imageFile(for: item) {
                .image(.file(file.path))
            } else {
                .text(item.content)
            }
            return PluginCard(id: "paste:\(item.id.uuidString)", title: item.sourceAppName ?? "Unknown", subtitle: item.relativeTime,
                              symbol: "doc.on.clipboard", image: item.sourceBundleID.map(PluginImage.app), preview: preview,
                              actions: [PluginRowAction(id: "delete:\(item.id.uuidString)", title: "Delete", symbol: "trash")])
                .trimmed
        }
        if !items.isEmpty {
            content.buttons = [PluginButton(id: "clear", title: "Clear", symbol: "trash")]
        }
        return content
    }

    /// A tap in the tab: paste a card's item into `app`, delete one, or clear them all. Returns whether it
    /// pasted, so the island can close
    @discardableResult
    func handle(_ event: PluginEvent, pastingInto app: NSRunningApplication?) -> Bool {
        guard case .action(let id) = event else { return false }
        if id == "clear" {
            clearAll()
            return false
        }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let itemID = UUID(uuidString: parts[1]),
              let item = items.first(where: { $0.id == itemID }) else { return false }
        switch parts[0] {
        case "paste":
            pasteItem(item, into: app)
            return true
        case "delete":
            removeItem(item)
        default:
            break
        }
        return false
    }
}
