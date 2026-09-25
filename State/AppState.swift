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
    let clipVault: IslandClipVault
    var clipboardHub: ClipboardHubStore { clipVault }
    /// Only the main island watches for files dragged to the notch; the drag detector knows one region
    private let tracksDrags: Bool

    @Published var isOverlayVisible: Bool = true
    @Published var visibilityReason: OverlayVisibilityReason = .none
    @Published var interactionState: IslandInteractionState = .idle
    @Published var overlayMode: OverlayMode = .compact {
        didSet { resetAutoCloseTimer(); islandSizeDidChange.send() }
    }
    @Published var currentSection: IslandSection = .music {
        didSet { resetAutoCloseTimer(); islandSizeDidChange.send() }
    }
    /// Sent once a new overlayMode or currentSection is stored. @Published sends before the value is stored,
    /// and resizing the panel then makes SwiftUI lay out with the old value and miss the new one
    let islandSizeDidChange = PassthroughSubject<Void, Never>()
    @Published var isDraggingOver: Bool = false

    /// Notch size of the display the island is on (.zero when it has no notch)
    @Published var notchSize: CGSize = .zero
    /// Collapsed content beside the notch, as wide as the menus and status icons leave room for.
    /// Set by OverlayWindowController after it has sized the panel, so the view never animates outside the panel.
    @Published var liveActivityWings: IslandWings = .none
    /// Whether the collapsed island shows its live activity (now playing or an agent session) beside the notch
    var showsLiveActivity: Bool { !liveActivityWings.isEmpty }
    /// The pointer is on the collapsed island: paused music shows beside the notch while it stays there
    @Published var isPeekingNotch: Bool = false
    /// Current frame of the island panel, in screen coordinates
    private(set) var islandFrame: CGRect = .zero

    // CUSTOMIZATION: Resolved from settingsStore
    var islandBackgroundColor: Color {
        settingsStore.resolveBackgroundColor()
    }

    private var settingsCancellable: AnyCancellable?
    private var autoCloseTimer: Timer?

    /// State of one island. The main one owns the clipboard history and watches for dragged files;
    /// islands on the other displays (with "all screens" on) share its history
    init(sharingWith main: AppState? = nil) {
        clipVault = main?.clipVault ?? IslandClipVault()
        tracksDrags = main == nil

        // Sync setting changes to AppState triggers
        settingsCancellable = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        guard main == nil else { return }
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
                // An agent's question or permission prompt stays open until you've dealt with it
                guard self?.visibilityReason != .agentPrompt else { return }
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
        case music, clipboard, files, agents
        var displayName: String {
             switch self {
             case .music: return "Music"
             case .clipboard: return "Clipboard"
             case .files: return "Files"
             case .agents: return "Agents"
             }
        }
        var iconName: String {
             switch self {
             case .music: return "music.note"
             case .clipboard: return "doc.on.clipboard"
             case .files: return "folder"
             case .agents: return "terminal"
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
        islandFrame = region
        if tracksDrags { DragDetectorManager.shared.updateNotchRegion(region) }
    }
}
