import XCTest
@testable import MacDynamicIsland

@MainActor
final class PluginTests: XCTestCase {

    private func line(_ json: String) -> Data { Data(json.utf8) }

    /// A plugins folder of its own, removed after the test
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PluginTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func writePlugin(_ json: String, id: String, in folder: URL) throws -> URL {
        let plugin = folder.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: plugin.appendingPathComponent(PluginManifest.fileName))
        return plugin
    }

    private func manifest(command: [String], id: String = "echo") -> PluginManifest {
        PluginManifest(id: id, name: "Echo", symbol: "star", command: command, protocol: 1, version: nil)
    }

    // MARK: - Messages

    func testEveryKindOfMessageReads() throws {
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"compact","symbol":"timer","text":"04:59","progress":0.5}"#)),
                       .compact(PluginCompact(symbol: "timer", text: "04:59", progress: 0.5)))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"list","rows":[{"id":"r1","title":"5 min"}]}"#)),
                       .list([PluginRow(id: "r1", title: "5 min")]))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"buttons","buttons":[{"id":"stop","title":"Stop"}]}"#)),
                       .buttons([PluginButton(id: "stop", title: "Stop")]))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"popup","text":"Done","seconds":2}"#)),
                       .popup(PluginPopup(text: "Done", seconds: 2)))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"clear","target":"all"}"#)), .clear(.all))
    }

    func testUnknownAndBrokenLinesThrow() {
        XCTAssertThrowsError(try PluginMessage.decode(line(#"{"type":"teleport"}"#))) { error in
            XCTAssertEqual(error as? PluginMessage.DecodeError, .unknownType("teleport"))
        }
        XCTAssertThrowsError(try PluginMessage.decode(line("{not json")))
        XCTAssertThrowsError(try PluginMessage.decode(line(#"{"type":"list"}"#)), "a list without rows")
    }

    func testMessagesAreKeptInBounds() throws {
        let rows = (0..<80).map { #"{"title":"\#($0)"}"# }.joined(separator: ",")
        guard case .list(let list) = try PluginMessage.decode(line(#"{"type":"list","rows":[\#(rows)]}"#)) else {
            return XCTFail("not a list")
        }
        XCTAssertEqual(list.count, PluginMessage.maxItems)

        let long = String(repeating: "x", count: 500)
        guard case .compact(let compact) = try PluginMessage.decode(line(#"{"type":"compact","text":"\#(long)","progress":7}"#)) else {
            return XCTFail("not compact")
        }
        XCTAssertEqual(compact.text?.count, PluginMessage.maxTextLength)
        XCTAssertEqual(compact.progress, 1)
        XCTAssertEqual(PluginPopup(text: "", seconds: 60).duration, 10, "a popup never stays long")
    }

    func testEventsAreOneLineEach() {
        XCTAssertEqual(String(decoding: PluginEvent.action("stop").line, as: UTF8.self), #"{"id":"stop","type":"action"}"# + "\n")
        XCTAssertEqual(String(decoding: PluginEvent.visible(true).line, as: UTF8.self), #"{"tab":true,"type":"visible"}"# + "\n")
    }

    // MARK: - Manifest

    func testManifestChecks() throws {
        let folder = try makeFolder()
        let good = try writePlugin(#"{"id":"timer","name":"Timer","symbol":"timer","command":["./timer"],"protocol":1}"#, id: "timer", in: folder)
        let manifest = try PluginManifest.load(from: good)
        XCTAssertEqual(manifest.executableURL(in: good).path, good.appendingPathComponent("timer").standardizedFileURL.path)

        func loadError(_ json: String) -> PluginManifest.LoadError? {
            let plugin = try? writePlugin(json, id: "bad", in: folder)
            do { _ = try PluginManifest.load(from: plugin!); return nil } catch { return error as? PluginManifest.LoadError }
        }
        XCTAssertEqual(loadError(#"{"id":"Bad Id","name":"x","symbol":"x","command":["./x"],"protocol":1}"#), .invalidID("Bad Id"))
        XCTAssertEqual(loadError(#"{"id":"bad","name":"x","symbol":"x","command":[],"protocol":1}"#), .emptyCommand)
        XCTAssertEqual(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["../../x"],"protocol":1}"#), .programOutsideFolder("../../x"))
        XCTAssertEqual(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["./x"],"protocol":99}"#), .newerProtocol(99))
        XCTAssertEqual(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["bin/../../x"],"protocol":1}"#), .programOutsideFolder("bin/../../x"))
        XCTAssertEqual(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["."],"protocol":1}"#), .programOutsideFolder("."), "the folder itself")
        XCTAssertNil(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["bin/x"],"protocol":1}"#))
        XCTAssertNil(loadError(#"{"id":"bad","name":"x","symbol":"x","command":["/usr/bin/python3","main.py"],"protocol":1}"#),
                     "a system program is fine")
    }

    // MARK: - Process

    func testAClientReadsWhatThePluginWrites() {
        let client = PluginClient(manifest: manifest(command: ["/bin/echo", #"{"type":"compact","text":"hi"}"#]),
                                  folder: FileManager.default.temporaryDirectory, restartDelay: 60)
        let received = expectation(description: "message")
        client.onMessage = { message in
            XCTAssertEqual(message, .compact(PluginCompact(text: "hi")))
            received.fulfill()
        }
        client.start()
        wait(for: [received], timeout: 5)
        client.stop()
    }

    func testTapsReachThePlugin() {
        // sed as a plugin: it turns each action it reads into a message the island understands
        let client = PluginClient(manifest: manifest(command: ["/usr/bin/sed", "-l", #"s/"type":"action"/"type":"clear","target":"all"/"#]),
                                  folder: FileManager.default.temporaryDirectory, restartDelay: 60)
        let received = expectation(description: "echo")
        client.onMessage = { message in
            XCTAssertEqual(message, .clear(.all))
            received.fulfill()
        }
        client.start()
        client.send(.action("stop"))
        wait(for: [received], timeout: 5)
        client.stop()
    }

    /// CPU seconds this process has used, user and system
    private func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    func testAStoppedPluginLeavesTheCPUIdle() {
        let client = PluginClient(manifest: manifest(command: ["/bin/sleep", "30"]), folder: FileManager.default.temporaryDirectory)
        client.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        client.stop()

        // A reader left listening at end of file is called again at once, forever: a core at 100%
        let before = cpuTime()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertLessThan(cpuTime() - before, 0.2, "nothing should keep running once the plugin has stopped")
    }

    func testAPluginThatKeepsExitingIsGivenUp() {
        let client = PluginClient(manifest: manifest(command: ["/usr/bin/true"]), folder: FileManager.default.temporaryDirectory,
                                  restartDelay: 0.05)
        let gaveUp = expectation(description: "gave up")
        client.onGiveUp = { gaveUp.fulfill() }
        client.start()
        wait(for: [gaveUp], timeout: 10)
        XCTAssertFalse(client.isRunning)
    }

    func testLinesSplitAcrossChunksAndOverlongLines() {
        let client = PluginClient(manifest: manifest(command: ["/usr/bin/true"]), folder: FileManager.default.temporaryDirectory)
        var messages: [PluginMessage] = []
        client.onMessage = { messages.append($0) }

        client.consume(Data(#"{"type":"clear","#.utf8))
        client.consume(Data((#""target":"list"}"# + "\n").utf8))
        XCTAssertEqual(messages, [.clear(.list)], "a line arriving in two chunks reads once complete")

        client.consume(Data(repeating: UInt8(ascii: "x"), count: PluginClient.maxLineLength + 1))
        client.consume(Data(("tail of the long line\n" + #"{"type":"clear","target":"all"}"# + "\n").utf8))
        XCTAssertEqual(messages, [.clear(.list), .clear(.all)], "an overlong line is dropped up to its end, the next one reads")
    }

    // MARK: - Catalog

    /// Zips a plugin folder the way the plugins repo ships it
    private func zip(_ folder: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testInstallUpdateAndRemoveFromTheCatalog() async throws {
        let repo = try makeFolder()
        let installed = try makeFolder()
        let source = try writePlugin(#"{"id":"timer","name":"Timer","symbol":"timer","command":["./timer"],"protocol":1,"version":"1.0.0"}"#,
                                     id: "timer", in: repo)
        let archive = repo.appendingPathComponent("timer.zip")
        try zip(source, to: archive)
        let index = repo.appendingPathComponent("index.json")
        try Data(#"{"plugins":[{"id":"timer","name":"Timer","version":"1.0.0","protocol":1,"archive":"\#(archive.absoluteString)"}]}"#.utf8)
            .write(to: index)

        let client = PluginCatalogClient(pluginsFolder: installed)
        let entries = try await client.fetchIndex(from: index)
        XCTAssertEqual(entries.map(\.id), ["timer"])

        try await client.install(entries[0])
        XCTAssertEqual(try PluginManifest.load(from: installed.appendingPathComponent("timer")).version, "1.0.0")

        // An update replaces the installed copy
        try FileManager.default.removeItem(at: archive)
        try Data(#"{"id":"timer","name":"Timer","symbol":"timer","command":["./timer"],"protocol":1,"version":"1.1.0"}"#.utf8)
            .write(to: source.appendingPathComponent(PluginManifest.fileName))
        try zip(source, to: archive)
        try await client.install(entries[0])
        XCTAssertEqual(try PluginManifest.load(from: installed.appendingPathComponent("timer")).version, "1.1.0")

        try client.remove("timer")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.appendingPathComponent("timer").path))
    }

    func testTheCatalogRefusesWhatItShouldnt() async throws {
        let repo = try makeFolder()
        let client = PluginCatalogClient(pluginsFolder: try makeFolder())
        do {
            _ = try await client.fetchIndex(from: URL(string: "http://example.com/index.json")!)
            XCTFail("plain http is refused")
        } catch {}

        // An archive holding a different plugin than the index says
        let other = try writePlugin(#"{"id":"other","name":"x","symbol":"x","command":["./x"],"protocol":1}"#, id: "other", in: repo)
        let archive = repo.appendingPathComponent("other.zip")
        try zip(other, to: archive)
        let entry = PluginCatalogEntry(id: "timer", name: "Timer", version: "1", protocol: 1, archive: archive)
        do {
            try await client.install(entry)
            XCTFail("a mismatched archive is refused")
        } catch {}
        XCTAssertFalse(PluginCatalogEntry(id: "x", name: "x", version: "1", protocol: 99, archive: archive).isSupported)
    }

    // MARK: - Beside the notch

    func testWhatShowsBesideTheNotch() {
        XCTAssertEqual(LiveActivity.pick(agent: true, pluginPopup: true, music: true, pluginCompact: true), .agent)
        XCTAssertEqual(LiveActivity.pick(agent: false, pluginPopup: true, music: true, pluginCompact: true), .pluginPopup,
                       "a popup shows ahead of music")
        XCTAssertEqual(LiveActivity.pick(agent: false, pluginPopup: false, music: true, pluginCompact: true), .music)
        XCTAssertEqual(LiveActivity.pick(agent: false, pluginPopup: false, music: false, pluginCompact: true), .pluginCompact,
                       "paused music (not playing, pointer away) leaves the space to a plugin's countdown")
        XCTAssertEqual(LiveActivity.pick(agent: false, pluginPopup: false, music: false, pluginCompact: false), .none)
    }

    func testARestartedPluginStartsWithNothingShown() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"echo","name":"Echo","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "echo", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, tabs: tabs)
        store.reload()
        tabs.setEnabled(.plugin("echo"), true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        store.apply(.compact(PluginCompact(text: "04:12")), from: "echo")
        XCTAssertNotNil(store.compactPlugin)
        store.reload()
        XCTAssertNil(store.compactPlugin, "the new process hasn't said anything yet, so the old countdown goes")
        store.stop()
    }

    // MARK: - Store

    func testTheStoreFindsPluginsAndShowsTheirContent() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"echo","name":"Echo","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "echo", in: folder)
        _ = try writePlugin(#"{"id":"other","name":"x","symbol":"x","command":["/bin/cat"],"protocol":1}"#, id: "mismatch", in: folder)

        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, tabs: tabs)
        store.reload()

        XCTAssertEqual(store.installed.map(\.id), ["echo"])
        XCTAssertEqual(store.broken.map(\.folder), ["mismatch"], "a plugin whose id isn't its folder name is skipped")
        XCTAssertEqual(tabs.pluginTabs, [.plugin("echo")])
        XCTAssertNil(store.compactPlugin, "its tab isn't one of yours yet")

        tabs.setEnabled(.plugin("echo"), true)
        store.apply(.compact(PluginCompact(text: "1")), from: "echo")
        XCTAssertEqual(store.compactPlugin?.compact.text, "1")
        store.apply(.clear(.compact), from: "echo")
        XCTAssertNil(store.compactPlugin)

        store.apply(.popup(PluginPopup(text: "Done", seconds: 1)), from: "echo")
        XCTAssertEqual(store.popup?.popup.text, "Done")
        let dismissed = expectation(description: "popup goes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            XCTAssertNil(store.popup)
            dismissed.fulfill()
        }
        wait(for: [dismissed], timeout: 3)
        store.stop()
    }
}
