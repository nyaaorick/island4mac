import AppKit
import ApplicationServices
import Combine

/// Displays showing a video in full screen, where the island gets out of the way. The video is whatever
/// Now Playing shows: its app (a player, or the browser a web video plays in) has a window filling the display.
/// Other apps in full screen, like a terminal or an editor, keep their island.
@MainActor
final class FullScreenVideo {
    static let shared = FullScreenVideo()

    /// Sent when the displays change
    let didChange = PassthroughSubject<Void, Never>()
    /// Displays showing a video in full screen now
    private(set) var displays: Set<CGDirectDisplayID> = [] {
        didSet { if displays != oldValue { didChange.send() } }
    }

    private var cancellables = Set<AnyCancellable>()
    /// Looks every few seconds while something plays: not every player switches spaces for full screen
    private var pollTimer: Timer?
    private var recheck: DispatchWorkItem?
    private var isChecking = false
    private var checkAgain = false

    private var isEnabled: Bool { SettingsDefaults.shared.get(SettingsDefaults.hideForFullScreenVideo) }

    private init() {
        // Unit tests run inside the app: they check the geometry directly instead of reading this Mac's windows
        guard !BuildConfig.isRunningUnitTests else { return }

        // Going into full screen or out of it switches spaces, and the window takes a moment to settle
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.checkNowAndAgainShortly()
        }
        .store(in: &cancellables)

        // Another app playing, or nothing playing any more. Sent before the new value is stored
        MusicManager.shared.$bundleIdentifier
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePolling()
            }
            .store(in: &cancellables)

        // The setting turned on or off (also sent before it changes)
        SettingsDefaults.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePolling()
            }
            .store(in: &cancellables)
    }

    /// The displays as the check needs them
    static func displayAreas() -> [DisplayArea] {
        NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayArea(id: $0, frame: screen.frame, notchHeight: screen.safeAreaInsets.top) }
        }
    }

    /// Polls while something plays and the setting is on
    private func updatePolling() {
        let watches = isEnabled && MusicManager.shared.bundleIdentifier != nil
        if watches && pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.check() }
            }
        } else if !watches {
            pollTimer?.invalidate()
            pollTimer = nil
        }
        checkNowAndAgainShortly()
    }

    private func checkNowAndAgainShortly() {
        check()
        recheck?.cancel()
        let again = DispatchWorkItem { [weak self] in
            self?.check()
        }
        recheck = again
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: again)
    }

    private func check() {
        guard isEnabled, let app = MusicManager.shared.bundleIdentifier else {
            displays = []
            return
        }
        guard !isChecking else {
            checkAgain = true
            return
        }
        isChecking = true
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: app).map(\.processIdentifier))
        let areas = Self.displayAreas()
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        // The window list and Accessibility wait on the window server and on the other app: off the main thread
        Task.detached(priority: .utility) { [weak self] in
            let found = Self.displays(showing: pids, in: areas, primaryHeight: primaryHeight)
            await self?.finishChecking(found)
        }
    }

    private func finishChecking(_ found: Set<CGDirectDisplayID>) {
        isChecking = false
        // The setting, or what plays, may have changed in the meantime
        displays = isEnabled && MusicManager.shared.bundleIdentifier != nil ? found : []
        if checkAgain {
            checkAgain = false
            check()
        }
    }

    /// The displays one of the windows of `pids` fills: covering it all, or below the notch in full screen.
    /// `primaryHeight` is the main display's height, where window bounds start counting from the top
    nonisolated static func displays(showing pids: Set<pid_t>, in areas: [DisplayArea], primaryHeight: CGFloat) -> Set<CGDirectDisplayID> {
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var found: Set<CGDirectDisplayID> = []
        for window in windows {
            // Ordinary windows only: not the menu bar, status icons, or panels floating above
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  window[kCGWindowLayer as String] as? Int == 0,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { continue }
            // Window bounds count down from the top of the main display; AppKit's frames count up from its bottom
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            for area in areas where !found.contains(area.id) {
                switch area.coverage(by: frame) {
                case .whole:
                    found.insert(area.id)
                case .belowNotch:
                    // A zoomed window fills that much too when the Dock is hidden; only one in full screen counts
                    if isInFullScreen(pid: pid, bounds: bounds) { found.insert(area.id) }
                case .none:
                    break
                }
            }
        }
        return found
    }

    /// Whether the app's window at `bounds` (global, from the top left, as Accessibility counts too) is in full screen.
    /// Needs Accessibility permission, which the app asks for anyway
    nonisolated private static func isInFullScreen(pid: pid_t, bounds: CGRect) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        // A busy app must not keep the island waiting
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let windows: [AXUIElement] = attribute(kAXWindowsAttribute, of: app) else { return false }
        return windows.contains { window in
            guard let isFullScreen: Bool = attribute("AXFullScreen", of: window), isFullScreen,
                  let position: AXValue = attribute(kAXPositionAttribute, of: window),
                  let size: AXValue = attribute(kAXSizeAttribute, of: window) else { return false }
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return false }
            return abs(origin.x - bounds.minX) < 2 && abs(origin.y - bounds.minY) < 2
                && abs(extent.width - bounds.width) < 2 && abs(extent.height - bounds.height) < 2
        }
    }

    nonisolated private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// A display as the full-screen check sees it
nonisolated struct DisplayArea: Sendable {
    let id: CGDirectDisplayID
    /// In AppKit's coordinates
    let frame: CGRect
    /// Height of the notch, which a window in full screen stays below; 0 without one
    let notchHeight: CGFloat

    /// How much of the display a window (in AppKit's coordinates) fills
    func coverage(by window: CGRect) -> WindowCoverage {
        let slack: CGFloat = 1
        guard window.minX <= frame.minX + slack, window.maxX >= frame.maxX - slack,
              window.minY <= frame.minY + slack else { return .none }
        if window.maxY >= frame.maxY - slack { return .whole }
        if notchHeight > 0 && window.maxY >= frame.maxY - notchHeight - slack { return .belowNotch }
        return .none
    }
}

nonisolated enum WindowCoverage: Equatable, Sendable {
    case none
    /// All of the display below the notch: what a window gets in full screen there
    case belowNotch
    /// The whole display, where the menu bar would be too: a window in full screen on a display without a notch
    case whole
}
