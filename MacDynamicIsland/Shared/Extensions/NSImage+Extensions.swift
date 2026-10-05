//
//  NSImage+Extensions.swift
//  MacDynamicIsland
//
//  Stage 1: Image utilities for color extraction
//

import AppKit
import CoreImage

extension NSImage {
    /// Extract average color from image (for album art tinting)
    var averageColor: NSColor {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSColor.gray
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let extentVector = CIVector(x: ciImage.extent.origin.x,
                                     y: ciImage.extent.origin.y,
                                     z: ciImage.extent.size.width,
                                     w: ciImage.extent.size.height)
        
        guard let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: ciImage,
                                                  kCIInputExtentKey: extentVector]) else {
            return NSColor.gray
        }
        
        guard let outputImage = filter.outputImage else {
            return NSColor.gray
        }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: nil)
        
        return NSColor(red: CGFloat(bitmap[0]) / 255.0,
                      green: CGFloat(bitmap[1]) / 255.0,
                      blue: CGFloat(bitmap[2]) / 255.0,
                      alpha: CGFloat(bitmap[3]) / 255.0)
    }
}
