import Foundation
import os

/// Runs one plugin's command and reads what it wants shown, one PluginMessage per line on its stdout; taps go
/// back as PluginEvent lines on its stdin. A plugin that exits is started again, unless it keeps exiting.
/// Closing its stdin is how it learns to quit, so it never outlives the app
@MainActor
final class PluginClient {
    let manifest: PluginManifest
    let folder: URL
    /// The plugin's own folder for what it keeps (ISLAND_DATA_DIR): outside its install folder, so updates keep it
    let dataFolder: URL
    /// Every message, in the order the plugin wrote them
    var onMessage: (PluginMessage) -> Void = { _ in }
    /// A new process started (the first, or one after an exit): it begins with nothing shown
    var onLaunch: () -> Void = {}
    /// The plugin stopped for good: it kept exiting, or it couldn't be started. With the reason
    var onGiveUp: (String) -> Void = { _ in }
    /// Started again when it exits (a plugin that runs while its tab is on). Without it, the process just ends
    /// and `onExit` says how (a plugin that runs on demand)
    var restartsOnExit = true
    var onExit: (Int32) -> Void = { _ in }

    /// A line longer than this is dropped, with everything up to its end
    static let maxLineLength = 64 * 1024
    /// How long a plugin gets to quit after being asked, before it and everything it started are killed
    static let terminationGrace: TimeInterval = 2
    /// Lines of its stderr kept to say why it stopped
    static let keptErrorLines = 5

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Plugin")
    private let restartDelay: TimeInterval
    private(set) var process: PluginProcess?
    private var outputBuffer = Data()
    /// Dropping the rest of an overlong line until its newline
    private var skippingLine = false
    private var errorBuffer = Data()
    /// The last lines the plugin wrote to stderr, newest last
    private(set) var recentErrors: [String] = []
    private var recentExits: [Date] = []
    private(set) var isRunning = false

    /// Where its program is, when not in its folder (a plugin bundled in the app)
    let programFolder: URL?

    var executableURL: URL { manifest.executableURL(in: programFolder ?? folder) }

    init(manifest: PluginManifest, folder: URL, dataFolder: URL, programFolder: URL? = nil, restartDelay: TimeInterval = 1) {
        self.manifest = manifest
        self.folder = folder
        self.programFolder = programFolder
        self.dataFolder = dataFolder
        self.restartDelay = restartDelay
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launch()
    }

    /// Starts a plugin that was given up on, with a clean slate
    func restart() {
        stop()
        recentExits.removeAll()
        recentErrors.removeAll()
        start()
    }

    /// Asks it to quit; it and everything it started are killed if it's still there after terminationGrace
    func stop() {
        isRunning = false
        process?.terminate(grace: Self.terminationGrace)
        process = nil
    }

    /// Forgets the process without signalling it, for stopForQuit, which ends every plugin together
    func stopWithoutKilling() {
        isRunning = false
        process = nil
    }

    func send(_ event: PluginEvent) {
        guard let process else { return }
        if !process.write(event.line) {
            logger.warning("Plugin \(self.manifest.id, privacy: .public) isn't reading its input; an event was dropped")
        }
    }

    /// What a plugin learns about where it runs, beside the environment it inherits
    var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["ISLAND_PROTOCOL"] = String(PluginManifest.supportedProtocol)
        environment["ISLAND_PLUGIN_ID"] = manifest.id
        environment["ISLAND_DATA_DIR"] = dataFolder.path
        environment["ISLAND_APP_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        environment["ISLAND_APP_BUNDLE"] = Bundle.main.bundleURL.path
        return environment
    }

    private func launch() {
        outputBuffer.removeAll()
        skippingLine = false
        errorBuffer.removeAll()
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)

        let spawned: PluginProcess
        do {
            spawned = try PluginProcess.spawn(
                executable: executableURL,
                arguments: Array(manifest.command.dropFirst()),
                directory: folder,
                environment: environment,
                // A line can span chunks, so keep them in order (Task hops don't guarantee that)
                onOutput: { [weak self] chunk in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(chunk) } }
                },
                onError: { [weak self] chunk in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.consumeErrors(chunk) } }
                },
                onExit: { [weak self] status in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.didExit(status: status) } }
                }
            )
        } catch {
            logger.error("Plugin \(self.manifest.id, privacy: .public) failed to start: \(String(describing: error), privacy: .public)")
            isRunning = false
            onGiveUp(String(describing: error))
            return
        }
        process = spawned
        onLaunch()
    }

    private func didExit(status: Int32) {
        // An exit of a process already replaced (restart) or stopped
        guard let process, process.exited else { return }
        self.process = nil
        guard isRunning else { return }
        guard restartsOnExit else {
            isRunning = false
            onExit(status)
            return
        }

        // Start it again, but give up if it keeps exiting
        let now = Date()
        recentExits = recentExits.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentExits.count <= 5 else {
            logger.error("Plugin \(self.manifest.id, privacy: .public) keeps exiting (status \(status)); giving up")
            isRunning = false
            onGiveUp(recentErrors.last ?? "exited \(recentExits.count) times in a minute (status \(status))")
            return
        }
        logger.warning("Plugin \(self.manifest.id, privacy: .public) exited with status \(status); restarting")
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self, self.isRunning, self.process == nil else { return }
            self.launch()
        }
    }

    private func consumeErrors(_ chunk: Data) {
        errorBuffer.append(chunk)
        while let newline = errorBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: errorBuffer[errorBuffer.startIndex..<newline], as: UTF8.self)
            errorBuffer = Data(errorBuffer[errorBuffer.index(after: newline)...])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            recentErrors = Array((recentErrors + [String(trimmed.prefix(PluginMessage.maxTextLength))]).suffix(Self.keptErrorLines))
        }
        if errorBuffer.count > Self.maxLineLength { errorBuffer.removeAll() }
    }

    // MARK: - Reading

    func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        outputBuffer.append(chunk)

        while let newline = outputBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = outputBuffer[outputBuffer.startIndex..<newline]
            outputBuffer = Data(outputBuffer[outputBuffer.index(after: newline)...])
            if skippingLine {
                skippingLine = false
                continue
            }
            handle(Data(line))
        }
        if outputBuffer.count > Self.maxLineLength {
            logger.error("Plugin \(self.manifest.id, privacy: .public) wrote a line over \(Self.maxLineLength) bytes; dropped")
            outputBuffer.removeAll()
            skippingLine = true
        }
    }

    private func handle(_ line: Data) {
        guard line.contains(where: { !$0.isASCIIWhitespace }) else { return }
        do {
            onMessage(try PluginMessage.decode(line))
        } catch {
            logger.error("Plugin \(self.manifest.id, privacy: .public) wrote an unreadable line: \(String(describing: error), privacy: .public)")
        }
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool { self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D }
}
