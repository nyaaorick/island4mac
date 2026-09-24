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
    private let appState = AppState()
    private let settingsStore = SettingsDefaults.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MANAGERS
    private var nowPlayingManager: NowPlayingManager!
    private var mouseTrackingMonitor: Any?
    
    // MARK: - Frame / Layout Stability (防止 Update Constraints 递归)
    private var isTransitioning = false
    private let transitionLock = NSLock()
    private var frameUpdateWorkItem: DispatchWorkItem?
    private let frameDebounceInterval: TimeInterval = 0.05 // 50ms
    private var lastTargetFrame: NSRect = .zero
    private var lastMouseCheckTime: Date = .distantPast
    
    private var compactSize: CGSize {
        CGSize(width: 185, height: settingsStore.get(SettingsDefaults.nonNotchHeight))
    }
    private let expandedWidth: CGFloat = 640
    
    private override init() {
        super.init()
        setupManagers() // INITIALIZE MUSIC STREAM
        setupPanel()
        setupObservers()
        
        // Initial position
        requestFrameUpdate(animated: false)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func getAppState() -> AppState { return appState }
    
    private func setupManagers() {
        // Initialize NowPlaying Stream
        nowPlayingManager = NowPlayingManager()
        
        // Connect to MusicManager
        Task { @MainActor in
            MusicManager.shared.connectToNowPlayingManager(nowPlayingManager)
        }
    }
    
    private func setupPanel() {
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: compactSize.width, height: compactSize.height),
            styleMask: [.borderless],  // ✅ 移除 .nonactivatingPanel
            backing: .buffered,
            defer: false
        )
        
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

        // ✅ 关键：避免 AutoLayout ↔︎ setFrame 互相触发导致的递归更新
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
        
        panel.contentView = hostingView
        panel.delegate = self
    }
    
    private func setupObservers() {
        appState.$overlayMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestFrameUpdate(animated: true)
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestFrameUpdate(animated: false)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestFrameUpdate(animated: false)
            }
            .store(in: &cancellables)
        
        // ✨ 双屏幕支持：如果启用了自动切换，监听鼠标移动跟随到不同屏幕
        if settingsStore.get(SettingsDefaults.automaticallySwitchDisplay) {
            setupMouseTracking()
        }
    }
    
    private func setupMouseTracking() {
        mouseTrackingMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self else { return }
            // ✅ 节流：每 1 秒最多检查一次屏幕切换
            let now = Date()
            guard now.timeIntervalSince(self.lastMouseCheckTime) > 1.0 else { return }
            self.lastMouseCheckTime = now
            
            let newScreen = ScreenManager.activeScreenContainingMouse()
            if newScreen !== self.panel.screen {
                self.requestFrameUpdate(animated: true)
            }
        }
    }
    
    func reposition() {
        requestFrameUpdate(animated: false)
    }

    // MARK: - Safe Frame Updates

    private func requestFrameUpdate(animated: Bool) {
        frameUpdateWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let screen = self.preferredScreen() else { return }
            let targetFrame = self.calculateFrame(for: self.appState.overlayMode, screen: screen)
            self.applyFrameSafely(targetFrame, animated: animated)
        }

        frameUpdateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + frameDebounceInterval, execute: work)
    }

    private func applyFrameSafely(_ targetFrame: NSRect, animated: Bool) {
        // 1) 防止递归: 如果正在更新 frame，直接跳过
        transitionLock.lock()
        if isTransitioning {
            transitionLock.unlock()
            return
        }
        isTransitioning = true
        transitionLock.unlock()

        // 2) 防重复: 目标 frame 基本一致则跳过
        if framesAreEffectivelyEqual(targetFrame, lastTargetFrame) {
            transitionLock.lock(); isTransitioning = false; transitionLock.unlock()
            return
        }
        lastTargetFrame = targetFrame

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.appState.updateNotchRegion(targetFrame)
            self.transitionLock.lock()
            self.isTransitioning = false
            self.transitionLock.unlock()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                // ✨ 付费级动画: 更流畅、更精致的过渡
                // 展开时使用较慢的速度，让用户能看清楰动画
                // 收起时快速干脆，不拖泥带水
                context.duration = (appState.overlayMode == .expanded) ? 0.5 : 0.32
                // ✅ 使用 ease-out quint 曲线，更加自然的缓出效果
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                DispatchQueue.main.async { finish() }
            }
        } else {
            panel.setFrame(targetFrame, display: true)
            finish()
        }
    }

    private func framesAreEffectivelyEqual(_ a: NSRect, _ b: NSRect) -> Bool {
        // 允许 0.5pt 的浮动，避免浮点抖动导致重复 setFrame
        abs(a.origin.x - b.origin.x) < 0.5 &&
        abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.size.width - b.size.width) < 0.5 &&
        abs(a.size.height - b.size.height) < 0.5
    }

    private func preferredScreen() -> NSScreen? {
        // 优先：有刘海的屏幕（MacBook 内屏）
        if let notchScreen = NSScreen.screens.first(where: { $0.hasNotch }) {
            return notchScreen
        }

        // 其次：根据设置自动切换到鼠标所在屏幕
        if settingsStore.get(SettingsDefaults.automaticallySwitchDisplay) {
            return ScreenManager.activeScreenContainingMouse() ?? NSScreen.main
        }

        // 最后：主屏
        return NSScreen.main
    }
    
    private func calculateFrame(for mode: AppState.OverlayMode, screen: NSScreen) -> NSRect {
        let width: CGFloat = (mode == .expanded) ? expandedWidth : compactSize.width
        let height: CGFloat = (mode == .expanded) ? 320 : compactSize.height

        // ✅ 使用 screen.frame 而不是 visibleFrame，确保定位在刘海正下方
        // screen.frame 包含刘海和菜单栏区域
        // visibleFrame 是减去菜单栏之后的可用区域
        let fullFrame = screen.frame
        let x = fullFrame.midX - (width / 2)
        
        // ⚠️ 关键：定位在屏幕顶部（刘海区域下方），而不是 visibleFrame 顶部（菜单栏下方）
        // 如果有刘海，则紧贴刘海下方；否则在屏幕顶部边缘
        let notchHeight: CGFloat = screen.hasNotch ? screen.safeAreaInsets.top : 0
        let y = fullFrame.maxY - notchHeight - height - 2
        
        return NSRect(x: x, y: y, width: width, height: height)
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
