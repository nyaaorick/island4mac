import Foundation

/// A plugin's countdown ({"until": …, "total": …}), run by the island so the plugin needn't send every second
enum PluginCountdown {
    static func remaining(until: Double, at now: Date) -> TimeInterval {
        max(0, until - now.timeIntervalSince1970)
    }

    /// "04:59" under an hour, "1:04:59" from an hour; whole seconds rounded up, so it reads 00:00 only at the end
    static func text(remaining: TimeInterval) -> String {
        let whole = Int(remaining.rounded(.up))
        let hours = whole / 3600, minutes = whole % 3600 / 60, seconds = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// The share of the countdown left, for the ring; nil without a total
    static func progress(remaining: TimeInterval, total: Double?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(max(remaining / total, 0), 1)
    }
}

extension PluginCompact {
    /// What to show at `now`: the countdown when there is one, else the plugin's text
    func displayText(at now: Date) -> String? {
        guard let until else { return text }
        return PluginCountdown.text(remaining: PluginCountdown.remaining(until: until, at: now))
    }

    func displayProgress(at now: Date) -> Double? {
        guard let until else { return progress }
        return PluginCountdown.progress(remaining: PluginCountdown.remaining(until: until, at: now), total: total) ?? progress
    }
}
