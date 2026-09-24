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
@MainActor
final class OverlayWindowController: NSResponder, NSWindowDelegate {

    static let shared = OverlayWindowController()

    private var panel: OverlayPanel!
    private var hostingView: NSView!
    private let appState = AppState()
    private let settingsStore = SettingsDefaults.shared
    private var cancellables = Set<AnyCancellable>()

    // MANAGERS
    private var nowPlayingManager: NowPlayingManager!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    // MARK: - Frame Management
    // 所有动效都由 SwiftUI 弹簧驱动：SwiftUI 画布尺寸固定、在屏幕上的位置固定，
    // 面板只是它的取景框。展开前面板先瞬间变大，收起时等弹簧停稳再瞬间缩回，
    // 所以 AppKit 既不做动画，也不会在动画中途触发 SwiftUI 重新布局。
    private var pendingShrink: DispatchWorkItem?
    private var pendingShrinkTarget: NSRect?
    private var windowUpdateScheduled = false
    private var lastMouseCheckTime: Date = .distantPast
    /// 岛当前所在的显示器
    private var currentDisplayID: CGDirectDisplayID?
    /// 收起弹簧（response 0.45，临界阻尼）在这个时间内停稳
    private let settleDelay: TimeInterval = 0.6

    private override init() {
        super.init()
        setupManagers() // INITIALIZE MUSIC STREAM
        setupPanel()
        setupObservers()
        // 首次摆放推迟到下一轮 runloop：init 发生在 App 的 @StateObject 初始化里，也就是 SwiftUI 更新途中，
        // 此时改动 hosting view 或 appState 会触发 “setting value during update” 崩溃
        scheduleWindowUpdate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func getAppState() -> AppState { return appState }

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

    private func setupPanel() {
        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],  // ✅ 移除 .nonactivatingPanel
            backing: .buffered,
            defer: false
        )

        // 先告诉视图当前屏幕的刘海尺寸，避免首帧按无刘海布局
        if let screen = preferredScreen() {
            appState.notchSize = screen.notchSize
            currentDisplayID = screen.displayID
        }

        let rootView = NotchHomeView()
            .environmentObject(appState)
            .environmentObject(appState.clipboardHub)
            .environmentObject(nowPlayingManager!)
            .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        // ✅ 确保 NSHostingView 及其 layer 不产生阴影
        hostingView.shadow = nil
        hostingView.layer?.shadowOpacity = 0
        hostingView.layer?.shadowRadius = 0
        hostingView.layer?.shadowOffset = .zero

