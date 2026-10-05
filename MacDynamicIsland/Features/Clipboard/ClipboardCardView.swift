import SwiftUI

// MARK: - ClipboardCardView (Premium Horizontal UI)
struct ClipboardCardView: View {
    let item: ClipboardItem
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // HEADER
                HStack(spacing: 6) {
                    Image(nsImage: item.sourceIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .cornerRadius(4)
                    
                    Text(item.sourceAppName ?? "Unknown")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(item.relativeTime).font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                }
                
                // CENTER
                ZStack {
                    if item.type == .image, let data = item.imageData, let img = NSImage(data: data) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 140, height: 80)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        Text(item.content)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(height: 80)
                .padding(10)
                .islandInset(cornerRadius: 10)
                
                // FOOTER
                Text("Click to Paste")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
            .frame(width: 170, height: 160)
            .islandTile(cornerRadius: 16, highlighted: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
