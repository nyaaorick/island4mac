import Foundation
import AppKit
import Combine
import IslandKit

/// Your clipboard history in the island, as a plugin that ships inside the app. Its logic is the shared
/// ClipboardCore (the history, pasteboard polling, pasting); what it shows is a card per item, through the plugin
/// protocol only. It runs in the background, so it hears every copy whether or not its tab is open
@main
struct ClipboardPlugin: IslandPlugin {
    static let id = "clipboard"
    static let name = "Clipboard"
    static let symbol = "doc.on.clipboard"
    static let version = "1.0.0"
    static let description: String? = "What you copy, to paste again from the island"
    /// Copies are kept whether or not the Clipboard tab is one of yours
    static let background = true

    @Preference("Items to keep", options: [10, 20, 50]) var maxItems = 50
    @Preference("Hours to keep them (0: forever)", options: [24, 72, 168, 0]) var keepHours = 24

    private var store: ClipboardStore { ClipboardService.shared.store }

    func onStart() {
        ClipboardService.shared.start()
    }

    /// "2 min ago" moves on: once a minute while the tab shows
    var timeline: [Date] {
        guard Island.isTabVisible, !store.items.isEmpty else { return [] }
        return [Date(timeIntervalSince1970: (Island.now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)]
    }

    var body: some IslandContent {
        let _ = ClipboardService.shared.apply(ClipboardStore.Settings(maxItems: maxItems, keepHours: keepHours))
        for item in store.items {
            Card(item.sourceAppName ?? "Unknown", subtitle: item.relativeTime, symbol: "doc.on.clipboard",
                 image: item.sourceBundleID.map(IslandImage.app), preview: preview(of: item), id: "paste:\(item.id.uuidString)",
                 actions: [RowAction("Delete", symbol: "trash") { store.removeItem(item) }]) {
                // The island closes and gives the keyboard back to the app you were using; the paste lands there
                Island.close()
                store.pasteItem(item)
            }
        }
        if !store.items.isEmpty {
            Button("Clear", symbol: "trash") { store.clearAll() }
        }
    }

    private func preview(of item: ClipboardItem) -> CardPreview {
        if item.type == .image, let file = store.imageFile(for: item) { return .image(.file(file.path)) }
        return .text(item.content)
    }
}

/// The history and the pasteboard polling, for as long as the plugin runs
@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    let store = ClipboardStore(
        folder: Island.dataDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("clipboard"),
        // The app kept the history in its own defaults before; read once, then moved into the data folder
        legacyDefaults: UserDefaults(suiteName: "com.macdynamicisland.app"),
        // The island app runs this plugin: it's the app to skip when remembering the one you were using
        frontmostApps: FrontmostAppMonitor(ignoring: getppid()))
    private var monitor: ClipboardMonitor?
    private var changes: AnyCancellable?

    func start() {
        store.load()
        monitor = ClipboardMonitor(store: store)
        monitor?.start()
        changes = store.objectWillChange.sink { _ in Island.refresh() }
    }

    /// The settings, as the preferences say
    func apply(_ settings: ClipboardStore.Settings) {
        if store.settings != settings { store.settings = settings }
    }
}
