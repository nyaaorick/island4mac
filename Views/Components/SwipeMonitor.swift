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

/// Reports two-finger trackpad swipes made in this island's swipe zone, over its panel or over another app.
/// Events pass through untouched (over another app it scrolls as usual), and a swipe that starts on one of the
/// island's own scrolling lists is left to the list
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
        /// The swipe in progress began outside the zone or on a list, so it isn't ours
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
                ignored = !Self.inZone(of: window) || (isLocal && Self.isOverScrollView(event, in: window))
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
