import Foundation
import SwiftUI
import Combine
import OSLog
import AppKit
import ApplicationServices

@MainActor
final class AppState: ObservableObject {
    let settingsStore = SettingsDefaults.shared

    // Clipboard history shown in the clipboard tab
    let clipVault = IslandClipVault()
    var clipboardHub: ClipboardHubStore { clipVault }

    @Published var isOverlayVisible: Bool = true
    @Published var visibilityReason: OverlayVisibilityReason = .none
    @Published var interactionState: IslandInteractionState = .idle
    @Published var overlayMode: OverlayMode = .compact {
        didSet { resetAutoCloseTimer() }
    }
    @Published var currentSection: IslandSection = .music {
        didSet { resetAutoCloseTimer() }
    }
    @Published var isDraggingOver: Bool = false

    // CUSTOMIZATION: Resolved from settingsStore
    var islandBackgroundColor: Color {
        settingsStore.resolveBackgroundColor()
    }

    private var settingsCancellable: AnyCancellable?
    private var autoCloseTimer: Timer?

    init() {
        // Sync setting changes to AppState triggers
        settingsCancellable = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Clipboard polling is started by AppIntegration; only load history here
        clipVault.loadFromDisk()

        // 启动全局拖拽检测器（Boring Notch 风格）
        setupGlobalDragDetector()
    }

    func resetAutoCloseTimer() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil

        guard overlayMode == .expanded else { return }
        guard settingsStore.get(SettingsDefaults.autoCloseEnabled) else { return }

        let timeout = settingsStore.get(SettingsDefaults.autoCloseTimeout)
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.deactivateOverlay()
            }
        }
    }

    // PERMISSIONS & POSITION
    @Published var isAXAuthorized: Bool = AXIsProcessTrusted()
    @Published var isPositionLocked: Bool = true
    @Published var isMoveModeEnabled: Bool = false

    func requestAXPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func togglePositionLock() {
        isPositionLocked.toggle()
        logEvent("Position lock: \(isPositionLocked)")
    }

    func toggleMoveMode() {
        isMoveModeEnabled.toggle()
        logEvent("Move mode: \(isMoveModeEnabled)")
    }

    // ENUMS
    enum IslandSection: String, CaseIterable {
        case music, clipboard, files, calendar, zone3
        var displayName: String {
             switch self {
             case .music: return "Music"
             case .clipboard: return "Clipboard"
             case .files: return "Files"
             case .calendar: return "Calendar"
             case .zone3: return "Zone"
             }
        }
        var iconName: String {
             switch self {
             case .music: return "music.note"
             case .clipboard: return "doc.on.clipboard"
             case .files: return "folder"
             case .calendar: return "calendar"
             case .zone3: return "briefcase"
             }
        }
    }

    enum OverlayMode { case compact, expanded }

    // HELPER METHODS
    func showOverlay(reason: OverlayVisibilityReason = .userExpanded) {
        visibilityReason = reason; isOverlayVisible = true
    }
    func activateOverlay(reason: OverlayVisibilityReason = .userExpanded) {
        interactionState = .active; overlayMode = .expanded; isOverlayVisible = true; visibilityReason = reason
    }
    func deactivateOverlay() {
        interactionState = .idle; overlayMode = .compact
    }

    func forceCloseOverlay() {
        deactivateOverlay()
    }

    func logEvent(_ message: String) {
        let logger = os.Logger(subsystem: "com.maclingdonggao.app", category: "state")
        logger.info("\(message)")
    }

    // MARK: - Global Drag Detection (Boring Notch Style)

    private func setupGlobalDragDetector() {
        let detector = DragDetectorManager.shared

        // 当拖拽进入刘海区域时
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.isDraggingOver = true
                self?.logEvent("🎯 Drag entered notch region")

                // 如果在收起状态，展开到文件区
                if self?.overlayMode == .compact {
                    self?.activateOverlay(reason: .dragDetected)
                    self?.currentSection = .files
                }
            }
        }

        // 当拖拽离开刘海区域时
        detector.onDragExitsNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.isDraggingOver = false
                self?.logEvent("📤 Drag exited notch region")
            }
        }

        // ⚠️ Fallback drop handler: fires when SwiftUI `.onDrop` is blocked by NSPanel settings
        detector.onDropInNotchRegion = { [weak self] urls in
            Task { @MainActor in
                self?.logEvent("💥 Fallback drop triggered with \(urls.count) files")

                // Convert URLs -> ShelfItems and add to the shelf
                for url in urls {
                    let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    let item = ShelfItem(url: url, bookmarkData: bookmarkData)
                    if !ShelfStateViewModel.shared.items.contains(where: { $0.url == item.url }) {
                        withAnimation(.spring()) {
                            ShelfStateViewModel.shared.items.insert(item, at: 0)
                        }
                    }
                }

                ShelfStateViewModel.shared.saveItems()
                self?.isDraggingOver = false
            }
        }

        // 启动监听
        detector.startMonitoring()
    }

    func updateNotchRegion(_ region: CGRect) {
        DragDetectorManager.shared.updateNotchRegion(region)
    }
}
