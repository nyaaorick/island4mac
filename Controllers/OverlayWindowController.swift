import Cocoa
import SwiftUI
import Combine

// MARK: - OverlayPanel (Pixel-Perfect Boring Notch Setup)
final class OverlayPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        // ✅ Removed .nonactivatingPanel to support full user interaction (including drag and drop)
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: backingStoreType, defer: flag)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        // The island is dark in every system appearance: white text on black or on the Glass theme's glass.
        // Under a light system appearance the glass would otherwise come back light (washed out, the text
        // unreadable) from the second time the island opens
        self.appearance = NSAppearance(named: .darkAqua)

        // ✅ Shadow removed entirely: make sure no layer renders one
        self.invalidateShadow()

        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
    }

    // ✅ Key fix: allow the window to receive keyboard focus so drag and drop works
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - OverlayWindowController
/// Keeps the islands: the main one on the display you chose (or under the mouse, with "automatically switch display"),
/// and with "all screens" on, one more on every other display. Everything outside that asks for "the" island
/// (hotkeys, the clipboard, Settings) gets the main one.
@MainActor
final class OverlayWindowController: NSObject {

    static let shared = OverlayWindowController()

    private let appState = AppState()
    private let settingsStore = SettingsDefaults.shared
    private var cancellables = Set<AnyCancellable>()

    // MANAGERS
    private var nowPlayingManager: NowPlayingManager!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    private var mainIsland: IslandWindow!
    /// With "all screens" on: an island on each display other than the main island's
    private var otherIslands: [CGDirectDisplayID: IslandWindow] = [:]
    private var islands: [IslandWindow] { [mainIsland] + otherIslands.values }

    private var islandSyncScheduled = false
    private var lastMouseCheckTime: Date = .distantPast
    /// Now playing (only counts as stopped after being paused for over 1 second)
    private var musicIsPlaying = false

    /// The app you were using before a click on an island brought this one to the front (the panel has to become
    /// key for text fields and drops). The keyboard goes back to it when the island closes, and pastes go into it
    private(set) var previousApp: NSRunningApplication?

    private override init() {
        super.init()
        setupManagers() // INITIALIZE MUSIC STREAM
        mainIsland = IslandWindow(appState: appState, nowPlayingManager: nowPlayingManager) { [weak self] in
            self?.mainIslandScreen()
        }
        setupObservers()
        // First placement is deferred to the next runloop turn: init runs inside the app's @StateObject initialization, i.e. in the middle of a SwiftUI update,
        // and changing the hosting view or appState then triggers a "setting value during update" crash
        scheduleIslandSync()
    }

    func getAppState() -> AppState { return appState }
    /// The main island's panel, the one hotkeys and the clipboard open
    var mainPanel: NSWindow { mainIsland.panel }

    /// Opens the island on the Agents tab, where you can answer an agent's question or permission prompt:
    /// the island on the display you're working on
    func showAgentPrompt() {
        guard settingsStore.get(SettingsDefaults.agentPromptsOpenIsland) else { return }
        let state = islandUnderMouse()?.appState ?? appState
        // Don't pull the open island away from a tab you're using
        if state.overlayMode == .expanded && state.islandFrame.contains(NSEvent.mouseLocation) { return }
        state.currentSection = .agents
        withAnimation(boringOpenAnimation) {
            state.activateOverlay(reason: .agentPrompt)
        }
    }

    /// Closes the islands a prompt opened once no prompt is left, unless the pointer is on them
    private func closeAfterAgentPrompts() {
        for state in islands.map(\.appState) {
            guard state.overlayMode == .expanded, state.visibilityReason == .agentPrompt,
                  !state.islandFrame.contains(NSEvent.mouseLocation) else { continue }
            withAnimation(boringCloseAnimation) {
                state.deactivateOverlay()
            }
        }
    }

    /// Gives the keyboard back to the app you were using once the island in `panel` has closed. Not while you're
    /// in another window of this app (Settings, a file dialog, another island), and not when you'd left already
    func returnFocus(from panel: NSWindow) {
        guard NSApp.isActive, let app = previousApp, !app.isTerminated else { return }
        if let key = NSApp.keyWindow, key !== panel { return }
        app.activate(options: [])
    }

    private func islandUnderMouse() -> IslandWindow? {
        guard let display = ScreenManager.activeScreenContainingMouse()?.displayID else { return nil }
        return islands.first { $0.currentDisplayID == display }
    }

    private func setupManagers() {
        // Initialize NowPlaying Stream
        nowPlayingManager = NowPlayingManager()

        // Unit tests are hosted inside the app: don't connect the music module, so tests don't send Apple Events to the player or pop up an authorization dialog
        guard !BuildConfig.isRunningUnitTests else { return }

        // Connect to MusicManager
        Task { @MainActor in
            MusicManager.shared.connectToNowPlayingManager(nowPlayingManager)
        }
    }

    private func setupObservers() {
        // Settings changes can affect sizing (e.g. nonNotchHeight) and which displays get an island
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleIslandSync()
            }
            .store(in: &cancellables)

