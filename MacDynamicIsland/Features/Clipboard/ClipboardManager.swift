import Cocoa
import Combine

// MARK: - ClipboardManager (Polling & Notification)
final class ClipboardManager: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let vault: IslandClipVault
    
    init(vault: IslandClipVault) {
        self.vault = vault
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
                    vault.addItem(content: "[Image]", type: IslandClipItem.ItemType.image, sourceBundleID: bundleID, sourceAppName: appName, imageData: pngData)
                    OverlayWindowController.shared.getAppState().showOverlay(reason: .clipboard)
                }
            }
            return
        }
        
        if let string = pb.string(forType: .string), !string.isEmpty {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = detectType(trimmed)
            
            Task { @MainActor in
                vault.addItem(content: trimmed, type: type, sourceBundleID: bundleID, sourceAppName: appName, imageData: nil)
                OverlayWindowController.shared.getAppState().showOverlay(reason: .clipboard)
            }
        }
    }
    
    private func detectType(_ content: String) -> IslandClipItem.ItemType {
        if let url = URL(string: content), url.scheme != nil { return IslandClipItem.ItemType.url }
        let codeMarkers = ["{", "}", ";", "func ", "let ", "var ", "import", "class"]
        if codeMarkers.contains(where: { content.contains($0) }) { return IslandClipItem.ItemType.code }
        return IslandClipItem.ItemType.text
    }
}
