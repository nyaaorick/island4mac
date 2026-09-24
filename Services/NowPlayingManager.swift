import Foundation
import Combine
import AppKit
import OSLog

@MainActor
final class NowPlayingManager: ObservableObject {
    @Published var currentState: IslandNowPlayingState = .idle

    private let queue = DispatchQueue(label: "com.maclingdong島.mediaremote", qos: .userInteractive)

    private typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int, AnyObject?) -> Bool
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void

    private var MRMediaRemoteGetNowPlayingInfoFunc: MRMediaRemoteGetNowPlayingInfoFunction?
    private var MRMediaRemoteSendCommandFunc: MRMediaRemoteSendCommandFunction?
    private var MRMediaRemoteSetElapsedTimeFunc: MRMediaRemoteSetElapsedTimeFunction?

    init() {
        loadMediaRemote()
    }

    private func loadMediaRemote() {
        let bundlePath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: bundlePath) as CFURL) else { return }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            MRMediaRemoteGetNowPlayingInfoFunc = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            let registerFunc = unsafeBitCast(ptr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self)
            registerFunc(queue)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            MRMediaRemoteSendCommandFunc = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            MRMediaRemoteSetElapsedTimeFunc = unsafeBitCast(ptr, to: MRMediaRemoteSetElapsedTimeFunction.self)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"), object: nil)
        refresh()
    }

    private func doubleValue(_ any: Any?) -> Double {
        switch any {
        case let d as Double:
            return d
        case let f as Float:
            return Double(f)
        case let i as Int:
            return Double(i)
        case let n as NSNumber:
            return n.doubleValue
        case let s as String:
            return Double(s) ?? 0
        default:
            return 0
        }
    }

    private func dataValue(_ any: Any?) -> Data? {
        switch any {
        case let data as Data:
            return data
        case let nsData as NSData:
            return nsData as Data
        default:
            return nil
        }
    }

    @objc func refresh() {
        // ✅ 添加静默错误处理：将系统 stderr 重定向到 /dev/null 以隐藏 MediaRemote 的误导性错误日志
        let originalStderr = dup(STDERR_FILENO)
        let devNull = open("/dev/null", O_WRONLY)
        dup2(devNull, STDERR_FILENO)
        close(devNull)

        MRMediaRemoteGetNowPlayingInfoFunc?(queue) { [weak self] info in
            // ✅ 恢复 stderr
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)

            guard let self = self else { return }
            guard let info = info else {
                DispatchQueue.main.async {
                    // ✅ 避免重复发布 idle 触发下游大量回退扫描
                    if self.currentState != .idle {
                        self.currentState = .idle
                    }
                }
                return
            }

            let playbackRate = doubleValue(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"])
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let duration = doubleValue(info["kMRMediaRemoteNowPlayingInfoDuration"])
            let position = doubleValue(info["kMRMediaRemoteNowPlayingInfoElapsedTime"])
            let sourceApp = info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ??
                info["kMRMediaRemoteNowPlayingInfoSenderDefaultPostNotificationName"] as? String ?? "System"
            let artworkData = dataValue(info["kMRMediaRemoteNowPlayingInfoArtworkData"])

            let newState = IslandNowPlayingState(
                isPlaying: playbackRate > 0,
                playbackRate: playbackRate,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                position: position,
                sourceApp: sourceApp,
                artworkData: artworkData
            )

            DispatchQueue.main.async {
                if self.currentState != newState {
                    self.currentState = newState
                }
            }
        }
    }

    func playPause() { _ = MRMediaRemoteSendCommandFunc?(2, nil); refresh() }
    func nextTrack() { _ = MRMediaRemoteSendCommandFunc?(4, nil); refresh() }
    func previousTrack() { _ = MRMediaRemoteSendCommandFunc?(5, nil); refresh() }

    func seek(to position: TimeInterval) {
        MRMediaRemoteSetElapsedTimeFunc?(position)
        refresh()
    }

    func revealSourceApp() {
        let identifier = currentState.sourceApp
        guard !identifier.isEmpty && identifier != "System" else { return }

        // Modern macOS way: Use bundle identifier directly
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        } else {
            // Fallback: If identifier is actually a name, but this is deprecated and unreliable
            // We'll stick to bundle identifier as per Apple's recommendation
        }
    }
}
