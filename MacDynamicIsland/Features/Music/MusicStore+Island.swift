import Foundation

extension MusicStore {
    /// The app's built-in Music, keeping its artwork in the Music plugin's data folder
    static let shared = MusicStore(
        artworkFolder: PluginStore.defaultDataFolder.appendingPathComponent("music/Artwork", isDirectory: true),
        settings: Settings(lyricsSource: SettingsDefaults.shared.get(SettingsDefaults.lyricsSource)))
}
