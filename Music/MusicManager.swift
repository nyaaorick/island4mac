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
    @Published var needsAccessibilityPermission: Bool = false
    
    // Lyrics
    @Published var currentLyrics: String = ""
    @Published var syncedLyrics: [(timeInSeconds: Double, line: String)] = []
    @Published var isFetchingLyrics: Bool = false
    
    // 静态变量，防止重复弹窗
    static var hasPromptedForAccessibility = false
    
    // MARK: - Private Properties

    private var activeController: MediaControllerProtocol?
    private var controllers: [MediaControllerProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastState: PlaybackState?
    private var nowPlayingManager: NowPlayingManager?

    private var avgColorTask: Task<Void, Never>?
    private var lastAvgColorImageID: ObjectIdentifier?

    // ✅ 回退扫描节流/取消（避免主线程被频繁 Accessibility 扫描拖死）
    private var detectPlayerTask: Task<Void, Never>?
    private var lastDetectPlayerTime: Date = .distantPast
    private let detectPlayerThrottleInterval: TimeInterval = 0.5 // ✅ 从 1.0 降低到 0.5秒，更快检测
    
    // ✅ 窗口检测节流
    private var lastWindowCheckTime: Date = .distantPast
    private let windowCheckThrottleInterval: TimeInterval = 1.0 // ✅ 从 2.0 降低到 1.0秒，更快获取歌曲信息

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
    }
    
    func stop() {
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
        nowPlayingManager?.playPause()
    }
    
    func pause() {
        activeController?.pause()
        nowPlayingManager?.playPause()
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
    
    func forceUpdate() {
        Task {
            await detectAndDisplayRunningPlayer()
            // Also update active controller if exists
            // activeController?.updatePlaybackInfo() // Assuming protocol has this, if not, detectAndDisplay is good for now
        }
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
    
    /// 获取歌词（先尝试 AppleScript，再尝试在线 API）
    private func fetchLyrics(title: String, artist: String) async {
        // 防止重复获取
        guard !isFetchingLyrics else { return }
        
        await MainActor.run {
            isFetchingLyrics = true
        }
        
        // 1️⃣ 尝试从 Apple Music 获取歌词（如果正在使用）
        if bundleIdentifier == "com.apple.Music" {
            if let lyrics = await fetchLyricsFromAppleMusic() {
                await MainActor.run {
                    self.currentLyrics = lyrics
                    self.syncedLyrics = [] // Apple Music 通常不提供同步歌词
                    self.isFetchingLyrics = false
                }
                return
            }
        }
        
        // 2️⃣ 尝试从在线 API 获取歌词（兼容 QQ音乐、网易云等）
        if let lyrics = await fetchLyricsFromAPI(title: title, artist: artist) {
            await MainActor.run {
                self.currentLyrics = lyrics.plainText
                self.syncedLyrics = lyrics.synced
                self.isFetchingLyrics = false
            }
            return
        }
        
        // 3️⃣ 没有找到歌词
        await MainActor.run {
            self.currentLyrics = ""
            self.syncedLyrics = []
            self.isFetchingLyrics = false
        }
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
        return AppleScriptHelper.executeScript(script)
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
    
    // MARK: - Album Art via Multiple Sources
    
    /// 支持的音乐播放器配置
    private struct MusicPlayerConfig {
        let bundleIdentifier: String
        let name: String
        let artworkScript: String?      // AppleScript 获取封面
        let artworkURLScript: String?   // AppleScript 获取封面 URL
        let playStateScript: String?    // AppleScript 获取播放状态
        let durationScript: String?     // AppleScript 获取歌曲时长
        
        // 默认初始化（为了向后兼容）
        init(bundleIdentifier: String, name: String, artworkScript: String?, artworkURLScript: String?, playStateScript: String? = nil, durationScript: String? = nil) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.artworkScript = artworkScript
            self.artworkURLScript = artworkURLScript
            self.playStateScript = playStateScript
            self.durationScript = durationScript
        }
        
        static let supportedPlayers: [MusicPlayerConfig] = [
            // 🇨🇳 国产播放器优先检测（因为它们通常不向 MediaRemote 提供数据）
            
            // 汽水音乐
            MusicPlayerConfig(
                bundleIdentifier: "com.soda.music",
                name: "汽水音乐",
                artworkScript: nil,
                artworkURLScript: nil,
                playStateScript: """
                    tell application "System Events"
                        tell process "汽水音乐"
                            try
                                set buttonName to name of button 1 of group 1 of group 1 of window 1
                                if buttonName contains "暂停" or buttonName contains "Pause" then
                                    return "playing"
                                else
                                    return "paused"
                                end if
                            end try
                        end tell
                    end tell
                    return "unknown"
                    """,
                durationScript: nil
            ),
            // QQ音乐
            MusicPlayerConfig(
                bundleIdentifier: "com.tencent.QQMusicMac",
                name: "QQ音乐",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // 网易云音乐
            MusicPlayerConfig(
                bundleIdentifier: "com.netease.163music",
                name: "网易云音乐",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // 酷狗音乐
            MusicPlayerConfig(
                bundleIdentifier: "com.kugou.mac.kugou",
                name: "酷狗音乐",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // 酷我音乐
            MusicPlayerConfig(
                bundleIdentifier: "com.kuwo.kwmusic",
                name: "酷我音乐",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // TIDAL
            MusicPlayerConfig(
                bundleIdentifier: "com.tidal.desktop",
                name: "TIDAL",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // YouTube Music (Electron)
            MusicPlayerConfig(
                bundleIdentifier: "com.electron.youtube-music",
                name: "YouTube Music",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // Deezer
            MusicPlayerConfig(
                bundleIdentifier: "com.deezer.deezer-desktop",
                name: "Deezer",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // Amazon Music
            MusicPlayerConfig(
                bundleIdentifier: "com.amazon.music",
                name: "Amazon Music",
                artworkScript: nil,
                artworkURLScript: nil
            ),
            // Swinsian
            MusicPlayerConfig(
                bundleIdentifier: "com.swinsian.Swinsian",
                name: "Swinsian",
                artworkScript: """
                    tell application "Swinsian"
                        try
                            return data of artwork 1 of current track
                        end try
                    end tell
                    return ""
                    """,
                artworkURLScript: nil
            ),
            // VOX
            MusicPlayerConfig(
                bundleIdentifier: "com.coppertino.Vox",
                name: "VOX",
                artworkScript: nil,
                artworkURLScript: """
                    tell application "VOX"
                        try
                            return artworkImage
                        end try
                    end tell
                    return ""
                    """
            ),
            
            // 🇺🇸 国际播放器（放在最后，因为它们通常正确向 MediaRemote 提供数据）
            
            // Spotify
            MusicPlayerConfig(
                bundleIdentifier: "com.spotify.client",
                name: "Spotify",
                artworkScript: nil,
                artworkURLScript: """
                    tell application "Spotify"
                        try
                            if player state is not stopped then
                                return artwork url of current track
                            end if
                        end try
                    end tell
                    return ""
                    """
            ),
            // Apple Music
            MusicPlayerConfig(
                bundleIdentifier: "com.apple.Music",
                name: "Apple Music",
                artworkScript: """
                    tell application "Music"
                        try
                            if player state is not stopped then
                                return raw data of artwork 1 of current track
                            end if
                        end try
                    end tell
                    return ""
                    """,
                artworkURLScript: nil
            )
        ]
    }
    
    /// 通过多种方式获取专辑封面（备用方案）
    private func fetchAlbumArtViaAppleScript() async {
        // 遍历所有支持的播放器
        for player in MusicPlayerConfig.supportedPlayers {
            guard isAppRunning(bundleIdentifier: player.bundleIdentifier) else {
                continue
            }
            
            #if DEBUG
            print("🎶 [MusicManager] 检测到 \(player.name) 正在运行")
            #endif
            
            // 尝试通过 AppleScript 获取封面数据
            if let script = player.artworkScript,
               let data = AppleScriptHelper.executeScriptReturningData(script),
               let image = NSImage(data: data) {
                await MainActor.run {
                    self.albumArt = image
                    self.usingAppIconForArtwork = false
                }
                #if DEBUG
                print("🎶 [MusicManager] ✅ 从 \(player.name) 获取专辑封面")
                #endif
                return
            }
            
            // 尝试通过 URL 下载封面
            if let script = player.artworkURLScript,
               let urlString = AppleScriptHelper.executeScript(script),
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        await MainActor.run {
                            self.albumArt = image
                            self.usingAppIconForArtwork = false
                        }
                        #if DEBUG
                        print("🎶 [MusicManager] ✅ 从 \(player.name) URL 下载专辑封面")
                        #endif
                        return
                    }
                } catch {
                    #if DEBUG
                    print("🎶 [MusicManager] \(player.name) 封面下载失败: \(error)")
                    #endif
                }
            }
            
            // 如果播放器不支持 AppleScript，尝试使用应用图标
            if player.artworkScript == nil && player.artworkURLScript == nil {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) {
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    await MainActor.run {
                        self.albumArt = icon
                        self.usingAppIconForArtwork = true
                    }
                    #if DEBUG
                    print("🎶 [MusicManager] ℹ️ 使用 \(player.name) 应用图标作为封面")
                    #endif
                    return
                }
            }
        }

        // 都失败了，使用默认图标
        await MainActor.run {
            self.albumArt = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!
            self.usingAppIconForArtwork = true
            #if DEBUG
            print("🎶 [MusicManager] ⚠️ 无法获取专辑封面，使用默认图标")
            #endif
        }
    }
    
    /// 检查应用是否正在运行
    private func isAppRunning(bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }
    
    /// 获取当前正在运行的音乐播放器名称
    func getRunningMusicPlayerName() -> String? {
        for player in MusicPlayerConfig.supportedPlayers {
            if isAppRunning(bundleIdentifier: player.bundleIdentifier) {
                return player.name
            }
        }
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
        let previousTitle = songTitle
        
        // 🔍 检查 MediaRemote 是否提供了有效数据
        // ✅ 增强检测：即使 MediaRemote 有数据，如果数据不完整也尝试回退检测
        let hasValidData = !state.title.isEmpty || !state.artist.isEmpty
        
        // ✅ 对于国产播放器（汽水、QQ、网易云等），始终尝试回退检测
        let isChinesePlayer = isAnyChinesePlayerRunning()
        if isChinesePlayer && !hasValidData {
            #if DEBUG
            print("🎶 [MusicManager] 🇨🇳 检测到国产播放器运行，MediaRemote 无数据，切换到回退检测")
            #endif
            scheduleDetectAndDisplayRunningPlayer()
            return // ✅ 直接返回，使用回退检测的结果
        }
        
        if hasValidData {
            // MediaRemote 有数据，使用它
            songTitle = state.title
            artistName = state.artist
            albumTitle = state.album
            isPlaying = state.isPlaying
            playbackRate = state.playbackRate
            
            // Anchor Set
            elapsedTime = state.position
            songDuration = state.duration
            timestampDate = Date() // Reset anchor time
            
            // Update "Live" display time immediately
            currentDisplayTime = elapsedTime
            
            // Keep both bundleIdentifier + applicationName in sync
            let source = state.sourceApp
            if source.isEmpty || source == "System" {
                bundleIdentifier = nil
                applicationName = nil
            } else {
                bundleIdentifier = source
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source),
                   let bundle = Bundle(url: appURL),
                   let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    applicationName = name
                } else {
                    applicationName = source
                }
            }
            
            // 🔄 Timer Management
            if isPlaying {
                startProgressTimer()
                // Force an immediate update cycle with very short delay to sync up
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateCurrentDisplayTime()
                }
            } else {
                stopProgressTimer()
            }
            
            #if DEBUG
            print("🎶 [MusicManager] MediaRemote 数据: \(state.title) - \(state.artist) | Pos: \(elapsedTime)/\(songDuration)")
            #endif
            
            // ✅ 优化：处理专辑封面 - 更积极地尝试多种方法
            Task {
                var artworkAcquired = false
                
                // 方法1: 使用 MediaRemote 提供的封面数据
                if let artworkData = state.artworkData, let image = NSImage(data: artworkData) {
                    await MainActor.run {
                        self.albumArt = image
                        self.usingAppIconForArtwork = false
                    }
                    artworkAcquired = true
                    #if DEBUG
                    print("🎶 [MusicManager] ✅ 使用 MediaRemote 封面")
                    #endif
                }
                
                // 方法2: 尝试通过 AppleScript 获取（适用于 Apple Music, Spotify 等）
                if !artworkAcquired {
                    await fetchAlbumArtViaAppleScript()
                    if !self.usingAppIconForArtwork {
                        artworkAcquired = true
                        #if DEBUG
                        print("🎶 [MusicManager] ✅ 使用 AppleScript 封面")
                        #endif
                    }
                }
                
                // 方法3: 尝试从网络获取封面（iTunes API）
                if !artworkAcquired || self.usingAppIconForArtwork {
                    #if DEBUG
                    print("🎶 [MusicManager] 尝试网络获取封面: \(self.songTitle) - \(self.artistName)")
                    #endif
                    await self.fetchArtworkFromNetwork(title: self.songTitle, artist: self.artistName)
                }
            }
            
            // 获取歌词
            if !songTitle.isEmpty, songTitle != previousTitle {
                Task {
                    await fetchLyrics(title: songTitle, artist: artistName)
                }
            }
        } else {
            // 🚨 MediaRemote 无数据，尝试检测运行中的音乐播放器（已节流/防并发）
            if !AccessibilityHelper.shared.hasAccessibilityPermission() {
                if !Self.hasPromptedForAccessibility {
                    Self.hasPromptedForAccessibility = true
                    AccessibilityHelper.shared.requestAccessibilityPermission()
                }
            }

            scheduleDetectAndDisplayRunningPlayer()
        }
    }
    
    // MARK: - Chinese Player Detection Helper
    
    /// 检查是否有国产播放器运行
    private func isAnyChinesePlayerRunning() -> Bool {
        let chinesePlayerBundleIds = [
            "com.soda.music",           // 汽水音乐
            "com.tencent.QQMusicMac",    // QQ音乐
            "com.netease.163music",      // 网易云音乐
            "com.kugou.mac.kugou",       // 酷狗音乐
            "com.kuwo.kwmusic"           // 酷我音乐
        ]
        
        return chinesePlayerBundleIds.contains { isAppRunning(bundleIdentifier: $0) }
    }
    
    // MARK: - Fallback Player Detection (Throttled)

    private func scheduleDetectAndDisplayRunningPlayer() {
        let now = Date()
        guard now.timeIntervalSince(lastDetectPlayerTime) >= detectPlayerThrottleInterval else {
            #if DEBUG
            print("🎶 [MusicManager] ⚡️ 节流中，跳过回退检测")
            #endif
            return
        }
        lastDetectPlayerTime = now

        #if DEBUG
        print("🎶 [MusicManager] 🔍 开始回退检测播放器...")
        #endif
        
        detectPlayerTask?.cancel()
        detectPlayerTask = Task { [weak self] in
            await self?.detectAndDisplayRunningPlayer()
        }
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
        if isPlaying {
            let timeDelta = Date().timeIntervalSince(timestampDate)
            let estimated = elapsedTime + (timeDelta * playbackRate)
            
            // Just ensure it's not negative. 
            // Only clamp to duration if duration is valid (> 0)
            if songDuration > 0 {
                currentDisplayTime = min(max(estimated, 0), songDuration)
            } else {
                currentDisplayTime = max(estimated, 0)
            }
        }
    }
    
    /// 检测并显示运行中的音乐播放器
    private func detectAndDisplayRunningPlayer() async {
        for player in MusicPlayerConfig.supportedPlayers {
            if isAppRunning(bundleIdentifier: player.bundleIdentifier) {
                #if DEBUG
                print("🎶 [MusicManager] 检测到 \(player.name) 正在运行（无 MediaRemote 数据）")
                #endif
                
                // 尝试通过 AppleScript 获取信息
                if let script = player.artworkScript,
                   let data = AppleScriptHelper.executeScriptReturningData(script),
                   let image = NSImage(data: data) {
                    await MainActor.run {
                        self.albumArt = image
                        self.usingAppIconForArtwork = false
                        self.applicationName = player.name
                    }
                    #if DEBUG
                    print("🎶 [MusicManager] ✅ 从 \(player.name) AppleScript 获取封面")
                    #endif
                    return
                }
                
                // 尝试通过 URL 获取封面
                if let script = player.artworkURLScript,
                   let urlString = AppleScriptHelper.executeScript(script),
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = NSImage(data: data) {
                            await MainActor.run {
                                self.albumArt = image
                                self.usingAppIconForArtwork = false
                                self.applicationName = player.name
                            }
                            #if DEBUG
                            print("🎶 [MusicManager] ✅ 从 \(player.name) URL 获取封面")
                            #endif
                            return
                        }
                    } catch {
                        #if DEBUG
                        print("🎶 [MusicManager] \(player.name) URL 封面获取失败")
                        #endif
                    }
                }

                // 使用应用图标作为封面
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) {
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    
                    // 🔍 尝试从窗口标题获取歌曲信息
                    var (title, artist) = getWindowTitleInfo(bundleId: player.bundleIdentifier)
                    
                    // 🆕 如果窗口标题没有信息，尝试使用 Accessibility API
                    if title == nil || (title?.isEmpty ?? true) {
                        #if DEBUG
                        print("🎶 [MusicManager] 🔄 窗口标题为空，尝试 Accessibility API...")
                        #endif
                        let axInfo = getAccessibilityInfo(bundleId: player.bundleIdentifier)
                        if let axTitle = axInfo.title, !axTitle.isEmpty {
                            title = axTitle
                            artist = axInfo.artist
                            #if DEBUG
                            print("🎶 [MusicManager] ✅ Accessibility API 获取成功: \(axTitle) - \(axInfo.artist ?? "")") 
                            #endif
                        } else {
                            #if DEBUG
                            print("🎶 [MusicManager] ⚠️ Accessibility API 也无法获取歌曲信息")
                            #endif
                        }
                    }
                    
                    // ✅ 获取真实的播放状态
                    let playingState = getPlayingStateViaAccessibility(bundleId: player.bundleIdentifier)
                    
                    let newTitle = title ?? player.name
                    let newArtist = artist ?? "正在播放..."
                    let trackChanged = (newTitle != self.songTitle) || (newArtist != self.artistName)

                    await MainActor.run {
                        self.bundleIdentifier = player.bundleIdentifier
                        self.applicationName = player.name

                        self.albumArt = icon
                        self.usingAppIconForArtwork = true

                        self.songTitle = newTitle
                        self.artistName = newArtist
                        
                        // ✅ 使用真实的播放状态
                        self.isPlaying = playingState

                        // ✅ Provide a real-time progress/lyrics clock even when MediaRemote has no timing.
                        if trackChanged {
                            self.elapsedTime = 0
                            self.songDuration = 0
                            self.playbackRate = playingState ? 1.0 : 0.0
                            self.timestampDate = Date()
                            self.currentDisplayTime = 0
                        } else {
                            // ✅ 更新 playbackRate 根据当前状态
                            self.playbackRate = playingState ? 1.0 : 0.0
                            if playingState {
                                self.updateCurrentDisplayTime()
                            }
                        }

                        if playingState {
                            self.startProgressTimer()
                        } else {
                            self.stopProgressTimer()
                        }
                    }
                    
                    #if DEBUG
                    print("🎶 [MusicManager] ℹ️ 使用 \(player.name) 应用图标")
                    if let t = title { print("🎶 [MusicManager] 歌曲信息: \(t) - \(artist ?? "未知")" ) }
                    #endif
                    
                // 如果获取到了歌曲信息
                if let t = title, !t.isEmpty {
                    // 1. 获取歌词
                    Task {
                        await self.fetchLyrics(title: t, artist: artist ?? "")
                    }
                    
                    // 2. 如果当前使用的是应用图标，尝试获取网络封面
                    if self.usingAppIconForArtwork {
                         Task {
                             await self.fetchArtworkFromNetwork(title: t, artist: artist ?? "")
                         }
                    }
                }
                return
            }
        }
    }
    
    // 没有检测到任何播放器
    #if DEBUG
    print("🎶 [MusicManager] ⚠️ 未检测到运行中的音乐播放器")
    #endif
}


