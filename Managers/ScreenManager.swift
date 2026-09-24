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
    /// (or the one it's already on when the cursor is on none); otherwise the built-in display with
    /// the notch, or the main display when there is none (lid closed).
    static func islandDisplay(
        followsMouse: Bool,
        mouseDisplay: CGDirectDisplayID?,
        currentDisplay: CGDirectDisplayID?,
        builtInDisplay: CGDirectDisplayID?,
        mainDisplay: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if followsMouse, let display = mouseDisplay ?? currentDisplay {
            return display
        }
        return builtInDisplay ?? mainDisplay
    }

    /// Detect the screen containing the frontmost application
    static func activeScreenForFrontmostApp() -> NSScreen? {
        guard NSScreen.screens.first != nil else { return nil }
        // Heuristic: use screen containing most of the frontmost app's windows
        // For now, simpler approach: use screen where mouse is, or main screen
        return activeScreenContainingMouse() ?? NSScreen.main
    }

    /// Get all connected screens
    static func allConnectedScreens() -> [NSScreen] {
        return NSScreen.screens
    }

    /// Get primary/main screen
    static func mainScreen() -> NSScreen? {
        return NSScreen.main
    }

    /// Determine the active screen based on display mode
    /// - activeOnly: use screen containing mouse, fallback to main
    /// - mainOnly: always use main screen
    static func activeScreen(displayMode: DisplayMode = .activeOnly) -> NSScreen? {
        switch displayMode {
        case .mainOnly:
            return mainScreen()
        case .activeOnly:
            return activeScreenContainingMouse() ?? mainScreen()
        }
    }
}

enum DisplayMode {
    case mainOnly        // Always show overlay on main/primary screen
    case activeOnly      // Show overlay on active screen (where mouse is)
}
