import AppKit

/// Watches the pasteboard (polled twice a second, as macOS has no notification for it) and adds what you copy
/// to the clipboard history, with the app it came from. `onCopy` hears each new item
@MainActor
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let store: ClipboardStore
    /// Something new was copied and added
    var onCopy: () -> Void = {}

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClipboard() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName

        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }
            store.addItem(content: "[Image]", type: .image, sourceBundleID: bundleID, sourceAppName: appName,
                          imageData: bitmap.representation(using: .png, properties: [:]))
            onCopy()
            return
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            store.addItem(content: trimmed, type: Self.detectType(trimmed), sourceBundleID: bundleID, sourceAppName: appName, imageData: nil)
            onCopy()
        }
    }

    static func detectType(_ content: String) -> ClipboardItem.ItemType {
        if let url = URL(string: content), url.scheme != nil { return .url }
        let codeMarkers = ["{", "}", ";", "func ", "let ", "var ", "import", "class"]
        if codeMarkers.contains(where: { content.contains($0) }) { return .code }
        return .text
    }
}
