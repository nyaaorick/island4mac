//
//  NSScreen+Extensions.swift
//  Mac灵动岛
//
//  Stage 1: Screen utilities for multi-display support
//

import AppKit

extension NSScreen {
    /// CoreGraphics display ID; stable while the display stays connected, unlike NSScreen instances
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Identifies the display across reconnects and restarts, unlike displayID; what Settings remembers
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    
    /// Check if screen has a notch
    var hasNotch: Bool {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top > 0
        }
        return false
    }
    
    /// Get notch height for screen
    var notchHeight: CGFloat {
        if #available(macOS 12.0, *) {
            return safeAreaInsets.top
        }
        return 0
    }

    /// Size of the camera housing (notch), or .zero if the screen has none
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return .zero }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }

    /// The Mac's own display, as opposed to an external one
    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// An external display with room for the wider island (see NotchMetrics.isLargeDisplay)
    var isLargeDisplay: Bool {
        NotchMetrics.isLargeDisplay(width: frame.width, notch: notchSize, isBuiltIn: isBuiltIn)
    }
}
