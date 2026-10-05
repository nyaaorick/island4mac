import Foundation

/// What's playing, from a plugin (protocol 5): data only. The island draws it with its own player (artwork,
/// lyrics, progress, controls, spectrum), runs the progress itself from `elapsed`, `at` and `rate`, and sends
/// taps on the controls back as PluginEvent.control and .seek. Also how the island knows what plays, to hide for
/// a full-screen video of that app (`app`). Shared with the Music plugin, which makes it (MusicStore)
///
///     {"type":"media","title":"Song","artist":"Artist","album":"Album","artwork":{"url":"https://…/cover.jpg"},
///      "app":"com.spotify.client","playing":true,"elapsed":42.0,"at":1767225600.0,"duration":215.0,"rate":1.0}
struct PluginMedia: Decodable, Equatable {
    var title: String
    var artist: String?
    var album: String?
    var artwork: PluginImage?
    /// The bundle id of the app that plays it
    var app: String?
    var playing: Bool
    /// Seconds into the track, as of `at`
    var elapsed: Double?
    /// When `elapsed` was true (seconds since 1970); now if it doesn't say
    var at: Double?
    /// Seconds; unknown if missing
    var duration: Double?
    /// 1 is normal speed; the island counts at it while playing
    var rate: Double?

    /// Where playback is at `date`: counted on from `elapsed` while playing, never past the end
    func position(at date: Date) -> Double {
        let start = elapsed ?? 0
        guard playing, let at else { return clamped(start) }
        let rate = rate ?? 1
        return clamped(start + max(0, date.timeIntervalSince1970 - at) * rate)
    }

    private func clamped(_ position: Double) -> Double {
        guard let duration else { return max(position, 0) }
        return min(max(position, 0), duration)
    }
}

/// One line of a track's lyrics (protocol 5, `{"type":"lyrics","lines":[{"time":12.3,"text":"…"}]}`). Lines with a
/// time follow the song; without, they show as plain lyrics
struct PluginLyricLine: Decodable, Equatable {
    var time: Double?
    var text: String

    /// A track has at most this many lines
    static let maxCount = 1000
}

extension Array where Element == PluginLyricLine {
    /// Timed lines, in order
    var synced: [PluginLyricLine] { filter { $0.time != nil }.sorted { $0.time! < $1.time! } }

    /// The timed line at `time`: the last one that has started
    func line(at time: Double) -> String {
        synced.last { $0.time! <= time }?.text ?? ""
    }

    /// All of it as text, for lyrics without times
    var plainText: String { map(\.text).joined(separator: "\n") }
}
