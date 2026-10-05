import Foundation
import AppKit
import Quartz

/// Service for displaying QuickLook previews
class QuickLookService: NSObject {
    static let shared = QuickLookService()
    
    private var previewPanel: QLPreviewPanel?
    private var currentURLs: [URL] = []
    private var currentIndex: Int = 0
    
    private override init() {
        super.init()
    }
    
    /// Show QuickLook preview for a single file
    func preview(url: URL) {
        preview(urls: [url], at: 0)
    }
    
    /// Show QuickLook preview for multiple files
    func preview(urls: [URL], at index: Int = 0) {
        guard !urls.isEmpty, index < urls.count else { return }
        
        currentURLs = urls
        currentIndex = index
        
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared() {
            panel.delegate = self
            panel.dataSource = self
            
            if !panel.isVisible {
                panel.makeKeyAndOrderFront(nil)
            }
            
            panel.currentPreviewItemIndex = index
            panel.reloadData()
            
            previewPanel = panel
        } else {
            let panel = QLPreviewPanel.shared()
            panel?.delegate = self
            panel?.dataSource = self
            panel?.makeKeyAndOrderFront(nil)
            panel?.currentPreviewItemIndex = index
            panel?.reloadData()
            
            previewPanel = panel
        }
    }
    
    /// Close the QuickLook panel
    func close() {
        if let panel = previewPanel, panel.isVisible {
            panel.close()
        }
        currentURLs.removeAll()
        previewPanel = nil
    }
}

// MARK: - QLPreviewPanelDataSource

extension QuickLookService: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURLs.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < currentURLs.count else { return nil }
        return currentURLs[index] as NSURL
    }
}

// MARK: - QLPreviewPanelDelegate

extension QuickLookService: QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event = event else { return false }
        // Allow keyboard shortcuts
        if event.type == .keyDown {
            return true
        }
        return false
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        // Return the frame where the preview should animate from
        return NSScreen.main?.visibleFrame ?? .zero
    }
}
