import AppKit
import SwiftUI

/// Look of the island's background, picked under Settings > Appearance
enum IslandTheme: String, CaseIterable, Identifiable {
    /// Solid color, black by default: the island is exactly as dark as the notch it grows out of
    case standard = "default"
    /// Black down to the bottom of the camera housing, then the system's Liquid Glass, like Control Center
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return L("settings.appearance.theme.default")
        case .glass: return L("settings.appearance.theme.glass")
        }
    }

    var summary: String {
        switch self {
        case .standard: return L("settings.appearance.theme.default_help")
        case .glass: return L("settings.appearance.theme.glass_help")
        }
    }
}

/// Fills the island behind its content. NotchHomeView clips it to the notch outline; under the Glass theme
/// it only covers the camera housing and fades out over the IslandGlass drawn behind it
struct IslandBackground: View {
    let theme: IslandTheme
    /// Background color of the default theme
    let color: Color
    /// Height of the camera housing: the Glass theme stays solid black this far down so the notch never shows
    let solidHeight: CGFloat

    /// How far below the camera housing the black takes to clear into the glass
    static let fadeLength: CGFloat = 28

    /// Black easing out along a smoothstep curve: no visible line where the fade starts or ends
    private static let fadeStops: [Gradient.Stop] = (0...8).map { step in
        let t = Double(step) / 8
        return .init(color: .black.opacity(1 - t * t * (3 - 2 * t)), location: t)
    }

    var body: some View {
        switch theme {
        case .standard:
            color
        case .glass:
            VStack(spacing: 0) {
                Color.black
                    .frame(height: solidHeight)
                LinearGradient(stops: Self.fadeStops, startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeLength)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// The system's Liquid Glass (NSGlassEffectView, the material behind Control Center), sampling whatever is
/// behind the panel. Always dark, like Control Center in dark mode, so the island's white text stays readable
/// over a light window: the panel (OverlayPanel) is dark whatever the system appearance, and so is this view.
/// It is drawn as the island's body (the notch outline without its top flares); the black of IslandBackground
/// covers its top edge
struct IslandGlass: NSViewRepresentable {
    let cornerRadius: CGFloat

    private static let dark = NSAppearance(named: .darkAqua)

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.appearance = Self.dark
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.appearance = Self.dark
        view.cornerRadius = cornerRadius
    }
}
