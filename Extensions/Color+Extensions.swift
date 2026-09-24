//
//  Color+Extensions.swift
//  Mac灵动岛
//
//  Stage 1: Color utilities from boringNotch
//

import SwiftUI
import AppKit

extension Color {
    /// Ensure minimum brightness for readability
    func ensureMinimumBrightness(factor: Double = 0.6) -> Color {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else { return self }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        if brightness < CGFloat(factor) {
            brightness = CGFloat(factor)
        }
        
        return Color(nsColor: NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha))
    }
}
