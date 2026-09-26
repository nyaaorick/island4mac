//
//  MarqueeText.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-17.
//

import SwiftUI

struct IslandMarqueeText: View {
    @Binding var text: String
    var font: Font = .body
    var nsFont: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var textColor: Color = .primary
    var minDuration: TimeInterval = 3.0
    var frameWidth: CGFloat
    
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .onAppear {
                    calculateTextWidth()
                    startMarqueeIfNeeded()
                }
                .onChange(of: text) { _, _ in
                    offset = 0
                    isAnimating = false
                    calculateTextWidth()
                    startMarqueeIfNeeded()
                }
                // The island moved to a display where the pill is wider (or narrower): the text may fit now, or not
                .onChange(of: frameWidth) { _, _ in
                    offset = 0
                    isAnimating = false
                    startMarqueeIfNeeded()
                }
        }
        .frame(width: frameWidth)
        .clipped()
        .mask(
            HStack(spacing: 0) {
                LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
                Rectangle().fill(Color.black)
                LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
            }
        )
    }
    
    private func calculateTextWidth() {
        let attributes: [NSAttributedString.Key: Any] = [.font: nsFont]
        let size = (text as NSString).size(withAttributes: attributes)
        textWidth = size.width
    }
    
    private func startMarqueeIfNeeded() {
        guard textWidth > frameWidth else {
            return
        }
        
        guard !isAnimating else { return }
        isAnimating = true
        
        let distance = textWidth + 20 // Add some padding
        let duration = max(minDuration, TimeInterval(distance / 30.0))
        
        withAnimation(.linear(duration: 1.0)) {
            offset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // The text or the width changed in the meantime and it fits now
            guard isAnimating else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -distance
            }
        }
    }
}
