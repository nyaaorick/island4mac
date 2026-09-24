import Foundation
import Combine
import AppKit
import OSLog

/// System-wide now playing (any app that reports to Control Center: Music, Spotify, browsers, video players…).
///
/// mediaremoted refuses now-playing reads from third-party processes, so reading goes through
/// libMediaRemoteAdapter.dylib loaded into the Apple-signed /usr/bin/perl, which streams JSON lines.
/// Sending commands is still allowed from the app itself.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published var currentState: IslandNowPlayingState = .idle

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "NowPlaying")

    private var helper: Process?
    private var helperInput: Pipe?
    private var outputBuffer = Data()
    private var isRunning = false
    private var recentCrashes: [Date] = []

    private typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias MRMediaRemoteSetElapsedTimeFunction = @convention(c) (Double) -> Void

    private var MRMediaRemoteSendCommandFunc: MRMediaRemoteSendCommandFunction?
    private var MRMediaRemoteSetElapsedTimeFunc: MRMediaRemoteSetElapsedTimeFunction?

    /// MRMediaRemoteCommand values
    private enum Command: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Perl only loads the adapter and hands control to it; the adapter never returns.
    private static let helperScript = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $sym = DynaLoader::dl_find_symbol($lib, "mediaremote_adapter_stream") or die "adapter entry point missing";
        DynaLoader::dl_install_xsub("main::stream", $sym);
        stream();
        """

    init() {
        loadCommandFunctions()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launchHelper()
    }

    func stop() {
        isRunning = false
        helper?.terminationHandler = nil
        helper?.terminate()
        helper = nil
        // Closing stdin also makes the adapter exit if terminate() raced with launch.
        try? helperInput?.fileHandleForWriting.close()
        helperInput = nil
    }

    private func launchHelper() {
        guard let adapterURL = Bundle.main.privateFrameworksURL?.appendingPathComponent("libMediaRemoteAdapter.dylib"),
              FileManager.default.fileExists(atPath: adapterURL.path) else {
            logger.error("libMediaRemoteAdapter.dylib is missing from the app bundle")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.helperScript, adapterURL.path]

        // The adapter exits when stdin closes, so it never outlives the app.
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        outputBuffer.removeAll()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // A line can span chunks, so keep them in order (Task hops don't guarantee that).
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(chunk) }
            }
        }
        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperDidExit(status: status) }
            }
        }

        do {
            try process.run()
            helper = process
            helperInput = input
        } catch {
            logger.error("Failed to launch now-playing helper: \(error.localizedDescription)")
        }
    }

    private func helperDidExit(status: Int32) {
        helper = nil
        helperInput = nil
        guard isRunning else { return }

        currentState = .idle

        // Restart after a crash, but give up if it keeps dying.
        let now = Date()
        recentCrashes = recentCrashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentCrashes.count <= 5 else {
            logger.error("Now-playing helper keeps exiting (status \(status)); giving up")
            isRunning = false
            return
        }
        logger.warning("Now-playing helper exited with status \(status); restarting")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isRunning, self.helper == nil else { return }
            self.launchHelper()
        }
    }

    // MARK: - Stream Parsing

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        outputBuffer.append(chunk)

        // Only the newest complete line matters; earlier ones are already stale.
        guard let lastNewline = outputBuffer.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = outputBuffer[outputBuffer.startIndex..<lastNewline]
        outputBuffer = Data(outputBuffer[outputBuffer.index(after: lastNewline)...])

        guard let line = complete.split(separator: UInt8(ascii: "\n")).last else { return }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(line))
            let newState = payload.state
            if newState != currentState {
                currentState = newState
            }
        } catch {
            logger.error("Unreadable now-playing payload: \(error.localizedDescription)")
        }
    }

    /// One line from MediaRemoteAdapter; `{}` means nothing is playing.
    private struct Payload: Decodable {
        var playing: Bool?
        var bundleID: String?
        var parentBundleID: String?
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var rate: Double?
        var timestamp: Double?
        var artwork: String?

        var state: IslandNowPlayingState {
            guard let playing else { return .idle }
            return IslandNowPlayingState(
                isPlaying: playing,
                playbackRate: rate ?? (playing ? 1 : 0),
                title: title ?? "",
                artist: artist ?? "",
                album: album ?? "",
                duration: duration ?? 0,
                position: elapsed ?? 0,
                positionTimestamp: timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date(),
                // Web players report a helper process; the browser is the app the user knows.
                sourceApp: parentBundleID ?? bundleID ?? "",
                artworkData: artwork.flatMap { Data(base64Encoded: $0) }
            )
        }
    }

    // MARK: - Commands

    private func loadCommandFunctions() {
        let bundleURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) else { return }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            MRMediaRemoteSendCommandFunc = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFunction.self)
        }
        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString) {
            MRMediaRemoteSetElapsedTimeFunc = unsafeBitCast(ptr, to: MRMediaRemoteSetElapsedTimeFunction.self)
        }
    }

    private func send(_ command: Command) {
        _ = MRMediaRemoteSendCommandFunc?(command.rawValue, nil)
    }

    func play() { send(.play) }
    func pause() { send(.pause) }
    func playPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    func seek(to position: TimeInterval) {
        MRMediaRemoteSetElapsedTimeFunc?(position)
    }

    func revealSourceApp() {
        let identifier = currentState.sourceApp
        guard !identifier.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