        // Collapse the playback wings when paused (after 1 second, so the brief pause when switching tracks doesn't count); show them again when the mouse moves onto the notch
        MusicManager.shared.$isPlaying
            .removeDuplicates()
            .map { playing -> AnyPublisher<Bool, Never> in
                playing
                    ? Just(true).eraseToAnyPublisher()
                    : Just(false).delay(for: .seconds(1), scheduler: DispatchQueue.main).eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self else { return }
                self.musicIsPlaying = playing
                self.islands.forEach { $0.musicIsPlaying = playing }
            }
            .store(in: &cancellables)

        // The collapsed island extends or retracts its wings when playback content appears or disappears
        // Playback info is reassigned periodically; only whether there is any content matters
        MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .map { title, artist in !(title.isEmpty && artist.isEmpty) }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // The wings also extend while Claude Code is working, waiting for your approval, or just finished, and retract afterwards
        AgentSessionStore.shared.$liveSession
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // When the frontmost app's menus or status bar icons change, re-extend the wings into the space left on either side of the notch
        MenuBarSpace.shared.didChange
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // A display is connected or disconnected
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.scheduleIslandSync()
            }
            .store(in: &cancellables)

        // Once an agent's question or permission prompt is handled (on the island or in the terminal), collapse the island it expanded
        AgentSessionStore.shared.$pendingPrompts
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] noneLeft in
                if noneLeft { self?.closeAfterAgentPrompts() }
            }
            .store(in: &cancellables)

        // Remember the app you're using: clicking the island brings this app to the front, and the keyboard goes back to that app when the island collapses
        let ownPID = ProcessInfo.processInfo.processIdentifier
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ownPID ? nil : $0 }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.processIdentifier != ownPID }
            .sink { [weak self] app in
                self?.previousApp = app
            }
            .store(in: &cancellables)

        // Multiple displays: when the mouse moves to another display, the island follows (the "Follow mouse across displays" setting is checked in the callback, so changing it needs no restart)
        setupMouseTracking()
    }

    private func setupMouseTracking() {
        // Global monitors don't receive events on this app's own windows, so listen locally too; while dragging files only dragged events arrive
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.followMouseToScreen()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.followMouseToScreen()
            return event
        }
    }

    private func followMouseToScreen() {
        guard followsMouse else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMouseCheckTime) > 0.1 else { return }
        lastMouseCheckTime = now

        if let screen = ScreenManager.activeScreenContainingMouse(), screen.displayID != mainIsland.currentDisplayID {
            mainIsland.scheduleWindowUpdate()
        }
    }

    // MARK: - Displays

    /// With an island on every display there's nothing to follow
    private var followsMouse: Bool {
        settingsStore.get(SettingsDefaults.automaticallySwitchDisplay) && !settingsStore.get(SettingsDefaults.showOnAllDisplays)
    }

    /// With "Follow mouse across displays" on, follows the display the mouse is on; otherwise uses the display chosen in Settings, or the built-in display with the notch (the main display if there is none) when none is chosen or it isn't connected
    private func mainIslandScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let chosenUUID = settingsStore.get(SettingsDefaults.preferredDisplayUUID)
        let display = ScreenManager.islandDisplay(
            followsMouse: followsMouse,
            mouseDisplay: ScreenManager.activeScreenContainingMouse()?.displayID,
            currentDisplay: mainIsland?.currentDisplayID,
            chosenDisplay: chosenUUID.isEmpty ? nil : screens.first { $0.displayUUID == chosenUUID }?.displayID,
            builtInDisplay: screens.first(where: \.hasNotch)?.displayID,
            mainDisplay: NSScreen.main?.displayID
        )
        return screens.first { $0.displayID == display } ?? NSScreen.main
    }

    /// Settings and display changes fire at willSet; wait for the new value to take effect, then rearrange the islands on each display
    private func scheduleIslandSync() {
        guard !islandSyncScheduled else { return }
        islandSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.islandSyncScheduled = false
            self.syncOtherIslands()
            self.updateAllIslands()
        }
    }

    /// With "All displays" on, every display besides the main island's gets its own island; they're removed when it's turned off or a display is unplugged
    private func syncOtherIslands() {
        let wanted = Set(ScreenManager.otherIslandDisplays(
            allScreens: settingsStore.get(SettingsDefaults.showOnAllDisplays),
            displays: NSScreen.screens.compactMap(\.displayID),
            primary: mainIslandScreen()?.displayID
        ))
        for (display, island) in otherIslands where !wanted.contains(display) {
            island.close()
            otherIslands[display] = nil
        }
        for display in wanted where otherIslands[display] == nil {
            let island = IslandWindow(appState: AppState(sharingWith: appState), nowPlayingManager: nowPlayingManager) {
                NSScreen.screens.first { $0.displayID == display }
            }
            island.musicIsPlaying = musicIsPlaying
            otherIslands[display] = island
        }
    }

    private func updateAllIslands() {
        islands.forEach { $0.scheduleWindowUpdate() }
    }

    func reposition() {
        islands.forEach { $0.reposition() }
    }

    func show() { islands.forEach { $0.appState.isOverlayVisible = true } }
    func hide() { islands.forEach { $0.appState.isOverlayVisible = false } }
}