/// 从应用窗口标题获取歌曲信息
private func getWindowTitleInfo(bundleId: String) -> (title: String?, artist: String?) {
        // ✅ 节流: 避免频繁调用 CGWindowListCopyWindowInfo（非常慢）
        let now = Date()
        guard now.timeIntervalSince(lastWindowCheckTime) >= windowCheckThrottleInterval else {
            #if DEBUG
            print("🎶 [MusicManager] 🐢 窗口检测节流中，使用缓存")
            #endif
            return (nil, nil) // 返回 nil，使用缓存的数据
        }
        lastWindowCheckTime = now
        
        #if DEBUG
        print("🎶 [MusicManager] 🔍 开始窗口标题检测: \(bundleId)")
        #endif
        
        // 使用 CGWindowListCopyWindowInfo 获取窗口标题（不需要 AppleScript 权限）
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            #if DEBUG
            print("🎶 [MusicManager] ⚠️ 无法获取窗口列表")
            #endif
            return (nil, nil)
        }
        
        let targetAppNames = getAppNames(for: bundleId)
        var bestTitle: String? = nil
        var bestArtist: String? = nil
        
        #if DEBUG
        print("🎶 [MusicManager] 🔍 搜索 \(bundleId) 的窗口...")
        print("🎶 [MusicManager] 目标应用名: \(targetAppNames)")
        #endif
        
        // 查找属于指定应用的窗口
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String else {
                continue
            }
            
            let windowName = window[kCGWindowName as String] as? String ?? ""
            let windowLayer = window[kCGWindowLayer as String] as? Int ?? 0
            
            // 检查是否是目标应用的窗口
            let isTargetApp = targetAppNames.contains { ownerName.lowercased().contains($0.lowercased()) }
            
            if isTargetApp {
                #if DEBUG
                print("🎶 [MusicManager] 📋 找到窗口: owner=\(ownerName), title='\(windowName)', layer=\(windowLayer)")
                #endif
                
                // 跳过空标题、应用名本身、或者常见的非歌曲窗口标题
                if windowName.isEmpty ||
                   windowName == ownerName ||
                   windowName == "汽水音乐" ||
                   windowName == "QQ音乐" ||
                   windowName == "网易云音乐" ||
                   windowName.contains("Item-0") ||
                   windowName == "Window" {
                    continue
                }
                
                // 解析窗口标题
                let (parsedTitle, parsedArtist) = parseWindowTitle(windowName)
                
                // 优先选择有艺术家信息的窗口
                if let t = parsedTitle, let a = parsedArtist {
                    bestTitle = t
                    bestArtist = a
                    #if DEBUG
                    print("🎶 [MusicManager] ✅ 找到完整歌曲信息: \(t) - \(a)")
                    #endif
                    break // 找到最佳结果，停止搜索
                } else if let t = parsedTitle, bestTitle == nil {
                    bestTitle = t
                    bestArtist = parsedArtist
                    #if DEBUG
                    print("🎶 [MusicManager] 📝 暂存标题: \(t) (无艺术家)")
                    #endif
                }
            }
        }
        
        #if DEBUG
        if bestTitle == nil {
            print("🎶 [MusicManager] ⚠️ 未能从窗口获取歌曲信息")
            print("🎶 [MusicManager] 💡 提示：")
            print("🎶    1. 确保\(getAppNames(for: bundleId).first ?? bundleId)正在播放歌曲")
            print("🎶    2. 在「系统设置 → 隐私与安全 → 辅助功能」中授予权限")
            print("🎶    3. 窗口标题为空可能是因为应用正在加载中")
        } else {
            print("🎶 [MusicManager] ✅ 窗口标题检测成功: \(bestTitle ?? "") - \(bestArtist ?? "")")
        }
        #endif
        
        return (bestTitle, bestArtist)
    }
    
    /// 获取应用的可能名称
    private func getAppNames(for bundleId: String) -> [String] {
        switch bundleId {
        case "com.soda.music":
            return ["汽水音乐", "Soda", "soda"]
        case "com.tencent.QQMusicMac":
            return ["QQ音乐", "QQMusic"]
        case "com.netease.163music":
            return ["网易云音乐", "NeteaseMusic", "163"]
        case "com.kugou.mac.kugou":
            return ["酷狗音乐", "KuGou"]
        case "com.kuwo.kwmusic":
            return ["酷我音乐", "KuWo"]
        case "com.apple.Music":
            return ["Music", "音乐"]
        case "com.spotify.client":
            return ["Spotify"]
        default:
            // 从 bundle ID 提取应用名
            let parts = bundleId.split(separator: ".")
            if let lastPart = parts.last {
                return [String(lastPart)]
            }
            return []
        }
    }
    
    /// 解析窗口标题为歌曲名和歌手名
    private func parseWindowTitle(_ windowTitle: String) -> (title: String?, artist: String?) {
        // 常见格式: "歌曲名 - 歌手名" 或 "歌手名 - 歌曲名"
        let separators = [" - ", " — ", " | ", " · ", " / "]
        
        for separator in separators {
            if windowTitle.contains(separator) {
                let parts = windowTitle.components(separatedBy: separator)
                if parts.count >= 2 {
                    let title = parts[0].trimmingCharacters(in: .whitespaces)
                    let artist = parts[1].trimmingCharacters(in: .whitespaces)
                    return (title, artist)
                }
            }
        }
        
        // 无法解析，返回整个标题作为歌曲名
        return (windowTitle, nil)
    }
    
    // MARK: - Accessibility API 获取歌曲信息
    
    // MARK: - Accessibility API 获取歌曲信息
    
    /// 使用 Accessibility API 获取歌曲信息（需要用户授权辅助功能权限）
    private func getAccessibilityInfo(bundleId: String) -> (title: String?, artist: String?) {
        // 0. 强制检查权限
        if !AccessibilityHelper.shared.hasAccessibilityPermission() {
            #if DEBUG
            print("🎶 [MusicManager] ⚠️ Accessibility 权限未授予，需要在「系统设置 → 隐私与安全 → 辅助功能」中授权")
            #endif
            Task { @MainActor in
                self.needsAccessibilityPermission = true
            }
            // 尝试一次请求
            if !Self.hasPromptedForAccessibility {
                Self.hasPromptedForAccessibility = true
                #if DEBUG
                print("🎶 [MusicManager] 🔔 弹出 Accessibility 权限请求")
                #endif
                AccessibilityHelper.shared.requestAccessibilityPermission()
            }
            return (nil, nil)
        } else {
             Task { @MainActor in
                if self.needsAccessibilityPermission {
                    self.needsAccessibilityPermission = false
                    #if DEBUG
                    print("🎶 [MusicManager] ✅ Accessibility 权限已授予")
                    #endif
                }
            }
        }
        
        // 获取运行中的应用
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return (nil, nil)
        }
        
        // ... (rest of the code)
        
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        // 获取所有窗口
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        
        if result != .success {
             #if DEBUG
             print("🎶 [MusicManager] ⚠️ Accessibility Error: \(result.rawValue)")
             #endif
             // 如果获取失败且错误是 kAXErrorCannotComplete，通常意味着没有权限
             if result.rawValue == -25204 || result.rawValue == -25201 { // kAXErrorCannotComplete / kAXErrorActionUnsupported
                 Task { @MainActor in
                     self.needsAccessibilityPermission = true
                 }
                 AccessibilityHelper.shared.requestAccessibilityPermission()
             }
             return (nil, nil)
        }
        
        guard let windows = windowsRef as? [AXUIElement] else {
            return (nil, nil)
        }
        
        #if DEBUG
        print("🎶 [MusicManager] 🔍 Accessibility: 找到 \(windows.count) 个窗口")
        #endif
        
        var candidates: [String] = []
        
        // 遍历窗口查找文本信息
        for window in windows {
            // 获取窗口标题作为参考
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let windowTitle = titleRef as? String ?? ""
            
            // 忽略迷你悬浮窗或无关窗口
            if windowTitle == "DesktopLyrics" || windowTitle == "FloatWindow" { continue }
            
            // ✅ 性能优化: 将递归深度从 50 降低到 15，大幅减少 CPU 占用
            let texts = collectVisibleText(in: window, depth: 0, maxDepth: 15)
            candidates.append(contentsOf: texts)
        }
        
        return analyzeTextCandidates(candidates, bundleId: bundleId)
    }
    
    /// 递归收集可见文本 (Aggressive Mode)
    private func collectVisibleText(in element: AXUIElement, depth: Int, maxDepth: Int) -> [String] {
        guard depth < maxDepth else { return [] }
        
        var results: [String] = []
        
        // 获取基本属性 (Value, Title, Description, Help)
        var valueRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        var helpRef: CFTypeRef?
        
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpRef)
        
        // 聚合所有可能的文本来源
        let candidates = [
            valueRef as? String,
            titleRef as? String,
            descRef as? String,
            helpRef as? String
        ].compactMap { $0 }.filter { !$0.isEmpty }
        
        // 只要有文本就收集，不再过滤 Role (Electron 里的 Role 经常乱标)
        if let bestText = candidates.first {
             results.append(bestText)
        }
        
        // 递归子元素
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                results.append(contentsOf: collectVisibleText(in: child, depth: depth + 1, maxDepth: maxDepth))
            }
        }
        
        return results
    }
    
    /// 分析文本候选列表，推断歌曲信息
    private func analyzeTextCandidates(_ candidates: [String], bundleId: String) -> (title: String?, artist: String?) {
        // 🚫 黑名单：侧边栏、菜单、通用按钮
        let blocklist = [
            "推荐", "听歌模式", "我喜欢的音乐", "抖音收藏的音乐", "历史播放",
            "创建的歌单", "月", "小杨的2024年度...", "收藏的歌单和专辑",
            "喜欢", "下载", "评论", "分享", "更多", "播放", "暂停", "收起",
            "上一首", "下一首", "音质", "词", "列表", "倍速", "音量", "关闭", "最小化", "全屏",
            "汽水音乐", "Window", "DesktopLyrics", "FloatWindow", "System Item"
        ]
        
        // 过滤过程
        let filtered = candidates.filter { text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return false }
            if t.count > 50 { return false } // 歌词或长文本通常很长，过滤掉
            if t.contains(":") && t.count <= 8 { return false } // 时间戳 00:00 / 03:00
            if Int(t) != nil { return false } // 纯数字
            if t.hasSuffix("w+") || t.hasSuffix("w") { return false } // 播放量 e.g. 3w+
            
            // 检查黑名单
            if blocklist.contains(where: { t.contains($0) }) { return false }
            
            return true
        }
        
        // 去重
        let unique = Array(NSOrderedSet(array: filtered)).map { $0 as! String }
        
        #if DEBUG
        print("🎶 [MusicManager] 🔍 过滤后的候选: \(unique)")
        #endif
        
        // 策略 1: 寻找包含了 " - " 的完整组合
        for text in unique {
            if text.contains(" - ") || text.contains(" — ") {
                let parts = text.components(separatedBy: text.contains(" - ") ? " - " : " — ")
                if parts.count >= 2 {
                    let t = parts[0].trimmingCharacters(in: .whitespaces)
                    let a = parts[1].trimmingCharacters(in: .whitespaces)
                    if t.count > 1 && a.count > 1 {
                        return (t, a)
                    }
                }
            }
        }
        
        // 策略 2: Heuristic 推断
        // 汽水音乐播放界面的特征：
        // 标题通常在艺人名字上面，且字号较大（但在 AX 树中可能表现为顺序相邻）
        // 过滤掉侧边栏后，剩余列表的前几个极有可能是 Title 和 Artist
        if unique.count >= 2 {
            let potentialTitle = unique[0]
            let potentialArtist = unique[1]
            return (potentialTitle, potentialArtist)
        }
        
        return (nil, nil)
    }
    
    /// 通过 Accessibility API 检测播放/暂停状态
    private func getPlayingStateViaAccessibility(bundleId: String) -> Bool {
        // 检查辅助功能权限
        if !AccessibilityHelper.shared.hasAccessibilityPermission() {
            // 无权限时，假定正在播放（保守策略）
            return true
        }
        
        // 获取运行中的应用
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return false
        }
        
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        // 获取所有窗口
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return true // 获取失败时假定播放中
        }
        
        // 遍历窗口，查找播放/暂停按钮
        for window in windows {
            let playPauseButton = findPlayPauseButton(in: window, depth: 0, maxDepth: 20)
            if let button = playPauseButton {
                // 检查按钮的各种属性来判断状态
                var titleRef: CFTypeRef?
                var descRef: CFTypeRef?
                var valueRef: CFTypeRef?
                
                AXUIElementCopyAttributeValue(button, kAXTitleAttribute as CFString, &titleRef)
                AXUIElementCopyAttributeValue(button, kAXDescriptionAttribute as CFString, &descRef)
                AXUIElementCopyAttributeValue(button, kAXValueAttribute as CFString, &valueRef)
                
                let title = titleRef as? String ?? ""
                let desc = descRef as? String ?? ""
                let value = valueRef as? String ?? ""
                
                // 判断逻辑:
                // - 包含 "暂停"/"Pause" -> 正在播放
                // - 包含 "播放"/"Play" -> 已暂停
                let combinedText = "\(title) \(desc) \(value)".lowercased()
                
                if combinedText.contains("暂停") || combinedText.contains("pause") {
                    return true // 按钮显示"暂停"，说明正在播放
                } else if combinedText.contains("播放") || combinedText.contains("play") {
                    return false // 按钮显示"播放"，说明已暂停
                }
            }
        }
        
        // 未找到明确的播放/暂停按钮，默认假定正在播放
        return true
    }
    
    /// 递归查找播放/暂停按钮
    private func findPlayPauseButton(in element: AXUIElement, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth < maxDepth else { return nil }
        
        // 检查当前元素的角色
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        
        // 如果是按钮，检查是否为播放/暂停按钮
        if role == kAXButtonRole as String {
            var titleRef: CFTypeRef?
            var descRef: CFTypeRef?
            
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            
            let title = titleRef as? String ?? ""
            let desc = descRef as? String ?? ""
            let combinedText = "\(title) \(desc)".lowercased()
            
            // 匹配播放/暂停按钮的特征
            if combinedText.contains("play") || combinedText.contains("pause") ||
               combinedText.contains("播放") || combinedText.contains("暂停") {
                return element
            }
        }
        
        // 递归搜索子元素
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findPlayPauseButton(in: child, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }
        
        return nil
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
                            if self.songTitle == title {
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
