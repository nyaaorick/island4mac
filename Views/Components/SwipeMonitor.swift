import SwiftUI

enum SwipeDirection: Equatable {
    case up, down
}

/// Turns the scroll deltas of one two-finger swipe into a single up or down. Fires once per swipe, so the
/// island opens or closes with its normal spring instead of following the fingers
struct SwipeTracker {
    /// How far the fingers travel, in points, before it counts as a swipe
    static let distance: CGFloat = 24
    /// A swipe has to be this much more vertical than horizontal
    static let verticalBias: CGFloat = 1.5

    private var vertical: CGFloat = 0
    private var horizontal: CGFloat = 0
    private var fired = false

    /// Call when the fingers touch down
    mutating func begin() {
        vertical = 0
        horizontal = 0
        fired = false
    }

    /// Adds finger movement (positive `dy` is fingers moving down); returns the swipe once it's long enough
    mutating func add(dx: CGFloat, dy: CGFloat) -> SwipeDirection? {
        guard !fired else { return nil }
        vertical += dy
        horizontal += abs(dx)
        guard abs(vertical) >= Self.distance, abs(vertical) >= horizontal * Self.verticalBias else { return nil }
        fired = true
        return vertical > 0 ? .down : .up
    }
}

/// Where on a display a swipe counts: the top-center third of the screen in each direction, plus the island itself
enum SwipeZone {
    static let fraction: CGFloat = 1.0 / 3

    static func rect(on screen: CGRect, covering panel: CGRect) -> CGRect {
        let size = CGSize(width: screen.width * fraction, height: screen.height * fraction)
        let zone = CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
        return zone.union(panel)
    }
}

/// What is under the pointer when a swipe starts. Scrolling whatever is there comes first: a swipe over another
/// app's window is left to that window, so the island only answers over the desktop, Dock, menu bar or itself
enum SwipeArea {
    /// Ordinary windows (layer 0), this app's own included (Settings), and the floating panels, dialogs and menus
    /// around them can scroll. The desktop (below 0) and the Dock, menu bar and status items (20 to 25) can't.
    /// Swipes over the island's own panel never get here: the app receives those itself
    static func isFree(layer: Int) -> Bool {
        layer < 0 || (20...25).contains(layer)
    }

    /// Whether the topmost window at `point` (AppKit screen coordinates) leaves the swipe to the island
    static func isFree(at point: CGPoint) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // Window bounds count down from the top of the main display; AppKit's points count up from its bottom
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        let displays = NSScreen.screens.compactMap { $0.displayID.map(CGDisplayBounds) }
        // Front to back: the first window containing the point is the one you'd be scrolling
        for window in windows {
            guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.contains(cgPoint) else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            // The Dock keeps a display-sized window above every app to catch clicks; it isn't something you scroll.
            // A real full-screen window is an ordinary one (layer 0)
            if layer > 0, displays.contains(where: { bounds.contains($0) }) { continue }
            return isFree(layer: layer)
        }
        return true
    }
}

/// Reports two-finger trackpad swipes made in this island's swipe zone, over its panel or over an empty part of
/// the screen. Events pass through untouched. A swipe that would scroll something (another app's window, or one
/// of the island's own lists) is left to that and doesn't open or close the island
struct SwipeMonitor: NSViewRepresentable {
    let onSwipe: (SwipeDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }

    final class Coordinator {
        var onSwipe: (SwipeDirection) -> Void
        private weak var view: NSView?
        /// Scrolls sent to this app's windows, and to other apps (which the island can watch but not take)
        private var monitors: [Any] = []
        private var tracker = SwipeTracker()
        /// The swipe in progress began outside the zone or where it scrolls something, so it isn't ours
        private var ignored = false

        init(onSwipe: @escaping (SwipeDirection) -> Void) {
            self.onSwipe = onSwipe
        }

        func install(on view: NSView) {
            remove()
            self.view = view
            if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
                self?.handle(event, isLocal: true)
                return event
            }) {
                monitors.append(local)
            }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
                self?.handle(event, isLocal: false)
            }) {
                monitors.append(global)
            }
        }

        func remove() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
        }

        private func handle(_ event: NSEvent, isLocal: Bool) {
            // Trackpad only: a mouse wheel has no phases, and momentum after the fingers lift isn't part of the swipe
            guard let window = view?.window, window.isVisible,
                  event.hasPreciseScrollingDeltas, !event.phase.isEmpty, event.momentumPhase.isEmpty else { return }
            // Scrolls in this app's other windows (Settings) or another island's panel aren't for this island
            if isLocal, event.window !== window { return }

            if event.phase.contains(.began) {
                tracker.begin()
                // Scrolls sent to this app are over the island: only its lists can scroll. The others go to whatever is there
                let wouldScroll = isLocal ? Self.isOverScrollView(event, in: window) : !SwipeArea.isFree(at: NSEvent.mouseLocation)
                ignored = wouldScroll || !Self.inZone(of: window)
            }
            guard !ignored else { return }

            // With natural scrolling the content follows the fingers, so a positive delta is fingers moving down
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            if let swipe = tracker.add(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY * direction) {
                onSwipe(swipe)
            }
        }

        /// The pointer is where a swipe counts for this island; checked when the fingers touch down
        private static func inZone(of window: NSWindow) -> Bool {
            guard let screen = window.screen else { return false }
            return SwipeZone.rect(on: screen.frame, covering: window.frame).contains(NSEvent.mouseLocation)
        }

        private static func isOverScrollView(_ event: NSEvent, in window: NSWindow) -> Bool {
            var view = window.contentView?.superview?.hitTest(event.locationInWindow)
            while let current = view {
                if current is NSScrollView { return true }
                view = current.superview
            }
            return false
        }
    }
}
