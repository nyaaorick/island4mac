import Cocoa
import UniformTypeIdentifiers

/// Global drag detector, modeled on Boring Notch
/// Detects system-wide file drags and fires a callback when a drag enters the notch region
final class DragDetectorManager {
    
    static let shared = DragDetectorManager()
    
    // MARK: - Callbacks
    
    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void
    typealias DropCallback = (_ urls: [URL]) -> Void
    
    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?

    /// ⚠️ Fallback drop callback: used when SwiftUI `.onDrop` does not fire in floating panels.
    /// Triggered on global mouse up while dragging content and mouse is inside notchRegion.
    var onDropInNotchRegion: DropCallback?
    
    // MARK: - Private Properties
    
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    
    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false
    private var didFireDropForCurrentDrag: Bool = false
    
    private var notchRegion: CGRect = .zero
    private let dragPasteboard = NSPasteboard(name: .drag)
    
    // Throttling
    private var lastProcessedTime: TimeInterval = 0
    private let throttleInterval: TimeInterval = 0.05 // 50ms throttle, down from handling every event to 20fps
    
    private init() {}
    
    // MARK: - Public Methods
    
    func updateNotchRegion(_ region: CGRect) {
        self.notchRegion = region
    }
    
    func startMonitoring() {
        stopMonitoring()
        
        // Watch mouse down - record the pasteboard state
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.didFireDropForCurrentDrag = false
        }
        
        // Watch drag movement - detect entering the notch region (optimized: throttled)
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }
            
            // ✅ Throttle: don't handle every mouseDragged
            let now = Date().timeIntervalSinceReferenceDate
            guard now - self.lastProcessedTime >= self.throttleInterval else { return }
            self.lastProcessedTime = now
            
            let newContent = self.dragPasteboard.changeCount != self.pasteboardChangeCount
            
            // Check that content is really being dragged (pasteboard changed + content valid)
            if newContent && !self.isContentDragging && self.hasValidDragContent() {
                self.isContentDragging = true
            }
            
            // Only handle position while content is being dragged
            if self.isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Detect entering/leaving the notch region
                let containsMouse = self.notchRegion.contains(mouseLocation)
                if containsMouse && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouse && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }
        
        // Watch mouse up - trigger the fallback drop (if released inside the notch region)
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let mouseLocation = NSEvent.mouseLocation
            let releasedInsideNotch = self.notchRegion.contains(mouseLocation)

            if releasedInsideNotch && self.isContentDragging && !self.didFireDropForCurrentDrag {
                self.didFireDropForCurrentDrag = true

                let urls = self.extractFileURLsFromDragPasteboard()
                if !urls.isEmpty {
                    print("💥 [DragDetectorManager] Fallback drop detected. urls=\(urls.count)")
                    self.onDropInNotchRegion?(urls)
                } else {
                    print("⚠️ [DragDetectorManager] Fallback drop detected but no file URLs found.")
                }
            }
            
            self.isDragging = false
            self.isContentDragging = false
            
            // Reset the region state after a delay to give the UI time to react
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.hasEnteredNotchRegion = false
            }
            
            self.pasteboardChangeCount = -1
        }
    }
    
    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }
    
    // MARK: - Private Helpers
    
    /// Check whether the drag pasteboard holds valid content
    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    private func extractFileURLsFromDragPasteboard() -> [URL] {
        // Prefer NSURL objects (most reliable for Finder drops)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        if let objects = dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] {
            let urls = objects.compactMap { $0 as URL }
            return urls
        }

        // Fallback: sometimes file URLs come as plain strings
        if let strings = dragPasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [NSString] {
            let urls = strings
                .map { $0 as String }
                .compactMap { URL(string: $0) ?? URL(fileURLWithPath: $0) }
                .filter { $0.isFileURL }
            return urls
        }

        return []
    }
    
    deinit {
        stopMonitoring()
    }
}
