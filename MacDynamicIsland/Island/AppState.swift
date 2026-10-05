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
    let clipboardStore: ClipboardStore
    /// Only the main island watches for files dragged to the notch; the drag detector knows one region
    private let tracksDrags: Bool

    @Published var isIslandVisible: Bool = true
    @Published var visibilityReason: IslandVisibilityReason = .none
    @Published var interactionState: IslandInteractionState = .idle
    @Published var islandMode: IslandMode = .compact {
        didSet {
            resetAutoCloseTimer()
            islandSizeDidChange.send()
            if oldValue == .expanded && islandMode == .compact { didCollapse.send() }
        }
    }
    @Published var currentSection: IslandTab = .music {
        didSet { resetAutoCloseTimer(); islandSizeDidChange.send() }
    }
    /// Sent once a new islandMode or currentSection is stored. @Published sends before the value is stored,
    /// and resizing the panel then makes SwiftUI lay out with the old value and miss the new one
    let islandSizeDidChange = PassthroughSubject<Void, Never>()
    /// Sent when the open island has closed
    let didCollapse = PassthroughSubject<Void, Never>()
    @Published var isDraggingOver: Bool = false

    /// Notch size of the display the island is on (.zero when it has no notch)
    @Published var notchSize: CGSize = .zero
    /// The island is on a large external display (NSScreen.isLargeDisplay): it opens wider, and its collapsed pill
    /// widens to fit the whole title and lyric line
    @Published var isOnLargeDisplay = false
    /// Collapsed content beside the notch, as wide as the menus and status icons leave room for.
    /// Set by IslandController after it has sized the panel, so the view never animates outside the panel.
    @Published var liveActivityWings: IslandWings = .none
    /// What fills the wings; set by IslandController together with them
    @Published var liveActivity: LiveActivity = .none
    /// Whether the collapsed island shows its live activity (now playing or an agent session) beside the notch
    var showsLiveActivity: Bool { !liveActivityWings.isEmpty }
    /// The pointer is on the collapsed island: paused music shows beside the notch while it stays there
    @Published var isPeekingNotch: Bool = false
    /// Current frame of the island panel, in screen coordinates
    private(set) var islandFrame: CGRect = .zero
    /// The panel showing this island; IslandWindow sets it
    weak var panel: NSWindow?
    /// You're typing in the island, e.g. an answer to an agent's question: it doesn't close under you
    var isTyping: Bool {
        guard let panel, panel.isKeyWindow else { return false }
        return panel.firstResponder is NSText
    }

    // CUSTOMIZATION: Resolved from settingsStore
    var islandBackgroundColor: Color {
        settingsStore.resolveBackgroundColor()
    }
    var islandTheme: IslandTheme {
        settingsStore.resolveTheme()
    }

    private var settingsCancellable: AnyCancellable?
    private var tabsCancellable: AnyCancellable?
    private var autoCloseTimer: Timer?

    /// State of one island. The main one owns the clipboard history and watches for dragged files;
    /// islands on the other displays (with "all screens" on) share its history
    init(sharingWith main: AppState? = nil) {
        clipboardStore = main?.clipboardStore ?? ClipboardStore()
        tracksDrags = main == nil

        // Sync setting changes to AppState triggers
        settingsCancellable = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // A tab you switch off while it's showing hands over to the first one left. On the next turn:
        // @Published sends before the new list is stored
        tabsCancellable = TabStore.shared.$enabledTabs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tabs in
                guard let self, !tabs.contains(self.currentSection), let first = tabs.first else { return }
                self.currentSection = first
            }
        currentSection = TabStore.shared.enabledTabs.first ?? .music

        guard main == nil else { return }
        // Clipboard polling is started by AppIntegration; only load history here
        clipboardStore.loadFromDisk()

        // Start the global drag detector (Boring Notch style)
        setupGlobalDragMonitor()
    }

    func resetAutoCloseTimer() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil

        guard islandMode == .expanded else { return }
        guard settingsStore.get(SettingsDefaults.autoCloseEnabled) else { return }

        let timeout = settingsStore.get(SettingsDefaults.autoCloseTimeout)
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                // An agent's question or permission prompt stays open until you've dealt with it,
                // and nothing closes under your typing
                guard self?.visibilityReason != .heldByPlugin, self?.isTyping != true else { return }
                self?.deactivateIsland()
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

    // ENUMS
    enum IslandMode { case compact, expanded }

    // HELPER METHODS
    func showIsland(reason: IslandVisibilityReason = .userExpanded) {
        visibilityReason = reason; isIslandVisible = true
    }
    func activateIsland(reason: IslandVisibilityReason = .userExpanded) {
        interactionState = .active; islandMode = .expanded; isIslandVisible = true; visibilityReason = reason
    }
    func deactivateIsland() {
        interactionState = .idle; islandMode = .compact
    }

    func forceCloseIsland() {
        deactivateIsland()
    }

    func logEvent(_ message: String) {
        let logger = os.Logger(subsystem: "com.maclingdonggao.app", category: "state")
        logger.info("\(message)")
    }

    // MARK: - Global Drag Detection (Boring Notch Style)

    private func setupGlobalDragMonitor() {
        let detector = DragMonitor.shared

        // When a drag enters the notch region
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.isDraggingOver = true
                self?.logEvent("🎯 Drag entered notch region")

                // If collapsed, expand to the files section (when it's one of your tabs)
                if self?.islandMode == .compact, TabStore.shared.isEnabled(.files) {
                    self?.activateIsland(reason: .dragDetected)
                    self?.currentSection = .files
                }
            }
        }

        // When a drag leaves the notch region
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

                ShelfStore.shared.add(urls)
                self?.isDraggingOver = false
            }
        }

        // Start listening
        detector.startMonitoring()
    }

    func updateNotchRegion(_ region: CGRect) {
        islandFrame = region
        if tracksDrags { DragMonitor.shared.updateNotchRegion(region) }
    }
}
