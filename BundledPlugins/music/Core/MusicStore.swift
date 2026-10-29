import Foundation
import Combine
import CryptoKit
import AppKit

/// What the system says is playing (NowPlayingClient), turned into the plugin protocol's `media` and `lyrics`:
/// the very data the Music plugin will send, which the island draws with its own player (NowPlayingStore). It
/// finds the lyrics and, when the player gives none, the artwork. No SwiftUI, no pictures and no settings
/// lookups in here: artwork is a file, an app icon or a URL (PluginImage), and the settings are handed in
@MainActor
final class MusicStore: ObservableObject {
    struct Settings: Equatable {
        /// "auto", "lrclib" or "netease"
        var lyricsSource = "auto"
    }

    @Published private(set) var media: PluginMedia?
    @Published private(set) var lyrics: [PluginLyricLine] = []

    var settings: Settings
    /// Artwork the player gave, as files (named by their contents), so it can be a PluginImage
    let artworkFolder: URL

    private var client: NowPlayingClient?
    private var stateChanges: AnyCancellable?
    private var lyricsTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    init(artworkFolder: URL, settings: Settings = Settings()) {
        self.artworkFolder = artworkFolder
        self.settings = settings
    }

    // MARK: - Lifecycle

    func connect(to client: NowPlayingClient) {
        self.client = client
        stateChanges = client.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.update(from: state) }
            }
        client.start()
    }

    func stop() {
        client?.stop()
    }

    // MARK: - Playback control (PluginEvent.control and .seek)

    /// "playPause", "next" or "previous"
    func control(_ command: String) {
        switch command {
        case "playPause": client?.playPause()
        case "next": client?.nextTrack()
        case "previous": client?.previousTrack()
        default: break
        }
    }

    func seek(to position: Double) {
        // MediaRemote seeking works for any app that takes part in the system's media controls
        client?.seek(to: position)
        // Shown at once, while the player catches up
        guard var media else { return }
        media.elapsed = max(0, position)
        media.at = Date().timeIntervalSince1970
        self.media = media
    }

    // MARK: - From the system's now playing

    func update(from state: NowPlayingState) {
        guard state.hasContent else {
            clear()
            return
        }
        let trackChanged = state.title != media?.title || state.artist != (media?.artist ?? "")
        let app = state.sourceApp.isEmpty ? nil : state.sourceApp

        var next = PluginMedia(
            title: state.title,
            artist: state.artist,
            album: state.album.isEmpty ? nil : state.album,
            artwork: trackChanged ? nil : media?.artwork,
            app: app,
            playing: state.isPlaying,
            // MediaRemote reports the elapsed time as of positionTimestamp, not as of now
            elapsed: state.position,
            at: state.positionTimestamp.timeIntervalSince1970,
            duration: state.duration > 0 ? state.duration : (trackChanged ? nil : media?.duration),
            rate: state.playbackRate)

        if let data = state.artworkData, let file = saveArtwork(data) {
            next.artwork = .file(file.path)
        } else if trackChanged {
            // Artwork often arrives a moment after the title; until then the app's icon shows
            next.artwork = app.map(PluginImage.app)
            artworkTask?.cancel()
            // Songs usually carry an album; videos don't, and a song search would find unrelated covers for them
            if !state.album.isEmpty { findArtwork(title: state.title, artist: state.artist) }
        }
        media = next

        if trackChanged {
            lyricsTask?.cancel()
            lyrics = []
            let album = next.album
            lyricsTask = Task { await self.findLyrics(title: state.title, artist: state.artist, album: album, app: app) }
        }
    }

    private func clear() {
        guard media != nil else { return }
        lyricsTask?.cancel()
        artworkTask?.cancel()
        media = nil
        lyrics = []
    }

    // MARK: - Artwork

    /// Writes the player's artwork to a file named by its contents, keeping only the current one
    private func saveArtwork(_ data: Data) -> URL? {
        let name = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined() + ".img"
        let file = artworkFolder.appendingPathComponent(name)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: file.path) { return file }
        try? fileManager.createDirectory(at: artworkFolder, withIntermediateDirectories: true)
        for old in (try? fileManager.contentsOfDirectory(atPath: artworkFolder.path)) ?? [] {
            try? fileManager.removeItem(at: artworkFolder.appendingPathComponent(old))
        }
        return (try? data.write(to: file, options: .atomic)) == nil ? nil : file
    }

    /// The cover from the iTunes Search API, when the player gives none; also its length when the player doesn't say
    private func findArtwork(title: String, artist: String) {
        artworkTask = Task {
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                URLQueryItem(name: "term", value: "\(title) \(artist)"),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "1"),
            ]
            guard let url = components?.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let small = first["artworkUrl100"] as? String,
                  // 600 × 600 rather than 100 × 100
                  let cover = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
                  !Task.isCancelled else { return }
            // Still the same track, still without the player's own artwork
            guard var media, media.title == title else { return }
            if case .file = media.artwork { return }
            media.artwork = .url(cover)
            if media.duration == nil, let milliseconds = first["trackTimeMillis"] as? Double, milliseconds > 0 {
                media.duration = milliseconds / 1000
            }
            self.media = media
        }
    }

    // MARK: - Lyrics

    /// Synced lyrics online first (they follow the song), then Apple Music's own, which are plain text
    private func findLyrics(title: String, artist: String, album: String?, app: String?) async {
        var lines: [PluginLyricLine] = []
        if let result = await LyricsClient.shared.fetchLyrics(title: title, artist: artist, album: album, source: settings.lyricsSource) {
            lines = result.syncedLyrics.isEmpty
                ? Self.plainLines(result.plainText)
                : result.syncedLyrics.map { PluginLyricLine(time: $0.timeInSeconds, text: $0.line) }
        }
        // Most streamed songs have none in Music (an empty string comes back and must not count as found)
        if lines.allSatisfy({ $0.time == nil }), !Task.isCancelled, app == "com.apple.Music",
           let own = await Self.appleMusicLyrics(), !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines = Self.plainLines(own)
        }
        // After a track change, the old request's result is dropped
        guard !Task.isCancelled else { return }
        lyrics = Array(lines.prefix(PluginLyricLine.maxCount))
    }

    /// Lyrics without times, a line each, with any leftover time tags taken out
    static func plainLines(_ text: String) -> [PluginLyricLine] {
        var lines = text.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { PluginLyricLine(text: $0.trimmingCharacters(in: .whitespaces)) }
        while lines.first?.text.isEmpty == true { lines.removeFirst() }
        while lines.last?.text.isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func appleMusicLyrics() async -> String? {
        await AppleScriptClient.execute("""
            tell application "Music"
                try
                    return lyrics of current track
                end try
                return ""
            end tell
            """)
    }
}
