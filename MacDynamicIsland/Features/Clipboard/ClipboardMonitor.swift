import Cocoa
import Combine

// MARK: - ClipboardMonitor (Polling & Notification)
final class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let store: ClipboardStore
    
    init(store: ClipboardStore) {
        self.store = store
    }
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName
        
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                let pngData = bitmap.representation(using: .png, properties: [:])
                Task { @MainActor in
                    store.addItem(content: "[Image]", type: ClipboardItem.ItemType.image, sourceBundleID: bundleID, sourceAppName: appName, imageData: pngData)
                    IslandController.shared.getAppState().showIsland(reason: .clipboard)
                }
            }
            return
        }
        
        if let string = pb.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = detectType(trimmed)
            
            Task { @MainActor in
                store.addItem(content: trimmed, type: type, sourceBundleID: bundleID, sourceAppName: appName, imageData: nil)
                IslandController.shared.getAppState().showIsland(reason: .clipboard)
            }
        }
    }
    
    private func detectType(_ content: String) -> ClipboardItem.ItemType {
        if let url = URL(string: content), url.scheme != nil { return ClipboardItem.ItemType.url }
        let codeMarkers = ["{", "}", ";", "func ", "let ", "var ", "import", "class"]
        if codeMarkers.contains(where: { content.contains($0) }) { return ClipboardItem.ItemType.code }
        return ClipboardItem.ItemType.text
    }
}
