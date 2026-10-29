import AppKit
import Combine

/// What the island shows as playing: one track, picked from every plugin that reports one in the plugin protocol's
/// `media` (the bundled Music plugin, and others such as a Spotify or YouTube one). The player views, the music beside
/// the notch, the track-change peek and the full-screen video check all read it here. A playing source wins over
/// a paused one, then the one that changed last. Taps on the controls go back to whichever it came from
@MainActor
final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()

    /// Where a track comes from
    enum Source: Hashable {
        case plugin(String)
    }

    struct NowPlaying: Equatable {
        let source: Source
        var media: PluginMedia
        var lyrics: [PluginLyricLine]
    }

    @Published private(set) var current: NowPlaying?
    /// The current track's artwork (or its app's icon), loaded by the island
    @Published private(set) var albumArt: NSImage = NowPlayingStore.placeholderArtwork
    /// The artwork's average color, for tinting
    @Published private(set) var avgColor: NSColor = .white

    /// Every source's track, and when it last changed
    private var tracks: [Source: (playing: NowPlaying, changed: Date)] = [:]
    private var plugins: PluginStore?
    private var cancellables = Set<AnyCancellable>()
    private var artworkTask: Task<Void, Never>?

    /// Set for a plugin's own tab: only that source's track
    let only: Source?

    private static var placeholderArtwork: NSImage { NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)! }

    /// `only` limits it to one source, for the player in a plugin's tab
    init(only: Source? = nil) {
        self.only = only
    }

    /// Starts listening to plugins' `media` and `lyrics`
    func start(plugins: PluginStore) {
        self.plugins = plugins
        cancellables.removeAll()
        plugins.$contents
            .sink { [weak self] contents in
                MainActor.assumeIsolated { self?.updatePlugins(contents) }
            }
            .store(in: &cancellables)
    }

    /// A source's track, or nil when it plays nothing
    func update(_ media: PluginMedia?, lyrics: [PluginLyricLine], from source: Source) {
        if let only, source != only { return }
        if let media {
            let playing = NowPlaying(source: source, media: media, lyrics: lyrics)
            guard tracks[source]?.playing != playing else { return }
            tracks[source] = (playing, Date())
        } else {
            guard tracks.removeValue(forKey: source) != nil else { return }
        }
        pick()
    }

    private func updatePlugins(_ contents: [String: PluginStore.Content]) {
        for (pluginID, content) in contents {
            update(content.media, lyrics: content.lyrics, from: .plugin(pluginID))
        }
        // A plugin that stopped, or cleared everything, plays nothing
        for case .plugin(let pluginID) in tracks.keys where contents[pluginID]?.media == nil {
            update(nil, lyrics: [], from: .plugin(pluginID))
        }
    }

    private func pick() {
        let next = tracks.values
            .max { a, b in
                if a.playing.media.playing != b.playing.media.playing { return !a.playing.media.playing }
                return a.changed < b.changed
            }?.playing
        guard next != current else { return }
        let artworkChanged = next?.media.artwork != current?.media.artwork || next?.media.app != current?.media.app
        current = next
        if artworkChanged { loadArtwork() }
    }

    private func loadArtwork() {
        artworkTask?.cancel()
        let media = current?.media
        artworkTask = Task {
            var image: NSImage?
            if let artwork = media?.artwork {
                image = await PluginImageLoader.shared.image(for: artwork, size: 300)
            }
            if image == nil, let app = media?.app {
                image = await PluginImageLoader.shared.image(for: .app(app), size: 300)
            }
            guard !Task.isCancelled else { return }
            albumArt = image ?? Self.placeholderArtwork
            avgColor = albumArt.averageColor
        }
    }

    // MARK: - What the views read

    var isPlayerIdle: Bool { current == nil }
    var songTitle: String { current?.media.title ?? "" }
    var artistName: String { current?.media.artist ?? "" }
    var isPlaying: Bool { current?.media.playing ?? false }
    /// Seconds; 0 when unknown
    var songDuration: Double { current?.media.duration ?? 0 }
    var playbackRate: Double { isPlaying ? current?.media.rate ?? 1 : 0 }
    /// The app that plays it
    var bundleIdentifier: String? { current?.media.app }
    var hasSyncedLyrics: Bool { current?.lyrics.contains { $0.time != nil } ?? false }
    /// Lyrics without times, as text
    var plainLyrics: String { current?.lyrics.plainText ?? "" }

    func estimatedPlaybackPosition(at date: Date) -> Double {
        current?.media.position(at: date) ?? 0
    }

    func lyricLine(at time: Double) -> String {
        current?.lyrics.line(at: time) ?? ""
    }

    /// Whether the collapsed island shows the now-playing live activity
    var showsCompactLiveActivity: Bool {
        SettingsDefaults.shared.get(SettingsDefaults.showMusicLiveActivity) && !isPlayerIdle
    }

    // MARK: - Controls, sent where the track comes from

    func togglePlay() { control("playPause") }
    func nextTrack() { control("next") }
    func previousTrack() { control("previous") }

    func seek(to position: Double) {
        guard var playing = current else { return }
        guard case .plugin(let pluginID) = playing.source else { return }
        plugins?.send(.seek(position), to: pluginID)
        // Shown at once, while the player catches up
        playing.media.elapsed = max(0, position)
        playing.media.at = Date().timeIntervalSince1970
        update(playing.media, lyrics: playing.lyrics, from: playing.source)
    }

    private func control(_ command: String) {
        guard case .plugin(let pluginID) = current?.source else { return }
        plugins?.send(.control(command), to: pluginID)
    }
}
