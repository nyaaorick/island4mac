//
//  MusicManager.swift
//  boringNotch
//
//  Created by Alexander on 2025-08-20.
//

import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
class MusicManager: ObservableObject {
    static let shared = MusicManager()
    
    // MARK: - Published Properties
    
    @Published var songTitle: String = ""
    @Published var artistName: String = ""
    @Published var albumTitle: String = ""
    @Published var albumArt: NSImage = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)! {
        didSet { updateAverageColor(for: albumArt) }
    }
    @Published var avgColor: NSColor = .white
    @Published var isPlaying: Bool = false
    @Published var elapsedTime: Double = 0
    @Published var songDuration: Double = 0
    @Published var playbackRate: Double = 1.0
    @Published var repeatMode: MusicRepeatMode = .off
    @Published var isShuffled: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published var volume: Double = 0.5
    @Published var bundleIdentifier: String? = nil
    @Published var applicationName: String? = nil
    
    // Timestamps
    @Published var timestampDate: Date = Date()
    
    // Controller state
    @Published var isNowPlayingDeprecated: Bool = false
    @Published var volumeControlSupported: Bool = false
    @Published var canFavoriteTrack: Bool = false
    @Published var usingAppIconForArtwork: Bool = false
    
    // Lyrics
    @Published var currentLyrics: String = ""
    @Published var syncedLyrics: [(timeInSeconds: Double, line: String)] = []
    @Published var isFetchingLyrics: Bool = false
    
    // MARK: - Private Properties

    private var activeController: MediaControllerProtocol?
    private var controllers: [MediaControllerProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastState: PlaybackState?
    private var nowPlayingManager: NowPlayingManager?

    private var avgColorTask: Task<Void, Never>?
    private var lastAvgColorImageID: ObjectIdentifier?

    private var lastArtworkData: Data?
    private var lyricsTask: Task<Void, Never>?

    private static var placeholderArtwork: NSImage {
        NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!
    }

    private func updateAverageColor(for image: NSImage) {
        let id = ObjectIdentifier(image)
        guard lastAvgColorImageID != id else { return }
        lastAvgColorImageID = id

        avgColorTask?.cancel()
        // ✅ 在主线程获取颜色，然后异步更新
        let color = image.averageColor
        avgColorTask = Task { [weak self] in
            self?.avgColor = color
        }
    }
    
    // MARK: - Computed Properties
    
    var isPlayerIdle: Bool {
        return songTitle.isEmpty && artistName.isEmpty
    }

    /// Whether the collapsed island shows the now-playing live activity
    var showsCompactLiveActivity: Bool {
        return SettingsDefaults.shared.get(SettingsDefaults.showMusicLiveActivity) && !isPlayerIdle
    }
    
    
    // MARK: - Initialization
    
    private init() {
        // Controllers will be initialized when start() is called
    }
    
    // MARK: - Lifecycle
    
    func start() {
        // Initialize controllers
        // Note: Actual controller instances will be created here
        // For now, this is a placeholder
    }
    
    func connectToNowPlayingManager(_ manager: NowPlayingManager) {
        self.nowPlayingManager = manager
        
        // Subscribe to state changes from NowPlayingManager
        manager.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlayingState in
                self?.updateFromIslandNowPlayingState(nowPlayingState)
            }
            .store(in: &cancellables)

        manager.start()
    }
    
    func stop() {
        nowPlayingManager?.stop()
        activeController?.stop()
        activeController = nil
    }
    
    func destroy() {
        stop()
        cancellables.removeAll()
        avgColorTask?.cancel()
        avgColorTask = nil
    }
    
    // MARK: - Playback Control
    
    func play() {
        activeController?.play()
        nowPlayingManager?.play()
    }
    
    func pause() {
        activeController?.pause()
        nowPlayingManager?.pause()
    }
    
    func togglePlay() {
        activeController?.togglePlayPause()
        nowPlayingManager?.playPause()
    }
    
    func nextTrack() {
        activeController?.nextTrack()
        nowPlayingManager?.nextTrack()
    }
    
    func previousTrack() {
        activeController?.previousTrack()
        nowPlayingManager?.previousTrack()
    }
    
    func seek(to position: TimeInterval) {
        // Prefer MediaRemote seeking (works for any app that participates in system media controls).
        nowPlayingManager?.seek(to: position)

        // Also update local timing anchors immediately so UI stays in sync while MediaRemote catches up.
        elapsedTime = max(0, position)
        timestampDate = Date()
        currentDisplayTime = elapsedTime

        activeController?.seek(to: position)
    }
    
    func skip(seconds: TimeInterval) {
        activeController?.skip(seconds: seconds)
    }
    
    // MARK: - Shuffle & Repeat
    
    func toggleShuffle() {
        activeController?.toggleShuffle()
    }
    
    func toggleRepeat() {
        activeController?.toggleRepeat()
    }
    
    // MARK: - Favorite
    
    func toggleFavoriteTrack() {
        activeController?.toggleFavorite()
    }
    
    // MARK: - Volume Control
    
    func setVolume(to newVolume: Double) {
        let clampedVolume = max(0, min(1, newVolume))
        activeController?.setVolume(clampedVolume)
        volume = clampedVolume
    }
    
    func syncVolumeFromActiveApp() async {
        guard let controller = activeController else { return }
        let currentVolume = await controller.getVolume()
        await MainActor.run {
            self.volume = currentVolume
        }
    }
    
    // MARK: - App Control
    
    func openMusicApp() {
        activeController?.openMusicApp()
    }
    
    // MARK: - State Update
    
    private func updateState(_ state: PlaybackState) {
        songTitle = state.songTitle
        artistName = state.artistName
        albumTitle = state.albumTitle
        isPlaying = state.isPlaying
        elapsedTime = state.elapsedTime
        songDuration = state.duration
        playbackRate = state.playbackRate
        repeatMode = state.repeatMode
        isShuffled = state.isShuffled
        isFavoriteTrack = state.isFavorite
        volume = state.volume
        bundleIdentifier = state.bundleIdentifier
        applicationName = state.applicationName
        timestampDate = state.timestampDate
        
        // Update album art
        if let image = state.albumArt {
            albumArt = image
            usingAppIconForArtwork = false
        } else {
            // Use app icon as fallback
            if let bundleId = state.bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                albumArt = NSWorkspace.shared.icon(forFile: appURL.path)
                usingAppIconForArtwork = true
            }
        }
        
        lastState = state
    }
    
    // MARK: - Lyrics
    
    func lyricLine(at time: Double) -> String {
        guard !syncedLyrics.isEmpty else { return "" }
        
        // Find the lyric line at the current time
        var currentLine = ""
        for lyric in syncedLyrics {
            if time >= lyric.timeInSeconds {
                currentLine = lyric.line
            } else {
                break
            }
        }
        return currentLine
    }
    
    // MARK: - Fetch Lyrics
    
    /// 获取歌词：先查在线的同步歌词（能跟着歌走），查不到同步歌词时再用 Apple Music 自带的歌词
    private func fetchLyrics(title: String, artist: String) async {
        isFetchingLyrics = true

        // 1️⃣ 在线 API（LrcLib、网易云等），任何播放器都适用
        var lyrics = await fetchLyricsFromAPI(title: title, artist: artist)

        // 2️⃣ Apple Music 自带的歌词只有纯文本，而且流媒体歌曲大多没有（读到的是空字符串，不能当成找到了）
        if lyrics?.synced.isEmpty ?? true, !Task.isCancelled, bundleIdentifier == "com.apple.Music",
           let own = await fetchLyricsFromAppleMusic(), !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyrics = (own, [])
        }

        // 切歌后，旧请求的结果作废
        guard !Task.isCancelled else { return }

        // 3️⃣ 没有找到歌词时清空
        currentLyrics = lyrics?.plainText ?? ""
        syncedLyrics = lyrics?.synced ?? []
        isFetchingLyrics = false
    }
    
    /// 从 Apple Music 获取歌词
    private func fetchLyricsFromAppleMusic() async -> String? {
        let script = """
        tell application "Music"
            try
                return lyrics of current track
            end try
            return ""
        end tell
        """
        return await AppleScriptHelper.execute(script)
    }
    
    /// 从在线 API 获取歌词
    private func fetchLyricsFromAPI(title: String, artist: String) async -> (plainText: String, synced: [(timeInSeconds: Double, line: String)])? {
        // 使用 LyricsService 获取歌词
        if let result = await LyricsService.shared.fetchLyrics(
            title: title,
            artist: artist,
            album: albumTitle.isEmpty ? nil : albumTitle
        ) {
            #if DEBUG
            print("✅ [MusicManager] 获取到歌词，来源: \(result.source)")
            #endif
            return (result.plainText, result.syncedLyrics)
        }
        
        #if DEBUG
        print("❌ [MusicManager] 未找到歌词: \(title) - \(artist)")
        #endif
        return nil
    }
    
    // MARK: - Playback Position Estimation
    
    func estimatedPlaybackPosition(at date: Date) -> Double {
        guard isPlaying, playbackRate > 0 else {
            return elapsedTime
        }

        let timeDelta = date.timeIntervalSince(timestampDate)
        let estimatedPosition = elapsedTime + (timeDelta * playbackRate)

        // ✅ If duration is unknown (0), do NOT clamp — this is needed for lyrics/progress fallback.
        if songDuration > 0 {
            return min(max(estimatedPosition, 0), songDuration)
        } else {
            return max(estimatedPosition, 0)
        }
    }
    
    // MARK: - NowPlaying State Update
    
    private func updateFromIslandNowPlayingState(_ state: IslandNowPlayingState) {
        guard state.hasContent else {
            clearNowPlaying()
            return
        }

        let trackChanged = state.title != songTitle || state.artist != artistName

        songTitle = state.title
        artistName = state.artist
        albumTitle = state.album
        isPlaying = state.isPlaying
        playbackRate = state.playbackRate
        songDuration = state.duration

        // Anchor: MediaRemote reports the elapsed time as of positionTimestamp, not as of now
        elapsedTime = state.position
        timestampDate = state.positionTimestamp
        updateCurrentDisplayTime()

        if state.sourceApp.isEmpty {
            bundleIdentifier = nil
            applicationName = nil
        } else {
            bundleIdentifier = state.sourceApp
            applicationName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: state.sourceApp)
                .map { FileManager.default.displayName(atPath: $0.path) } ?? state.sourceApp
        }

        if isPlaying {
            startProgressTimer()
        } else {
            stopProgressTimer()
        }

        updateArtwork(from: state, trackChanged: trackChanged)

        if trackChanged {
            lyricsTask?.cancel()
            currentLyrics = ""
            syncedLyrics = []
            let title = songTitle
            let artist = artistName
            lyricsTask = Task {
                await fetchLyrics(title: title, artist: artist)
            }
        }

        #if DEBUG
        print("🎶 [MusicManager] \(applicationName ?? "?"): \(state.title) - \(state.artist) | Pos: \(elapsedTime)/\(songDuration)")
        #endif
    }

    private func updateArtwork(from state: IslandNowPlayingState, trackChanged: Bool) {
        if let data = state.artworkData {
            guard data != lastArtworkData, let image = NSImage(data: data) else { return }
            lastArtworkData = data
            albumArt = image
            usingAppIconForArtwork = false
            return
        }

        // Artwork often arrives a moment after the title; until then show the source app's icon
        guard trackChanged else { return }
        lastArtworkData = nil
        if let bundleID = bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            albumArt = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            albumArt = Self.placeholderArtwork
        }
        usingAppIconForArtwork = true

        // Songs usually carry an album; videos don't, and a song search would find unrelated covers for them
        if !state.album.isEmpty {
            let title = state.title
            let artist = state.artist
            Task {
                await fetchArtworkFromNetwork(title: title, artist: artist)
            }
        }
    }

    private func clearNowPlaying() {
        guard !isPlayerIdle else { return }
        stopProgressTimer()
        lyricsTask?.cancel()
        songTitle = ""
        artistName = ""
        albumTitle = ""
        isPlaying = false
        playbackRate = 0
        elapsedTime = 0
        songDuration = 0
        currentDisplayTime = 0
        bundleIdentifier = nil
        applicationName = nil
        currentLyrics = ""
        syncedLyrics = []
        isFetchingLyrics = false
        lastArtworkData = nil
        albumArt = Self.placeholderArtwork
        usingAppIconForArtwork = true
    }

    // MARK: - Progress Timer
    
    @Published var currentDisplayTime: Double = 0
    private var progressTimer: Timer?
    
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateCurrentDisplayTime()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateCurrentDisplayTime() {
        currentDisplayTime = estimatedPlaybackPosition(at: Date())
    }
    
    // MARK: - Network Artwork Fetching
    
    /// 从网络(iTunes API)获取专辑封面
    private func fetchArtworkFromNetwork(title: String, artist: String) async {
        let query = "\(title) \(artist)"
        #if DEBUG
        print("🎶 [MusicManager] 🖼️ 尝试网络获取封面: \(query)")
        #endif
        
        // 构建 iTunes Search API URL
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let url = components?.url else { return }
        
        do {
            // 请求 API
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // 解析 JSON
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first,
               let artworkUrlString = first["artworkUrl100"] as? String {
                
                // 获取更高清的图片 (100x100 -> 600x600)
                let highResUrlString = artworkUrlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                
                // 获取歌曲时长 (毫秒 -> 秒)
                let trackDurationMs = first["trackTimeMillis"] as? Double ?? 0
                let trackDuration = trackDurationMs / 1000.0
                
                if let artworkUrl = URL(string: highResUrlString) {
                    // 下载图片
                    let (imageData, _) = try await URLSession.shared.data(from: artworkUrl)
                    if let image = NSImage(data: imageData) {
                        await MainActor.run {
                            // 再次检查是否还需要更新（防止已经切歌）
                            if self.songTitle == title && self.usingAppIconForArtwork {
                                self.albumArt = image
                                self.usingAppIconForArtwork = false
                                
                                // 🆕 如果当前时长为0，使用网络获取的时长
                                if self.songDuration == 0 && trackDuration > 0 {
                                    self.songDuration = trackDuration
                                    #if DEBUG
                                    print("🎶 [MusicManager] ✅ 网络获取时长: \(trackDuration)s")
                                    #endif
                                }
                                
                                 #if DEBUG
                                 print("🎶 [MusicManager] ✅ 网络封面已更新")
                                 #endif
                            }
                        }
                    }
                }
            } else {
                 #if DEBUG
                 print("🎶 [MusicManager] ❌ 未找到网络封面")
                 #endif
            }
        } catch {
            #if DEBUG
            print("🎶 [MusicManager] 网络封面获取错误: \(error)")
            #endif
        }
    }
}
