import AppKit
import ApplicationServices
import Combine

/// How much of the menu bar beside the notch is free: the frontmost app's menus and the status icons
/// belong to other apps, and macOS lays them out around the notch only, so nothing can push them aside.
/// The collapsed island fits itself into the gaps they leave instead. Reading them needs Accessibility permission.
@MainActor
final class MenuBarSpace {
    static let shared = MenuBarSpace()

    /// Sent when the menus or status icons move, so the island can fit itself again
    let didChange = PassthroughSubject<Void, Never>()

    /// Horizontal extent of each top-level menu, from the left edge of the display showing them; nil when unknown
    var menuSpans: [ClosedRange<CGFloat>]? {
        didSet { if menuSpans != oldValue { didChange.send() } }
    }
    /// Frames of the status icons in global Accessibility coordinates (top-left origin); nil when unknown
    var statusItemFrames: [CGRect]? {
        didSet { if statusItemFrames != oldValue { didChange.send() } }
    }

    /// Keep measuring while the island shows something beside the notch: status icons change width, come and go,
    /// and move across the notch when the system folds its hidden ones away
    var isWatching = false {
        didSet {
            guard isWatching != oldValue else { return }
            watchTimer?.invalidate()
            watchTimer = nil
            guard isWatching, !BuildConfig.isRunningUnitTests else { return }
            watchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.measure() }
            }
        }
    }

    private var measuredAt: Date = .distantPast
    private var isMeasuring = false
    /// Apps that had status icons at the last full scan; nil: scan every app next time
    private var appsWithStatusItems: Set<pid_t>?
    private var watchTimer: Timer?
    private var observers: [Any] = []
    private var ownerObservation: NSKeyValueObservation?

    private init() {
        // Unit tests run inside the app: they set the spans themselves instead of reading this Mac's menu bar
        guard !BuildConfig.isRunningUnitTests else { return }
        ownerObservation = NSWorkspace.shared.observe(\.menuBarOwningApplication) { [weak self] _, _ in
            Task { @MainActor in self?.measureNowAndAgainShortly() }
        }
        // Apps add their status icons when they launch and take them away when they quit
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.appsWithStatusItems = nil
                    self?.measureNowAndAgainShortly()
                }
            })
        }
        measure()
    }

    /// Free width left and right of the notch on `screen`, up to the nearest menu or status icon; nil where it isn't known
    func roomBesideNotch(on screen: NSScreen) -> (leading: CGFloat?, trailing: CGFloat?) {
        let notch = screen.notchSize
        guard notch != .zero else { return (nil, nil) }
        if Date().timeIntervalSince(measuredAt) > 1 { measure() }
        guard menuSpans != nil || statusItemFrames != nil else { return (nil, nil) }

        // Status icons in this display's menu bar, from its left edge
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let menuBar = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: notch.height)
        let items = Self.visible((statusItemFrames ?? [])
            .filter { menuBar.contains(CGPoint(x: $0.midX, y: $0.midY)) }
            .map { ($0.minX - screen.frame.minX)...($0.maxX - screen.frame.minX) })

        let notchMinX = (screen.frame.width - notch.width) / 2
        let room = Self.room(beside: notchMinX...(notchMinX + notch.width), obstacles: (menuSpans ?? []) + items,
                             displayWidth: screen.frame.width)
        // Without the status icons the right side can't be judged. Accessibility only reports them where the menu bar
        // is active, so on another display there are none to go by
        return (room.leading, items.isEmpty ? nil : room.trailing)
    }

    /// Status icons actually showing. Icons folded away behind the system's hidden-items chevron still report a frame,
    /// stacked on each other and on the chevron; a showing icon only ever touches the next one
    nonisolated static func visible(_ items: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        let sorted = items.sorted { $0.lowerBound < $1.lowerBound }
        return sorted.indices.filter { index in
            index == sorted.count - 1 || sorted[index].upperBound - sorted[index + 1].lowerBound <= 4
        }.map { sorted[$0] }
    }

    /// Room between the notch and the nearest obstacle on each side (menus that don't fit before the notch continue after it)
    nonisolated static func room(beside notch: ClosedRange<CGFloat>, obstacles: [ClosedRange<CGFloat>],
                                 displayWidth: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let leftEnd = obstacles.filter { $0.lowerBound < notch.lowerBound }.map(\.upperBound).max() ?? 0
        let rightStart = obstacles.filter { $0.upperBound > notch.upperBound }.map(\.lowerBound).min() ?? displayWidth
        return (max(0, notch.lowerBound - leftEnd), max(0, rightStart - notch.upperBound))
    }

    private func measureNowAndAgainShortly() {
        measure()
        // Some apps only fill in their menus once they are in front, and add status icons a moment after launching
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            measure()
        }
    }

    private func measure() {
        guard !isMeasuring, !BuildConfig.isRunningUnitTests, AXIsProcessTrusted() else { return }
        isMeasuring = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Our own app has no menus of its own in the menu bar; keep the last app's while it's in front
        let menuOwner = NSWorkspace.shared.menuBarOwningApplication.map(\.processIdentifier).flatMap { $0 == ownPID ? nil : $0 }
        let scanned = appsWithStatusItems.map(Array.init) ?? NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        let isFullScan = appsWithStatusItems == nil
        // Accessibility calls wait on the other apps; keep them off the main thread
        Task.detached(priority: .userInitiated) { [weak self] in
            let menus = menuOwner.map { Self.frames(of: kAXMenuBarAttribute, in: [$0]).frames }
            let statusItems = Self.frames(of: "AXExtrasMenuBar", in: scanned)
            await self?.finishMeasuring(menus: menus, statusItems: statusItems, isFullScan: isFullScan)
        }
    }

    private func finishMeasuring(menus: [CGRect]?, statusItems: (frames: [CGRect], apps: Set<pid_t>), isFullScan: Bool) {
        isMeasuring = false
        measuredAt = Date()
        if isFullScan { appsWithStatusItems = statusItems.apps }
        statusItemFrames = statusItems.frames
        guard let menus else { return }
        guard let first = menus.min(by: { $0.minX < $1.minX }) else {
            menuSpans = nil
            return
        }
        // The menus start at the left edge of the display showing the active menu bar
        let display = NSScreen.screens.first { $0.frame.minX <= first.minX && first.minX < $0.frame.maxX }
        let origin = display?.frame.minX ?? 0
        menuSpans = menus.map { ($0.minX - origin)...($0.maxX - origin) }
    }

    /// Frames (global, top-left origin) of the items in a menu bar of each app, read in parallel, and the apps that have any
    nonisolated private static func frames(of menuBarAttribute: String, in pids: [pid_t]) -> (frames: [CGRect], apps: Set<pid_t>) {
        let results = FramesCollector()
        DispatchQueue.concurrentPerform(iterations: pids.count) { index in
            let pid = pids[index]
            let app = AXUIElementCreateApplication(pid)
            // A busy app must not keep the island waiting
            AXUIElementSetMessagingTimeout(app, 0.3)
            guard let bar: AXUIElement = attribute(menuBarAttribute, of: app),
                  let items: [AXUIElement] = attribute(kAXChildrenAttribute, of: bar) else { return }
            let frames = items.compactMap { item -> CGRect? in
                guard let position: AXValue = attribute(kAXPositionAttribute, of: item),
                      let size: AXValue = attribute(kAXSizeAttribute, of: item) else { return nil }
                var origin = CGPoint.zero
                var extent = CGSize.zero
                guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent),
                      extent.width > 0 else { return nil }
                return CGRect(origin: origin, size: extent)
            }
            results.add(frames, from: pid)
        }
        return results.result
    }

    nonisolated private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// Gathers frames from the parallel Accessibility reads
private nonisolated final class FramesCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [CGRect] = []
    private var apps: Set<pid_t> = []

    func add(_ newFrames: [CGRect], from pid: pid_t) {
        guard !newFrames.isEmpty else { return }
        lock.withLock {
            frames += newFrames
            apps.insert(pid)
        }
    }

    var result: (frames: [CGRect], apps: Set<pid_t>) {
        lock.withLock { (frames, apps) }
    }
}
