import Cocoa
import SwiftUI
import Combine

/// One island: a panel on one display and the state of what it shows. OverlayWindowController keeps the main one
/// on the display you chose (or under the mouse) and, with "all screens" on, one on every other display.
@MainActor
final class IslandWindow {
    let appState: AppState
    let panel: OverlayPanel
    private let hostingView: NSView
    private let settingsStore = SettingsDefaults.shared
    private var cancellables = Set<AnyCancellable>()
    /// The display this island belongs on right now
    private let preferredScreen: () -> NSScreen?

    /// Playing (paused for over a second counts as stopped); OverlayWindowController keeps it up to date
    var musicIsPlaying = false {
        didSet { if musicIsPlaying != oldValue { scheduleWindowUpdate() } }
    }

    // MARK: - Frame Management
    // All motion is driven by SwiftUI springs: the SwiftUI canvas has a fixed size and a fixed position on screen,
    // and the panel is just its viewfinder. The panel grows instantly before expanding and shrinks back instantly once the spring settles on collapse,
    // so AppKit neither animates nor triggers a SwiftUI relayout mid-animation.
    private var pendingShrink: DispatchWorkItem?
    private var pendingShrinkTarget: NSRect?
    private var windowUpdateScheduled = false
    /// The display the island is currently on
    private(set) var currentDisplayID: CGDirectDisplayID?
    /// The collapse spring (response 0.45, critically damped) settles within this time
    private let settleDelay: TimeInterval = 0.6

