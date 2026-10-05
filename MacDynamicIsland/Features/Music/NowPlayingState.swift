import Foundation
import AppKit

// MARK: - IslandNowPlayingState (Globally Unique)
struct IslandNowPlayingState: Equatable {
    let isPlaying: Bool
    let playbackRate: Double
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    /// Elapsed time as of `positionTimestamp`
    let position: TimeInterval
    let positionTimestamp: Date
    /// Bundle identifier of the app that owns the session
    let sourceApp: String
    var artworkData: Data?

    static let idle = Self(
        isPlaying: false,
        playbackRate: 0,
        title: "",
        artist: "",
        album: "",
        duration: 0,
        position: 0,
        positionTimestamp: .distantPast,
        sourceApp: "",
        artworkData: nil
    )

    var hasContent: Bool { !title.isEmpty || !artist.isEmpty }
}
