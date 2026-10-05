//
//  MediaRemoteAdapter.swift
//  MacDynamicIsland
//
//  Since macOS 15.4, mediaremoted only answers now-playing queries from Apple-signed
//  processes. This library is loaded into /usr/bin/perl (see NowPlayingManager) and
//  streams the system-wide now-playing state to stdout, one JSON object per line.
//  The process exits when its stdin is closed, i.e. when the app goes away.
//

import Foundation

// The private MediaRemote functions, as the C ABI sees them
private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
private typealias GetNowPlayingClient = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
private typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (UInt8) -> Void) -> Void // The block gets a C Boolean, an unsigned char
private typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void
private typealias ClientString = @convention(c) (AnyObject) -> Unmanaged<CFString>?

/// Everything runs on `queue`, a serial queue, so the state needs no locking.
private final class Streamer: @unchecked Sendable {
    static let shared = Streamer()

    let queue = DispatchQueue(label: "MediaRemoteAdapter")
    private var getNowPlayingInfo: GetNowPlayingInfo!
    private var getNowPlayingClient: GetNowPlayingClient!
    private var getIsPlaying: GetIsPlaying!
    private var clientBundleIdentifier: ClientString!
    private var clientParentBundleIdentifier: ClientString?

    private var lastLine: Data?
    private var refreshScheduled = false
    private var retainedSources: [DispatchSourceProtocol] = []

    private static let infoKeys: [(mediaRemote: String, json: String)] = [
        ("kMRMediaRemoteNowPlayingInfoTitle", "title"),
        ("kMRMediaRemoteNowPlayingInfoArtist", "artist"),
        ("kMRMediaRemoteNowPlayingInfoAlbum", "album"),
        ("kMRMediaRemoteNowPlayingInfoDuration", "duration"),
        ("kMRMediaRemoteNowPlayingInfoElapsedTime", "elapsed"),
        ("kMRMediaRemoteNowPlayingInfoPlaybackRate", "rate"),
    ]

    private func writeLine(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              json != lastLine else { return }
        lastLine = json

        var line = json
        line.append(0x0A)
        var offset = 0
        while offset < line.count {
            let written = line.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress! + offset, line.count - offset) }
            if written <= 0 { exit(0) } // The app closed the pipe.
            offset += written
        }
    }

    private func emitSnapshot() {
        var info: [String: Any] = [:]
        var bundleID: String?
        var parentBundleID: String?
        var isPlaying = false

        let group = DispatchGroup()

        group.enter()
        getNowPlayingInfo(queue) { raw in
            if let raw, let dictionary = (raw as NSDictionary) as? [String: Any] { info = dictionary }
            group.leave()
        }

        group.enter()
        getNowPlayingClient(queue) { [self] client in
            if let client {
                bundleID = clientBundleIdentifier(client)?.takeUnretainedValue() as String?
                parentBundleID = clientParentBundleIdentifier?(client)?.takeUnretainedValue() as String?
            }
            group.leave()
        }

        group.enter()
        getIsPlaying(queue) { playing in
            isPlaying = playing != 0
            group.leave()
        }

        group.notify(queue: queue) { [self] in
            var payload: [String: Any] = [:]
            if !info.isEmpty {
                payload["playing"] = isPlaying
                if let bundleID { payload["bundleID"] = bundleID }
                if let parentBundleID { payload["parentBundleID"] = parentBundleID }

                for key in Streamer.infoKeys {
                    if let value = info[key.mediaRemote] as? String {
                        payload[key.json] = value
                    } else if let value = info[key.mediaRemote] as? NSNumber {
                        payload[key.json] = value
                    }
                }

                // Elapsed time was sampled at this moment, not when we read it.
                if let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                    payload["timestamp"] = timestamp.timeIntervalSince1970
                }

                if let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, !artwork.isEmpty {
                    payload["artwork"] = artwork.base64EncodedString()
                }
            }
            writeLine(payload)
        }
    }

    /// Change notifications arrive in bursts (app, info and playing state together); coalesce them.
    private func scheduleSnapshot() {
        queue.async { [self] in
            if refreshScheduled { return }
            refreshScheduled = true
            queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
                refreshScheduled = false
                emitSnapshot()
            }
        }
    }

    private func exitWithParent() {
        let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        stdinSource.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 256)
            if read(STDIN_FILENO, &buffer, buffer.count) <= 0 { exit(0) }
        }
        stdinSource.resume()

        // Backstop in case EOF is never delivered: once the app dies we are re-parented to launchd.
        let parent = getppid()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 2, leeway: .seconds(1))
        timer.setEventHandler {
            if getppid() != parent { exit(0) }
        }
        timer.resume()

        // Keep the sources alive for the life of the process.
        retainedSources = [stdinSource, timer]
    }

    private func loadMediaRemote() -> Bool {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else { return false }

        func function<T>(_ name: String, as type: T.Type) -> T? {
            CFBundleGetFunctionPointerForName(bundle, name as CFString).map { unsafeBitCast($0, to: T.self) }
        }

        let info = function("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self)
        let client = function("MRMediaRemoteGetNowPlayingClient", as: GetNowPlayingClient.self)
        let playing = function("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        let bundleIdentifier = function("MRNowPlayingClientGetBundleIdentifier", as: ClientString.self)
        let register = function("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterForNotifications.self)
        guard let info, let client, let playing, let bundleIdentifier, let register else { return false }

        getNowPlayingInfo = info
        getNowPlayingClient = client
        getIsPlaying = playing
        clientBundleIdentifier = bundleIdentifier
        clientParentBundleIdentifier = function("MRNowPlayingClientGetParentAppBundleIdentifier", as: ClientString.self)
        register(queue)
        return true
    }

    /// Never returns.
    func run() -> Never {
        guard loadMediaRemote() else {
            FileHandle.standardError.write(Data("MediaRemoteAdapter: MediaRemote symbols unavailable\n".utf8))
            exit(1)
        }
        exitWithParent()

        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { [self] _ in
                scheduleSnapshot()
            }
        }

        scheduleSnapshot()
        CFRunLoopRun()
        exit(0)
    }
}

/// Entry point, installed by perl as an XSUB. Never returns.
@_cdecl("mediaremote_adapter_stream")
public func mediaRemoteAdapterStream(_ perlInterpreter: UnsafeMutableRawPointer?, _ perlCV: UnsafeMutableRawPointer?) {
    Streamer.shared.run()
}
