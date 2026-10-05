import Foundation
import os

/// Runs one plugin's command and reads what it wants shown, one PluginMessage per line on its stdout; taps go
/// back as PluginEvent lines on its stdin. A plugin that exits is started again, unless it keeps exiting.
/// Closing its stdin is how it learns to quit, so it never outlives the app
@MainActor
final class PluginClient {
    let manifest: PluginManifest
    let folder: URL
    /// Every message, in the order the plugin wrote them
    var onMessage: (PluginMessage) -> Void = { _ in }
    /// A new process started (the first, or one after an exit): it begins with nothing shown
    var onLaunch: () -> Void = {}
    /// The plugin stopped for good: it kept exiting, or it couldn't be started
    var onGiveUp: () -> Void = {}

    /// A line longer than this is dropped, with everything up to its end
    static let maxLineLength = 64 * 1024

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Plugin")
    private let restartDelay: TimeInterval
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var outputBuffer = Data()
    /// Dropping the rest of an overlong line until its newline
    private var skippingLine = false
    private var recentExits: [Date] = []
    private(set) var isRunning = false

    init(manifest: PluginManifest, folder: URL, restartDelay: TimeInterval = 1) {
        self.manifest = manifest
        self.folder = folder
        self.restartDelay = restartDelay
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launch()
    }

    func stop() {
        isRunning = false
        // At end of file a readability handler is called again and again with no data, so it must go with the
        // process: the termination handler that would clear it is cleared right here
        output?.fileHandleForReading.readabilityHandler = nil
        output = nil
        process?.terminationHandler = nil
        try? input?.fileHandleForWriting.close()
        process?.terminate()
        process = nil
        input = nil
    }

    func send(_ event: PluginEvent) {
        guard let input else { return }
        // A plugin that has just exited makes this fail; SIGPIPE is ignored (PluginStore), so it only throws
        do {
            try input.fileHandleForWriting.write(contentsOf: event.line)
        } catch {
            logger.warning("Plugin \(self.manifest.id, privacy: .public) isn't reading its input: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func launch() {
        let process = Process()
        process.executableURL = manifest.executableURL(in: folder)
        process.arguments = Array(manifest.command.dropFirst())
        process.currentDirectoryURL = folder

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        outputBuffer.removeAll()
        skippingLine = false
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            // End of file: stop listening, or this is called again at once, forever
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            // A line can span chunks, so keep them in order (Task hops don't guarantee that)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(chunk) }
            }
        }
        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            let status = process.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didExit(status: status) }
            }
        }

        do {
            try process.run()
            self.process = process
            self.input = input
            self.output = output
            onLaunch()
        } catch {
            logger.error("Plugin \(self.manifest.id, privacy: .public) failed to start: \(error.localizedDescription, privacy: .public)")
            isRunning = false
            onGiveUp()
        }
    }

    private func didExit(status: Int32) {
        process = nil
        input = nil
        output = nil
        guard isRunning else { return }

        // Start it again, but give up if it keeps exiting
        let now = Date()
        recentExits = recentExits.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard recentExits.count <= 5 else {
            logger.error("Plugin \(self.manifest.id, privacy: .public) keeps exiting (status \(status)); giving up")
            isRunning = false
            onGiveUp()
            return
        }
        logger.warning("Plugin \(self.manifest.id, privacy: .public) exited with status \(status); restarting")
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self, self.isRunning, self.process == nil else { return }
            self.launch()
        }
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
