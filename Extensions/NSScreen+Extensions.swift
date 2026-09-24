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
}
