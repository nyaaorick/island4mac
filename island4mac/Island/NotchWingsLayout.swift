import SwiftUI

/// Collapsed content around the notch: the primary item in the left wing and the secondary one in the right.
/// With room on one side only, the primary item goes there, and the secondary one beside it if the left has room for both.
struct NotchWingsLayout<Primary: View, Secondary: View>: View {
    let notch: CGSize
    let wings: IslandWings
    /// Content of a wing, given the wing's width
    @ViewBuilder let primary: (_ width: CGFloat) -> Primary
    @ViewBuilder let secondary: (_ width: CGFloat) -> Secondary

    var body: some View {
        HStack(spacing: 0) {
            if wings.trailing == 0, wings.leading >= 2 * NotchMetrics.minWingWidth {
                let half = wings.leading / 2
                primary(half).frame(width: half)
                secondary(half).frame(width: half)
            } else if wings.leading > 0 {
                primary(wings.leading).frame(width: wings.leading)
            }

            // Hidden behind the camera housing
            Color.clear
                .frame(width: notch.width)

            if wings.trailing > 0 {
                Group {
                    if wings.leading > 0 { secondary(wings.trailing) } else { primary(wings.trailing) }
                }
                .frame(width: wings.trailing)
            }
        }
    }
}