    init(appState: AppState, nowPlayingManager: NowPlayingManager, preferredScreen: @escaping () -> NSScreen?) {
        self.appState = appState
        self.preferredScreen = preferredScreen

        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],  // ✅ Removed .nonactivatingPanel
            backing: .buffered,
            defer: false
        )

        // Tell the view the current display's notch and size first, so the first frame isn't laid out as a no-notch, non-large display
        if let screen = preferredScreen() {
            appState.notchSize = screen.notchSize
            appState.isOnLargeDisplay = screen.isLargeDisplay
            currentDisplayID = screen.displayID
        }

        let rootView = NotchHomeView()
            // When the app is in the background, the first click on the island activates the window; by default that click isn't passed to buttons or tap gestures, so it would take two clicks to respond
            .allowsWindowActivationEvents()
            .environmentObject(appState)
            .environmentObject(appState.clipboardHub)
            .environmentObject(nowPlayingManager)
            .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        // ✅ Make sure the NSHostingView and its layer cast no shadow
        hostingView.shadow = nil
        hostingView.layer?.shadowOpacity = 0
        hostingView.layer?.shadowRadius = 0
        hostingView.layer?.shadowOffset = .zero

        // ✅ Key: the canvas size is fixed, so SwiftUI content doesn't constrain the window in turn, and there's no AutoLayout ↔︎ setFrame recursion
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        // The panel may grow and shrink asymmetrically; the canvas is placed by layoutCanvas according to screen position and doesn't resize with the panel
        hostingView.autoresizingMask = []
        // Size it before it's attached to the window: the container is 0×0 at that point, and the canvas sits top-centered
        let canvas = NotchMetrics.canvasSize(notch: appState.notchSize, largeDisplay: appState.isOnLargeDisplay)
        hostingView.frame = NSRect(x: -canvas.width / 2, y: -canvas.height, width: canvas.width, height: canvas.height)

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hostingView)

        self.hostingView = hostingView
        panel.contentView = container
        appState.panel = panel

        setupObservers()
    }

    /// Takes the island off screen for good (its display went away, or "all screens" was turned off)
    func close() {
        pendingShrink?.cancel()
        cancellables.removeAll()
        panel.orderOut(nil)
    }

    private func setupObservers() {
        // Adjust the panel synchronously once the new value is stored (didSet), so the panel is already big enough when SwiftUI renders the first frame of the expansion (or a switch to a larger section).
        // The @Published publisher can't be used: it fires at willSet, so resizing the panel then makes SwiftUI lay out with the old value and the new value only shows on the next event
        appState.islandSizeDidChange
            .compactMap { [weak appState] in appState.map { ($0.overlayMode, $0.currentSection) } }
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] mode, section in
                self?.updateWindowFrame(for: mode, section: section)
            }
            .store(in: &cancellables)

        // Defer to the next runloop turn, when the new value is already stored
        appState.$isOverlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelVisibility()
            }
            .store(in: &cancellables)

        // The island steps aside when the playing video is full screen on the island's display
        FullScreenVideo.shared.didChange
            .sink { [weak self] in
                self?.updatePanelVisibility()
            }
            .store(in: &cancellables)

        // Paused music only shows while the mouse rests on the notch
        appState.$isPeekingNotch
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
            }
            .store(in: &cancellables)

        // Clicking the island brings this app to the front and takes the keyboard from the app you're using; give it back once the island collapses
        appState.didCollapse
            .sink { [weak self] in
                guard let self else { return }
                OverlayWindowController.shared.returnFocus(from: self.panel)
            }
            .store(in: &cancellables)
    }

    func reposition() {
        updateWindowFrame(for: appState.overlayMode, section: appState.currentSection)
    }

    /// The panel only shows when you haven't hidden the island and the island's display isn't playing full-screen video
    private func updatePanelVisibility() {
        let coveredByVideo = currentDisplayID.map { FullScreenVideo.shared.displays.contains($0) } ?? false
        let shows = appState.isOverlayVisible && !coveredByVideo
        guard shows != panel.isVisible else { return }
        if shows {
            panel.orderFront(nil)
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: - Panel Frame

    /// Coalesce changes fired during willSet and recompute once the new value has taken effect
    func scheduleWindowUpdate() {
        guard !windowUpdateScheduled else { return }
        windowUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowUpdateScheduled = false
            self.updateWindowFrame(for: self.appState.overlayMode, section: self.appState.currentSection)
        }
    }

    /// Growing takes effect immediately to leave room for the island's animation; shrinking waits until the island's spring settles
    private func updateWindowFrame(for mode: AppState.OverlayMode, section: AppState.IslandSection) {
        guard let screen = targetScreen(for: mode) else { return }
        currentDisplayID = screen.displayID
        // The display it moved to may be playing full-screen video (or it just left such a display); decide whether to show the panel after it has been moved
        defer { updatePanelVisibility() }
        let notchSize = screen.notchSize
        // The island is wider on a large external display, and the canvas changes with it
        let largeDisplay = screen.isLargeDisplay
        if appState.notchSize != notchSize || appState.isOnLargeDisplay != largeDisplay {
            appState.notchSize = notchSize
            appState.isOnLargeDisplay = largeDisplay
            layoutCanvas()
        }
        let showsMusic = MusicManager.shared.showsCompactLiveActivity && (musicIsPlaying || appState.isPeekingNotch)
        let showsLiveActivity = showsMusic || AgentSessionStore.shared.showsCompactLiveActivity
        let wings = showsLiveActivity ? liveActivityWings(on: screen) : .none
        // Keep measuring while something is shown beside the notch: status bar icons widen and come and go (only displays with a notch need to make room)
        if notchSize != .zero {
            MenuBarSpace.shared.isWatching = showsLiveActivity
        }
        let target = windowFrame(for: mode, section: section, wings: wings, screen: screen)

        // Target unchanged: don't interrupt a shrink that's already scheduled, or frequent updates would keep the panel from ever shrinking back
        if let pending = pendingShrinkTarget, framesAreEffectivelyEqual(pending, target) {
            return
        }
        pendingShrink?.cancel()
        pendingShrink = nil
        pendingShrinkTarget = nil

        // Same display: first cover all the area the island occupies now and will occupy
        let current = panel.frame
        let immediate = current.intersects(screen.frame) ? current.union(target) : target
        setPanelFrame(immediate)

        // The panel is big enough now; let the view extend the playback wings
        if appState.liveActivityWings != wings {
            appState.liveActivityWings = wings
        }

        guard !framesAreEffectivelyEqual(immediate, target) else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShrink = nil
            self.pendingShrinkTarget = nil
            self.setPanelFrame(target)
            // The mouse may have moved to another display during the collapse; follow it now that things have settled
            self.scheduleWindowUpdate()
        }
        pendingShrink = shrink
        pendingShrinkTarget = target
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: shrink)
    }

    private func setPanelFrame(_ frame: NSRect) {
        if !framesAreEffectivelyEqual(frame, panel.frame) {
            // No forced immediate redraw: the canvas keeps its position on screen, so the next normal refresh is enough
            panel.setFrame(frame, display: false)
            layoutCanvas()
        }
        appState.updateNotchRegion(frame)
    }

    /// The canvas: the expanded island plus spring-bounce headroom, pinned to the panel's top edge and horizontally centered on the notch (the screen's center line);
    /// when the collapsed island's wings differ in width the panel is asymmetric, so it can't be centered on the panel
    private func layoutCanvas() {
        guard let container = panel.contentView else { return }
        let size = NotchMetrics.canvasSize(notch: appState.notchSize, largeDisplay: appState.isOnLargeDisplay)
        let bounds = container.bounds
        let screenMidX = currentScreen?.frame.midX ?? panel.frame.midX
        let frame = NSRect(
            x: screenMidX - panel.frame.minX - size.width / 2,
            y: bounds.height - size.height,
            width: size.width,
            height: size.height
        )
        if !framesAreEffectivelyEqual(frame, hostingView.frame) {
            hostingView.frame = frame
        }
    }

    private func framesAreEffectivelyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        // Allow 0.5pt of slack so floating-point jitter doesn't cause repeated setFrame calls
        abs(a.origin.x - b.origin.x) < 0.5 &&
        abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.size.width - b.size.width) < 0.5 &&
        abs(a.size.height - b.size.height) < 0.5
    }

    var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == currentDisplayID }
    }

    /// Stay on the current display while expanding, expanded, or collapsing, so the animation doesn't jump to another display
    private func targetScreen(for mode: AppState.OverlayMode) -> NSScreen? {
        let isOpenOrClosing = mode == .expanded || appState.overlayMode == .expanded || pendingShrink != nil
        if isOpenOrClosing, let screen = currentScreen {
            return screen
        }
        return preferredScreen()
    }

    /// The wings only take the space menus and status bar icons leave on either side of the notch: those belong to other apps, and the system only lays them out around the notch and can't be pushed aside
    private func liveActivityWings(on screen: NSScreen) -> IslandWings {
        let room = MenuBarSpace.shared.roomBesideNotch(on: screen)
        return NotchMetrics.liveActivityWings(leadingRoom: room.leading, trailingRoom: room.trailing, notch: screen.notchSize)
    }

    /// Panel position: flush with the top edge of the screen, horizontally centered; with a notch, the top half of the island hides right inside it
    private func windowFrame(for mode: AppState.OverlayMode, section: AppState.IslandSection, wings: IslandWings, screen: NSScreen) -> NSRect {
        var size = NotchMetrics.islandSize(
            expanded: mode == .expanded,
            section: section,
            notch: screen.notchSize,
            wings: wings,
            largeDisplay: screen.isLargeDisplay,
            nonNotchHeight: settingsStore.get(SettingsDefaults.nonNotchHeight)
        )
        if mode == .expanded {
            // Leave headroom for the expansion spring's bounce so it isn't clipped by the panel edge
            size.width += 2 * NotchMetrics.overshootMargin
            size.height += NotchMetrics.overshootMargin
        }

        // ✅ Use screen.frame rather than visibleFrame: screen.frame includes the notch and menu bar area
        let fullFrame = screen.frame
        // When collapsed the wings differ in width, so the panel shifts toward the wider side
        let offset = NotchMetrics.islandOffset(expanded: mode == .expanded, notch: screen.notchSize, wings: wings)
        return NSRect(
            x: fullFrame.midX + offset - size.width / 2,
            y: fullFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
