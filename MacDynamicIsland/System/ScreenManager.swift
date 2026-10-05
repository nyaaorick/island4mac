import Cocoa

enum ScreenManager {
    /// Detect the screen containing the mouse cursor
    static func activeScreenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { frame($0.frame, contains: mouse) }
    }

    /// Edges count as inside: at the very top of a screen the cursor reports y == frame.maxY,
    /// which CGRect.contains excludes, and that is exactly where the island is
    static func frame(_ frame: CGRect, contains point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// The display the island belongs on. Following the mouse, that's the display under the cursor
    /// (or the one it's already on when the cursor is on none); otherwise the display chosen in Settings
    /// while it's connected, else the built-in display with the notch, or the main display when there is none (lid closed).
    static func islandDisplay(
        followsMouse: Bool,
        mouseDisplay: CGDirectDisplayID?,
        currentDisplay: CGDirectDisplayID?,
        chosenDisplay: CGDirectDisplayID?,
        builtInDisplay: CGDirectDisplayID?,
        mainDisplay: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if followsMouse, let display = mouseDisplay ?? currentDisplay {
            return display
        }
        return chosenDisplay ?? builtInDisplay ?? mainDisplay
    }

    /// Displays that get an island of their own besides the one on `primary`: every other display with "all screens" on
    static func otherIslandDisplays(allScreens: Bool, displays: [CGDirectDisplayID], primary: CGDirectDisplayID?) -> [CGDirectDisplayID] {
        allScreens ? displays.filter { $0 != primary } : []
    }
}
