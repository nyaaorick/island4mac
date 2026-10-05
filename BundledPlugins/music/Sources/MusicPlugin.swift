import Foundation
import Combine
import IslandKit

/// Now playing in the island, as a plugin that ships inside the app. Its logic is the shared MusicCore: the
/// system's now playing (read through the MediaRemote adapter beside the app's Frameworks), lyrics and artwork.
/// It hands the island what plays as `media`, and the island draws its own player; taps on the player come back
/// here. It runs in the background, so music shows beside the notch whether or not its tab is open
@main
struct MusicPlugin: IslandPlugin {
    static let id = "music"
    static let name = "Music"
    static let symbol = "music.note"
    static let version = "1.0.0"
    static let description: String? = "What plays on your Mac, with synced lyrics"
    /// Music shows beside the notch, and the island stays out of a full-screen video, whether or not the Music tab
    /// is one of yours
    static let background = true

    @Preference("Lyrics from", options: ["auto", "lrclib", "netease"]) var lyricsSource = "auto"

    private var store: MusicStore { MusicService.shared.store }

    func onStart() {
        MusicService.shared.start()
    }

    var body: some IslandContent {
        let _ = MusicService.shared.apply(MusicStore.Settings(lyricsSource: lyricsSource))
        if let media = store.media {
            Media(media.title, artist: media.artist, album: media.album, artwork: media.artwork.map(Self.image), app: media.app,
                  playing: media.playing, elapsed: media.elapsed, at: Date(timeIntervalSince1970: media.at ?? Island.now.timeIntervalSince1970),
                  duration: media.duration, rate: media.rate,
                  lyrics: store.lyrics.map { LyricLine($0.text, at: $0.time) },
                  control: { store.control($0.rawValue) },
                  seek: { store.seek(to: $0) })
        }
    }

    private static func image(_ image: PluginImage) -> IslandImage {
        switch image {
        case .file(let path): return .file(path)
        case .app(let bundleID): return .app(bundleID)
        case .url(let url): return .url(url.absoluteString)
        }
    }
}

/// The now-playing reader, for as long as the plugin runs
@MainActor
final class MusicService {
    static let shared = MusicService()

    let store = MusicStore(artworkFolder: (Island.dataDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("music"))
        .appendingPathComponent("Artwork", isDirectory: true))
    private var changes: AnyCancellable?

    func start() {
        changes = store.objectWillChange.sink { _ in Island.refresh() }
        // This program is in the app's Contents/Helpers, the adapter in its Contents/Frameworks
        let program = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let adapter = program.resolvingSymlinksInPath().deletingLastPathComponent()
            .appendingPathComponent("../Frameworks/libMediaRemoteAdapter.dylib").standardizedFileURL
        store.connect(to: NowPlayingClient(adapterURL: adapter))
    }

    func apply(_ settings: MusicStore.Settings) {
        if store.settings != settings { store.settings = settings }
    }
}
