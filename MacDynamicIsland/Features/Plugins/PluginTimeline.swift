import SwiftUI

/// Gives its content a plugin's text and progress as of now: once a second while it counts down
/// ({"until": …}), once otherwise
struct PluginTimeline<Content: View>: View {
    let compact: PluginCompact
    @ViewBuilder let content: (_ text: String?, _ progress: Double?) -> Content

    var body: some View {
        if compact.until != nil {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(compact.displayText(at: timeline.date), compact.displayProgress(at: timeline.date))
            }
        } else {
            content(compact.text, compact.progress)
        }
    }
}