        // ✅ 关键：画布尺寸固定，不让 SwiftUI 内容反过来约束窗口，也就不会有 AutoLayout ↔︎ setFrame 递归
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        // 面板变大变小时，画布保持贴住顶边、水平居中
        hostingView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        // 挂进窗口之前就定好尺寸：此时容器宽高为 0，画布贴顶居中
        let canvas = NotchMetrics.canvasSize(notch: appState.notchSize)
        hostingView.frame = NSRect(x: -canvas.width / 2, y: -canvas.height, width: canvas.width, height: canvas.height)

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hostingView)

        self.hostingView = hostingView
        panel.contentView = container
        panel.delegate = self
    }

    private func setupObservers() {
        // @Published 在 willSet 时发出：直接用新值，并且同步调整面板，
        // 保证 SwiftUI 渲染展开（或切到更大的分区）的第一帧时面板已经够大。订阅时的首个值跳过，初始摆放由 init 负责
        appState.$overlayMode
            .combineLatest(appState.$currentSection)
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] mode, section in
                self?.updateWindowFrame(for: mode, section: section)
            }
            .store(in: &cancellables)

        appState.$isOverlayVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible {
                    self.panel.orderFront(nil)
                } else {
                    self.panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        // Settings changes can affect sizing (e.g. nonNotchHeight)
        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
            }
            .store(in: &cancellables)

        // 开始/停止播放时，收起状态的岛要在刘海两侧伸出或收回
        // 播放信息会被周期性地重复赋值，只关心“有没有在播”是否变化
        MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .map { title, artist in !(title.isEmpty && artist.isEmpty) }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
            }
            .store(in: &cancellables)

        // Claude Code 开始工作、等你授权或刚完成时，两翼同样要伸出；结束后收回
        AgentSessionStore.shared.$liveSession
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
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
        guard settingsStore.get(SettingsDefaults.automaticallySwitchDisplay) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMouseCheckTime) > 0.1 else { return }
        lastMouseCheckTime = now

        if let screen = ScreenManager.activeScreenContainingMouse(), screen.displayID != currentDisplayID {
            scheduleWindowUpdate()
        }
    }

    func reposition() {
        updateWindowFrame(for: appState.overlayMode, section: appState.currentSection)
    }

    // MARK: - Panel Frame

    /// 合并 willSet 阶段发出的变化，等新值生效后再算一次
    private func scheduleWindowUpdate() {
        guard !windowUpdateScheduled else { return }
        windowUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowUpdateScheduled = false
            self.updateWindowFrame(for: self.appState.overlayMode, section: self.appState.currentSection)
        }
    }

    /// 变大立即生效，给岛留出动画空间；变小等岛的弹簧停稳后再执行
    private func updateWindowFrame(for mode: AppState.OverlayMode, section: AppState.IslandSection) {
        guard let screen = targetScreen(for: mode) else { return }
        currentDisplayID = screen.displayID
        let notchSize = screen.notchSize
        if appState.notchSize != notchSize {
            appState.notchSize = notchSize
            layoutCanvas()
        }
        let showsLiveActivity = MusicManager.shared.showsCompactLiveActivity || AgentSessionStore.shared.showsCompactLiveActivity
        let target = windowFrame(for: mode, section: section, showsLiveActivity: showsLiveActivity, screen: screen)

        // 目标没变：别打断已经排好的缩小，否则频繁的更新会让面板一直缩不回去
        if let pending = pendingShrinkTarget, framesAreEffectivelyEqual(pending, target) {
            return
        }
        pendingShrink?.cancel()
        pendingShrink = nil
        pendingShrinkTarget = nil

        // 同一块屏幕上：先覆盖岛现在和将要占的全部区域
        let current = panel.frame
        let immediate = current.intersects(screen.frame) ? current.union(target) : target
        setPanelFrame(immediate)

        // 面板已经够大，再让视图伸出播放两翼
        if appState.showsLiveActivity != showsLiveActivity {
            appState.showsLiveActivity = showsLiveActivity
        }

        guard !framesAreEffectivelyEqual(immediate, target) else { return }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShrink = nil
            self.pendingShrinkTarget = nil
            self.setPanelFrame(target)
            // 收起期间鼠标可能已经换了屏幕，现在停稳了再跟过去
            self.scheduleWindowUpdate()
        }
        pendingShrink = shrink
        pendingShrinkTarget = target
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: shrink)
    }

    private func setPanelFrame(_ frame: NSRect) {
        if !framesAreEffectivelyEqual(frame, panel.frame) {
            // 不强制立即重绘：画布在屏幕上的位置不变，下一次正常刷新即可
            panel.setFrame(frame, display: false)
            layoutCanvas()
        }
        appState.updateNotchRegion(frame)
    }

    /// 画布：展开后的岛加上弹簧回弹余量，固定贴在面板顶部正中
    private func layoutCanvas() {
        guard let container = panel.contentView else { return }
        let size = NotchMetrics.canvasSize(notch: appState.notchSize)
        let bounds = container.bounds
        let frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height,
            width: size.width,
            height: size.height
        )
        if !framesAreEffectivelyEqual(frame, hostingView.frame) {
            hostingView.frame = frame
        }
    }

    private func framesAreEffectivelyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        // 允许 0.5pt 的浮动，避免浮点抖动导致重复 setFrame
        abs(a.origin.x - b.origin.x) < 0.5 &&
        abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.size.width - b.size.width) < 0.5 &&
        abs(a.size.height - b.size.height) < 0.5
    }

    private var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.displayID == currentDisplayID }
    }

    /// 展开中、已展开或正在收起时留在当前屏幕，免得动画跳到另一块屏幕上
    private func targetScreen(for mode: AppState.OverlayMode) -> NSScreen? {
        let isOpenOrClosing = mode == .expanded || appState.overlayMode == .expanded || pendingShrink != nil
        if isOpenOrClosing, let screen = currentScreen {
            return screen
        }
        return preferredScreen()
    }

    /// 开着“自动切换显示器”时跟随鼠标所在的屏幕，否则固定在有刘海的内建屏幕（没有就用主屏）
    private func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let display = ScreenManager.islandDisplay(
            followsMouse: settingsStore.get(SettingsDefaults.automaticallySwitchDisplay),
            mouseDisplay: ScreenManager.activeScreenContainingMouse()?.displayID,
            currentDisplay: currentScreen?.displayID,
            builtInDisplay: screens.first(where: \.hasNotch)?.displayID,
            mainDisplay: NSScreen.main?.displayID
        )
        return screens.first { $0.displayID == display } ?? NSScreen.main
    }

    /// 面板位置：紧贴屏幕顶边、水平居中；有刘海时岛的上半部分正好藏在刘海里
    private func windowFrame(for mode: AppState.OverlayMode, section: AppState.IslandSection, showsLiveActivity: Bool, screen: NSScreen) -> NSRect {
        var size = NotchMetrics.islandSize(
            expanded: mode == .expanded,
            section: section,
            notch: screen.notchSize,
            showsLiveActivity: showsLiveActivity,
            nonNotchHeight: settingsStore.get(SettingsDefaults.nonNotchHeight)
        )
        if mode == .expanded {
            // 留出展开弹簧回弹的余量，避免回弹被面板边缘截掉
            size.width += 2 * NotchMetrics.overshootMargin
            size.height += NotchMetrics.overshootMargin
        }

        // ✅ 使用 screen.frame 而不是 visibleFrame：screen.frame 包含刘海和菜单栏区域
        let fullFrame = screen.frame
        return NSRect(
            x: fullFrame.midX - size.width / 2,
            y: fullFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func show() { appState.isOverlayVisible = true }
    func hide() { appState.isOverlayVisible = false }

    func showTemporarily(duration: TimeInterval = 1.5) {
        show()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self else { return }
            if self.appState.overlayMode == .compact {
                self.hide()
            }
        }
    }
}
