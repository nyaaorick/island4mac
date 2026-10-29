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
/// it is solid only over the camera housing, then a soft black wash over the IslandGlass drawn behind it:
/// fading down from the camera and in from the left and right edges, so the glass reads as framed by the
/// notch's black rather than cut out of it
struct IslandBackground: View {
    let theme: IslandTheme
    /// Background color of the default theme
    let color: Color
    /// Height of the camera housing: the Glass theme stays solid black this far down so the notch never shows
    let solidHeight: CGFloat

    /// Share of the island below the camera housing that the black takes to clear into the glass
    private static let topFadeShare = 0.55
    /// Width of the soft black along the left and right edges
    private static let sideFadeWidth: CGFloat = 36
    /// Black right at the left and right edges
    private static let sideFadeOpacity = 0.5
    /// Black over the whole glass. The clear glass has no dimming of its own: it brightens and refracts what is
    /// behind it, so over a light window it blows out like an overexposed photo and the white text disappears.
    /// Apple pairs clear glass with a dimming layer for this reason
    private static let dimOpacity = 0.35

    var body: some View {
        switch theme {
        case .standard:
            color
        case .glass:
            VStack(spacing: 0) {
                Color.black
                    .frame(height: solidHeight)
                ZStack {
                    Color.black.opacity(Self.dimOpacity)
                    LinearGradient(stops: Self.easedStops(from: 1, over: Self.topFadeShare), startPoint: .top, endPoint: .bottom)
                    HStack(spacing: 0) {
                        LinearGradient(stops: Self.easedStops(from: Self.sideFadeOpacity, over: 1), startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.sideFadeWidth)
                        Spacer(minLength: 0)
                        LinearGradient(stops: Self.easedStops(from: Self.sideFadeOpacity, over: 1), startPoint: .trailing, endPoint: .leading)
                            .frame(width: Self.sideFadeWidth)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Black easing from `opacity` to clear along a smootherstep curve over the first `share` of the gradient:
    /// flat at both ends, so there is no visible line where the fade starts or ends
    private static func easedStops(from opacity: Double, over share: Double) -> [Gradient.Stop] {
        (0...16).map { step in
            let t = Double(step) / 16
            let eased = t * t * t * (t * (t * 6 - 15) + 10)
            return .init(color: .black.opacity(opacity * (1 - eased)), location: t * share)
        } + (share < 1 ? [.init(color: .clear, location: 1)] : [])
    }
}

/// The system's Liquid Glass (NSGlassEffectView, clear style: more see-through than Control Center's), sampling
/// whatever is behind the panel. Always dark, like Control Center in dark mode, so the island's white text stays readable
/// over a light window: the panel (IslandPanel) is dark whatever the system appearance, and so is this view.
/// It is drawn as the island's body (the notch outline without its top flares); the black of IslandBackground
/// covers its top edge
struct IslandGlass: NSViewRepresentable {
    let cornerRadius: CGFloat

    private static let dark = NSAppearance(named: .darkAqua)

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .clear
        view.appearance = Self.dark
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.appearance = Self.dark
        view.cornerRadius = cornerRadius
    }
}
