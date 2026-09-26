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
    // 所有动效都由 SwiftUI 弹簧驱动：SwiftUI 画布尺寸固定、在屏幕上的位置固定，
    // 面板只是它的取景框。展开前面板先瞬间变大，收起时等弹簧停稳再瞬间缩回，
    // 所以 AppKit 既不做动画，也不会在动画中途触发 SwiftUI 重新布局。
    private var pendingShrink: DispatchWorkItem?
    private var pendingShrinkTarget: NSRect?
    private var windowUpdateScheduled = false
    /// 岛当前所在的显示器
    private(set) var currentDisplayID: CGDirectDisplayID?
    /// 收起弹簧（response 0.45，临界阻尼）在这个时间内停稳
    private let settleDelay: TimeInterval = 0.6

    init(appState: AppState, nowPlayingManager: NowPlayingManager, preferredScreen: @escaping () -> NSScreen?) {
        self.appState = appState
        self.preferredScreen = preferredScreen

        panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless],  // ✅ 移除 .nonactivatingPanel
            backing: .buffered,
            defer: false
        )

        // 先告诉视图当前屏幕的刘海尺寸和大小，避免首帧按无刘海、非大屏布局
        if let screen = preferredScreen() {
            appState.notchSize = screen.notchSize
            appState.isOnLargeDisplay = screen.isLargeDisplay
            currentDisplayID = screen.displayID
        }

        let rootView = NotchHomeView()
            // App 在后台时，点岛的第一下会激活窗口；默认这一下不交给按钮和点按手势，要点两次才有反应
            .allowsWindowActivationEvents()
            .environmentObject(appState)
            .environmentObject(appState.clipboardHub)
            .environmentObject(nowPlayingManager)
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
        // 面板可能左右不对称地变大变小，画布由 layoutCanvas 按屏幕位置摆放，不随面板自动伸缩
        hostingView.autoresizingMask = []
        // 挂进窗口之前就定好尺寸：此时容器宽高为 0，画布贴顶居中
        let canvas = NotchMetrics.canvasSize(notch: appState.notchSize, largeDisplay: appState.isOnLargeDisplay)
        hostingView.frame = NSRect(x: -canvas.width / 2, y: -canvas.height, width: canvas.width, height: canvas.height)

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hostingView)

        self.hostingView = hostingView
        panel.contentView = container

        setupObservers()
    }

    /// Takes the island off screen for good (its display went away, or "all screens" was turned off)
    func close() {
        pendingShrink?.cancel()
        cancellables.removeAll()
        panel.orderOut(nil)
    }

    private func setupObservers() {
        // 新值存好后（didSet）同步调整面板，保证 SwiftUI 渲染展开（或切到更大的分区）的第一帧时面板已经够大。
        // 不能用 @Published 的发布者：它在 willSet 发出，此时改面板会让 SwiftUI 按旧值布局，新值要等下一个事件才显示出来
        appState.islandSizeDidChange
            .compactMap { [weak appState] in appState.map { ($0.overlayMode, $0.currentSection) } }
            .removeDuplicates { $0 == $1 }
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

        // 暂停的音乐只在鼠标停在刘海上时露出来
        appState.$isPeekingNotch
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleWindowUpdate()
            }
            .store(in: &cancellables)
    }

    func reposition() {
        updateWindowFrame(for: appState.overlayMode, section: appState.currentSection)
    }

    // MARK: - Panel Frame

    /// 合并 willSet 阶段发出的变化，等新值生效后再算一次
    func scheduleWindowUpdate() {
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
        // 大外接屏上的岛更宽，画布也跟着变
        let largeDisplay = screen.isLargeDisplay
        if appState.notchSize != notchSize || appState.isOnLargeDisplay != largeDisplay {
            appState.notchSize = notchSize
            appState.isOnLargeDisplay = largeDisplay
            layoutCanvas()
        }
        let showsMusic = MusicManager.shared.showsCompactLiveActivity && (musicIsPlaying || appState.isPeekingNotch)
        let showsLiveActivity = showsMusic || AgentSessionStore.shared.showsCompactLiveActivity
        let wings = showsLiveActivity ? liveActivityWings(on: screen) : .none
        // 有东西要显示在刘海旁时持续测量：状态栏图标会变宽、会增减（只有带刘海的屏幕要让位）
        if notchSize != .zero {
            MenuBarSpace.shared.isWatching = showsLiveActivity
        }
        let target = windowFrame(for: mode, section: section, wings: wings, screen: screen)

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
        if appState.liveActivityWings != wings {
            appState.liveActivityWings = wings
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

    /// 画布：展开后的岛加上弹簧回弹余量，贴住面板顶边，水平方向正对刘海（屏幕中线）；
    /// 收起的岛两翼宽度不一时面板左右不对称，所以不能按面板居中
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
        // 允许 0.5pt 的浮动，避免浮点抖动导致重复 setFrame
        abs(a.origin.x - b.origin.x) < 0.5 &&
        abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.size.width - b.size.width) < 0.5 &&
        abs(a.size.height - b.size.height) < 0.5
    }

    var currentScreen: NSScreen? {
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

    /// 两翼只占菜单和状态栏图标在刘海两边留下的空位：它们归别的 App，系统只会绕开刘海排，推不开
    private func liveActivityWings(on screen: NSScreen) -> IslandWings {
        let room = MenuBarSpace.shared.roomBesideNotch(on: screen)
        return NotchMetrics.liveActivityWings(leadingRoom: room.leading, trailingRoom: room.trailing, notch: screen.notchSize)
    }

    /// 面板位置：紧贴屏幕顶边、水平居中；有刘海时岛的上半部分正好藏在刘海里
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
            // 留出展开弹簧回弹的余量，避免回弹被面板边缘截掉
            size.width += 2 * NotchMetrics.overshootMargin
            size.height += NotchMetrics.overshootMargin
        }

        // ✅ 使用 screen.frame 而不是 visibleFrame：screen.frame 包含刘海和菜单栏区域
        let fullFrame = screen.frame
        // 收起时两翼宽度不一，面板随之偏向宽的一边
        let offset = NotchMetrics.islandOffset(expanded: mode == .expanded, notch: screen.notchSize, wings: wings)
        return NSRect(
            x: fullFrame.midX + offset - size.width / 2,
            y: fullFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
