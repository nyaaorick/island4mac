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
        // ✅ 移除 .nonactivatingPanel 以支持完整的用户交互（包括拖放）
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: backingStoreType, defer: flag)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false

        // ✅ 彻底移除阴影：确保所有层都不渲染阴影
        self.invalidateShadow()

        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
    }

    // ✅ 关键修复：允许窗口接收键盘焦点以支持拖放操作
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
    /// 正在播放（暂停超过 1 秒才算停）
    private var musicIsPlaying = false

    private override init() {
        super.init()
        setupManagers() // INITIALIZE MUSIC STREAM
        mainIsland = IslandWindow(appState: appState, nowPlayingManager: nowPlayingManager) { [weak self] in
            self?.mainIslandScreen()
        }
        setupObservers()
        // 首次摆放推迟到下一轮 runloop：init 发生在 App 的 @StateObject 初始化里，也就是 SwiftUI 更新途中，
        // 此时改动 hosting view 或 appState 会触发 “setting value during update” 崩溃
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

    private func islandUnderMouse() -> IslandWindow? {
        guard let display = ScreenManager.activeScreenContainingMouse()?.displayID else { return nil }
        return islands.first { $0.currentDisplayID == display }
    }

    private func setupManagers() {
        // Initialize NowPlaying Stream
        nowPlayingManager = NowPlayingManager()

        // 单元测试寄宿在 App 里运行：不连接音乐模块，免得测试给播放器发 Apple Event、弹授权框
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

        // 暂停就收起播放两翼（停 1 秒再收，切歌时的短暂停顿不算），鼠标移到刘海上时再露出来
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

        // 有无播放内容变化时，收起状态的岛要伸出或收回
        // 播放信息会被周期性地重复赋值，只关心“有没有内容”是否变化
        MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .map { title, artist in !(title.isEmpty && artist.isEmpty) }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // Claude Code 开始工作、等你授权或刚完成时，两翼同样要伸出；结束后收回
        AgentSessionStore.shared.$liveSession
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // 前台 App 的菜单或状态栏图标变了，两翼重新按刘海两边留下的空位伸出
        MenuBarSpace.shared.didChange
            .sink { [weak self] _ in
                self?.updateAllIslands()
            }
            .store(in: &cancellables)

        // 接上或拔掉显示器
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.scheduleIslandSync()
            }
            .store(in: &cancellables)

        // Agent 的问题或权限确认处理完（在岛上或终端里）后，把因它展开的岛收回去
        AgentSessionStore.shared.$pendingPrompts
            .map(\.isEmpty)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] noneLeft in
                if noneLeft { self?.closeAfterAgentPrompts() }
            }
            .store(in: &cancellables)

        // 多屏：鼠标移到另一块屏幕时，岛跟过去（“自动切换显示器”设置在回调里判断，改设置不用重启）
        setupMouseTracking()
    }

    private func setupMouseTracking() {
        // 全局监听收不到本 App 窗口上的事件，所以本地也监听一份；拖文件时只有 dragged 事件
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

    /// 开着“自动切换显示器”时跟随鼠标所在的屏幕，否则放在设置里选的屏幕；没选或它没接上时放在有刘海的内建屏幕（没有就用主屏）
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

    /// 设置和显示器变化在 willSet 时通知，等新值生效后再重新安排各块屏幕上的岛
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

    /// 打开“所有屏幕”时，主岛以外的每块屏幕各放一个岛；关掉或屏幕拔掉时收走
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

    func showTemporarily(duration: TimeInterval = 1.5) {
        show()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            for island in self.islands where island.appState.overlayMode == .compact {
                island.appState.isOverlayVisible = false
            }
        }
    }
}
