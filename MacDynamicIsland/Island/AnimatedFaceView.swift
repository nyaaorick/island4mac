import SwiftUI
import Combine

struct AnimatedFaceView: View {
    @State private var isBlinking = false
    @State private var lookOffset = CGSize.zero
    
    // Timer for random blinks
    let blinkTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    // Timer for random looks
    let lookTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            EyeView(isBlinking: isBlinking, lookOffset: lookOffset)
            EyeView(isBlinking: isBlinking, lookOffset: lookOffset)
        }
        .onReceive(blinkTimer) { _ in
            blink()
        }
        .onReceive(lookTimer) { _ in
            lookAround()
        }
    }
    
    private func blink() {
        // Random chance to double blink
        let doubleBlink = Bool.random()
        
        withAnimation(.easeOut(duration: 0.1)) {
            isBlinking = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.1)) {
                isBlinking = false
            }
            
            if doubleBlink {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        isBlinking = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeIn(duration: 0.1)) {
                            isBlinking = false
                        }
                    }
                }
            }
        }
    }
    
    private func lookAround() {
        // 30% chance to look somewhere, otherwise center
        if Int.random(in: 1...100) > 70 {
            let maxOffset: CGFloat = 2.0
            let randomX = CGFloat.random(in: -maxOffset...maxOffset)
            let randomY = CGFloat.random(in: -maxOffset...maxOffset)
            
            withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.7)) {
                lookOffset = CGSize(width: randomX, height: randomY)
            }
            
            // Return to center after a short while
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.7)) {
                    lookOffset = .zero
                }
            }
        }
    }
}

private struct EyeView: View {
    var isBlinking: Bool
    var lookOffset: CGSize
    
    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 8, height: 8) // Small dots like Boring Notch's face
            .scaleEffect(y: isBlinking ? 0.1 : 1.0)
            .offset(lookOffset)
    }
}

struct AnimatedFaceView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            AnimatedFaceView()
        }
        .frame(width: 100, height: 50)
    }
}
