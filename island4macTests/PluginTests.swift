import XCTest
@testable import island4mac

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
                                  folder: FileManager.default.temporaryDirectory, dataFolder: FileManager.default.temporaryDirectory, restartDelay: 60)
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
                                  folder: FileManager.default.temporaryDirectory, dataFolder: FileManager.default.temporaryDirectory, restartDelay: 60)
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
        let client = PluginClient(manifest: manifest(command: ["/bin/sleep", "30"]), folder: FileManager.default.temporaryDirectory, dataFolder: FileManager.default.temporaryDirectory)
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
                                  dataFolder: FileManager.default.temporaryDirectory, restartDelay: 0.05)
        let gaveUp = expectation(description: "gave up")
        client.onGiveUp = { _ in gaveUp.fulfill() }
        client.start()
        wait(for: [gaveUp], timeout: 10)
        XCTAssertFalse(client.isRunning)
    }

    func testLinesSplitAcrossChunksAndOverlongLines() {
        let client = PluginClient(manifest: manifest(command: ["/usr/bin/true"]), folder: FileManager.default.temporaryDirectory, dataFolder: FileManager.default.temporaryDirectory)
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

        // Removed for good here, so tests leave nothing in your Trash
        var client = PluginCatalogClient(pluginsFolder: installed)
        client.movesToTrash = false
        let entries = try await client.fetchIndex(from: index)
        XCTAssertEqual(entries.map(\.id), ["timer"])

        try await client.install(entries[0])
        XCTAssertEqual(try PluginManifest.load(from: installed.appendingPathComponent("timer")).version, "1.0.0")

        // An update replaces the installed copy
        try FileManager.default.removeItem(at: archive)
        try Data(#"{"id":"timer","name":"Timer","symbol":"timer","command":["./timer"],"protocol":1,"version":"1.1.0"}"#.utf8)
            .write(to: source.appendingPathComponent(PluginManifest.fileName))
        try zip(source, to: archive)
        let newer = PluginCatalogEntry(id: "timer", name: "Timer", version: "1.1.0", protocol: 1, archive: archive)
        try await client.install(newer)
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
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: true, pluginPopup: true, music: true, pluginCompact: true), .priorityPlugin,
                       "an agent at work (a high-priority plugin) comes first")
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: false, pluginPopup: true, music: true, pluginCompact: true), .pluginPopup,
                       "a popup shows ahead of music")
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: false, pluginPopup: false, music: true, pluginCompact: true), .music)
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: false, pluginPopup: false, music: false, pluginCompact: true), .pluginCompact,
                       "paused music (not playing, pointer away) leaves the space to a plugin's countdown")
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: false, pluginPopup: false, music: false, pluginCompact: false), .none)
    }

    func testARestartedPluginStartsWithNothingShown() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"echo","name":"Echo","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "echo", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, dataFolder: try makeFolder(), tabs: tabs)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        tabs.setEnabled(.plugin("echo"), true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        store.apply(.compact(PluginCompact(text: "04:12")), from: "echo")
        XCTAssertNotNil(store.compactPlugin)
        store.reload()
        XCTAssertNil(store.compactPlugin, "the new process hasn't said anything yet, so the old countdown goes")
        store.stop()
    }

    func testOnlyAPluginWhoseFilesChangedRestarts() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"one","name":"One","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "one", in: folder)
        _ = try writePlugin(#"{"id":"two","name":"Two","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "two", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, dataFolder: try makeFolder(), tabs: tabs)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        // Room for two plugin tabs
        tabs.setEnabled(IslandTab.builtIn.last!, false)
        tabs.setEnabled(.plugin("one"), true)
        tabs.setEnabled(.plugin("two"), true)
        // Without start() nothing follows the tabs, so scan again to run the two
        store.reload()
        XCTAssertTrue(waitUntil(2) { store.processID(of: "one") != nil && store.processID(of: "two") != nil })
        let one = store.processID(of: "one"), two = store.processID(of: "two")

        store.refresh()
        XCTAssertEqual(store.processID(of: "one"), one, "nothing changed: nothing restarts")
        XCTAssertEqual(store.processID(of: "two"), two)

        _ = try writePlugin(#"{"id":"two","name":"Two","symbol":"star","command":["/bin/cat"],"protocol":1,"version":"2"}"#, id: "two", in: folder)
        store.refresh()
        XCTAssertTrue(waitUntil(2) { store.processID(of: "two") != nil && store.processID(of: "two") != two }, "an update restarts it")
        XCTAssertEqual(store.processID(of: "one"), one, "and only it")

        try FileManager.default.removeItem(at: folder.appendingPathComponent("two"))
        store.refresh()
        XCTAssertNil(store.processID(of: "two"), "a removed plugin stops")
        XCTAssertEqual(store.processID(of: "one"), one)
        store.stop()
    }

    func testTheFolderMonitorReportsAChangeInAPluginsFolder() throws {
        let folder = try makeFolder()
        let plugin = try writePlugin(#"{"id":"one","name":"One","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "one", in: folder)
        var changes = 0
        let monitor = PluginFolderMonitor(folder: folder, delay: 0.05) { changes += 1 }
        monitor.start()
        defer { monitor.stop() }
        // As island-plugin dev installs a build: written aside, then renamed into place
        try Data("new".utf8).write(to: plugin.appendingPathComponent(".one.installing"))
        XCTAssertEqual(rename(plugin.appendingPathComponent(".one.installing").path, plugin.appendingPathComponent("one").path), 0)
        XCTAssertTrue(waitUntil(2) { changes > 0 })

        // A plugin folder added later is watched too
        let added = try writePlugin(#"{"id":"two","name":"Two","symbol":"star","command":["/bin/cat"],"protocol":1}"#, id: "two", in: folder)
        XCTAssertTrue(waitUntil(2) { changes > 1 })
        let before = changes
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        try Data("x".utf8).write(to: added.appendingPathComponent("two"))
        XCTAssertTrue(waitUntil(2) { changes > before })
    }

    // MARK: - Preferences

    /// Secrets in memory, so tests never touch the Keychain
    private final class MemorySecrets: SecretStorage {
        var items: [String: String] = [:]
        func read(service: String, account: String) -> String? { items["\(service)/\(account)"] }
        func write(_ value: String?, service: String, account: String) { items["\(service)/\(account)"] = value }
        func removeAll(service: String) { items = items.filter { !$0.key.hasPrefix(service + "/") } }
    }

    private func makePreferences() -> (PluginPreferencesStore, MemorySecrets) {
        let suiteName = "PluginTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let secrets = MemorySecrets()
        return (PluginPreferencesStore(defaults: UserDefaults(suiteName: suiteName)!, secrets: secrets), secrets)
    }

    func testPreferencesInTheManifest() throws {
        let folder = try makeFolder()
        let plugin = try writePlugin(#"""
        {"id":"weather","name":"Weather","symbol":"sun.max","command":["./weather"],"protocol":2,"preferences":[
          {"key":"apiKey","title":"API key","kind":"secure","required":true},
          {"key":"city","title":"City","kind":"text","default":"Paris","placeholder":"City name"},
          {"key":"celsius","title":"Celsius","kind":"toggle","default":true},
          {"key":"count","title":"Days","kind":"number","default":3,"minimum":1,"maximum":7},
          {"key":"minutes","title":"Refresh every","kind":"choice","default":5,
           "options":[{"title":"1 min","value":1},{"title":"5 min","value":5}]}]}
        """#, id: "weather", in: folder)
        let manifest = try PluginManifest.load(from: plugin)
        XCTAssertEqual(manifest.preferences?.map(\.kind), [.secure, .text, .toggle, .number, .choice])
        XCTAssertEqual(manifest.preferences?[3].fallback, .number(3))
        XCTAssertEqual(manifest.preferences?[4].fallback, .number(5))

        func loadError(_ preferences: String) -> PluginManifest.LoadError? {
            let bad = try? writePlugin(#"{"id":"bad","name":"x","symbol":"x","command":["./x"],"protocol":2,"preferences":\#(preferences)}"#, id: "bad", in: folder)
            do { _ = try PluginManifest.load(from: bad!); return nil } catch { return error as? PluginManifest.LoadError }
        }
        XCTAssertEqual(loadError(#"[{"key":"a","title":"A","kind":"text"},{"key":"a","title":"B","kind":"text"}]"#),
                       .invalidPreferences(#"preference "a" is declared twice"#))
        XCTAssertEqual(loadError(#"[{"key":"a","title":"A","kind":"choice"}]"#), .invalidPreferences(#"preference "a" is a choice without options"#))
        let many = (0...PluginPreference.maxCount).map { #"{"key":"k\#($0)","title":"t","kind":"toggle"}"# }.joined(separator: ",")
        XCTAssertNotNil(loadError("[\(many)]"))
        let unknownKind = try writePlugin(#"{"id":"bad","name":"x","symbol":"x","command":["./x"],"protocol":2,"preferences":[{"key":"a","title":"A","kind":"colour"}]}"#,
                                          id: "bad", in: folder)
        XCTAssertThrowsError(try PluginManifest.load(from: unknownKind), "an unknown kind")
    }

    /// IslandKit's plugin.json for a plugin with one preference of each kind, copied from the plugins repo
    /// (IslandKit/Tests/IslandKitTests/Fixtures/weather.plugin.json): the app must read what IslandKit writes
    func testIslandKitsPluginJSONLoads() throws {
        let folder = try makeFolder()
        let plugin = try writePlugin(#"""
        {
          "command" : [
            "./weather"
          ],
          "id" : "weather",
          "name" : "Weather",
          "preferences" : [
            {
              "default" : "",
              "key" : "apiKey",
              "kind" : "secure",
              "required" : true,
              "title" : "API key"
            },
            {
              "default" : 5,
              "key" : "minutes",
              "kind" : "choice",
              "options" : [
                {
                  "title" : "1",
                  "value" : 1
                },
                {
                  "title" : "5",
                  "value" : 5
                },
                {
                  "title" : "15",
                  "value" : 15
                }
              ],
              "title" : "Refresh every"
            },
            {
              "default" : 3,
              "key" : "days",
              "kind" : "number",
              "maximum" : 7,
              "minimum" : 1,
              "title" : "Days"
            },
            {
              "default" : true,
              "key" : "celsius",
              "kind" : "toggle",
              "title" : "Celsius"
            }
          ],
          "protocol" : 2,
          "symbol" : "sun.max",
          "version" : "1.0.0"
        }
        """#, id: "weather", in: folder)
        let manifest = try PluginManifest.load(from: plugin)
        XCTAssertEqual(manifest.preferences?.map(\.kind), [.secure, .choice, .number, .toggle])
        XCTAssertEqual(manifest.preferences?.first?.required, true)
        XCTAssertEqual(manifest.preferences?[1].options?.map(\.value), [.number(1), .number(5), .number(15)])
        XCTAssertEqual(manifest.preferences?[1].fallback, .number(5))
        XCTAssertEqual(manifest.preferences?[3].fallback, .bool(true))
    }

    func testPreferenceValuesKeepTheirShape() throws {
        let decoded = try JSONDecoder().decode([PluginPreferenceValue].self, from: Data(#"[true, 5, 2.5, "x"]"#.utf8))
        XCTAssertEqual(decoded, [.bool(true), .number(5), .number(2.5), .string("x")])
        XCTAssertEqual(PluginPreferenceValue(object: true as NSNumber), .bool(true), "a boolean isn't read as 1")
        XCTAssertEqual(PluginPreferenceValue(object: 1 as NSNumber), .number(1))

        let days = PluginPreference(key: "d", title: "Days", kind: .number, minimum: 1, maximum: 7)
        XCTAssertEqual(days.accepted(.number(30)), .number(7))
        XCTAssertNil(days.accepted(.string("3")))
        let choice = PluginPreference(key: "c", title: "C", kind: .choice, options: [.init(title: "One", value: .number(1))])
        XCTAssertNil(choice.accepted(.number(2)), "only one of its options")

        let line = String(decoding: PluginEvent.preferences(["on": .bool(true), "n": .number(5), "s": .string("x")]).line, as: UTF8.self)
        XCTAssertEqual(line, #"{"type":"preferences","values":{"n":5,"on":true,"s":"x"}}"# + "\n")
    }

    func testPreferencesAreKeptAndSecretsGoToTheKeychain() {
        let (store, secrets) = makePreferences()
        let key = PluginPreference(key: "apiKey", title: "Key", kind: .secure, required: true)
        let city = PluginPreference(key: "city", title: "City", kind: .text, default: .string("Paris"))
        var changes: [String] = []
        let cancellable = store.changes.sink { changes.append($0) }
        defer { cancellable.cancel() }

        XCTAssertEqual(store.value(of: city, for: "w"), .string("Paris"), "its default until set")
        store.set(.string("Rome"), of: city, for: "w")
        store.set(.string("s3cret"), of: key, for: "w")
        XCTAssertEqual(store.value(of: city, for: "w"), .string("Rome"))
        XCTAssertEqual(store.value(of: key, for: "w"), .string("s3cret"))
        XCTAssertEqual(secrets.items.values.sorted(), ["s3cret"], "only the secret is in the Keychain")
        XCTAssertEqual(changes, ["w", "w"])
        store.set(.string("Rome"), of: city, for: "w")
        XCTAssertEqual(changes.count, 2, "setting the same value isn't a change")

        store.removeAll(for: "w")
        XCTAssertEqual(store.value(of: city, for: "w"), .string("Paris"))
        XCTAssertTrue(secrets.items.isEmpty)
    }

    func testAPluginWaitsForItsRequiredSettingsThenHearsThem() throws {
        let folder = try makeFolder()
        let data = try makeFolder()
        _ = try writePlugin(#"""
        {"id":"weather","name":"Weather","symbol":"sun.max","command":["/bin/sh","-c","cat > \"$ISLAND_DATA_DIR/in.txt\""],"protocol":2,
         "preferences":[{"key":"apiKey","title":"API key","kind":"secure","required":true},{"key":"city","title":"City","kind":"text","default":"Paris"}]}
        """#, id: "weather", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: UserDefaults(suiteName: suiteName)!)
        let (preferences, _) = makePreferences()
        let store = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs, preferences: preferences)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        tabs.setEnabled(.plugin("weather"), true)
        store.reload()
        XCTAssertEqual(store.statuses["weather"], .needsSetup)
        XCTAssertNil(store.processID(of: "weather"), "not started without its key")

        let apiKey = try XCTUnwrap(store.installed.first?.manifest.preferences?.first)
        preferences.set(.string("k1"), of: apiKey, for: "weather")
        store.applyPreferences(of: "weather")
        XCTAssertNotNil(store.processID(of: "weather"), "started once it's set")
        XCTAssertEqual(store.statuses["weather"], .running)

        let input = data.appendingPathComponent("weather/in.txt")
        func received() -> [String] {
            ((try? String(contentsOf: input, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        XCTAssertTrue(waitUntil(2) { received().count >= 2 })
        XCTAssertEqual(received().prefix(2), [#"{"type":"preferences","values":{"apiKey":"k1","city":"Paris"}}"#,
                                              #"{"tab":false,"type":"visible"}"#], "its settings first, then visibility")

        preferences.set(.string("k2"), of: apiKey, for: "weather")
        XCTAssertTrue(waitUntil(2) { received().last?.contains("k2") == true }, "a change reaches it after a pause")

        preferences.set(.string(""), of: apiKey, for: "weather")
        store.applyPreferences(of: "weather")
        XCTAssertNil(store.processID(of: "weather"), "emptied: it stops")
        XCTAssertEqual(store.statuses["weather"], .needsSetup)
        store.stop()
    }

    // MARK: - Protocol 5

    /// Protocol 6: a state and a detail on rows, cards and the compact content; a state this app doesn't know
    /// (from a plugin written for a newer one) reads as none rather than failing the message
    func testStatesAndDetailsRead() throws {
        guard case .list(let rows) = try PluginMessage.decode(line(#"{"type":"list","rows":[{"title":"Tests","subtitle":"Running","state":"working","detail":"1:23"},{"title":"Lint","state":"done"},{"title":"Later","state":"paused","detail":"x"}]}"#)) else {
            return XCTFail("not a list")
        }
        XCTAssertEqual(rows.map(\.state), [.working, .done, nil])
        XCTAssertEqual(rows.map(\.detail), ["1:23", nil, "x"])
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"compact","symbol":"hammer","text":"1:23","state":"attention"}"#)),
                       .compact(PluginCompact(symbol: "hammer", text: "1:23", state: .attention)))
        guard case .cards(let cards) = try PluginMessage.decode(line(#"{"type":"cards","cards":[{"title":"Report","state":"failed"}]}"#)) else {
            return XCTFail("not cards")
        }
        XCTAssertEqual(cards.first?.state, .failed)
    }

    /// Protocol 7: sections, toggles and progress on rows, and row actions that ask first
    func testSectionsTogglesProgressAndConfirmsRead() throws {
        guard case .list(let rows) = try PluginMessage.decode(line(#"{"type":"list","rows":[{"title":"Power","kind":"section","detail":"1"},{"id":"awake","title":"Keep awake","toggle":true},{"title":"Upgrading","progress":1.4},{"title":"Odd","kind":"banner"},{"id":"c1","title":"Container","actions":[{"id":"rm","title":"Remove","confirm":"Remove it?"}]}]}"#)) else {
            return XCTFail("not a list")
        }
        XCTAssertEqual(rows.map(\.kind), [.section, .row, .row, .row, .row], "an unknown kind reads as a row")
        XCTAssertEqual(rows[1].toggle, true)
        XCTAssertEqual(rows[2].progress, 1, "clamped")
        XCTAssertEqual(rows[4].actions?.first?.confirm, "Remove it?")
        var content = PluginStore.Content()
        content.rows = rows
        XCTAssertTrue(content.hasAction("rm"))
        XCTAssertFalse(content.hasAction("awake"), "a row's own id isn't an action's")
    }

    func testCardsRead() throws {
        let message = try PluginMessage.decode(line(#"{"type":"cards","cards":[{"id":"c1","title":"Safari","subtitle":"now","image":{"app":"com.apple.Safari"},"preview":{"text":"hello"},"actions":[{"id":"delete:c1","title":"Delete","symbol":"trash"}]},{"title":"a.pdf","preview":{"image":{"file":"/tmp/a.pdf"}},"file":"/tmp/a.pdf"},{"title":"Bare","symbol":"star"}]}"#))
        XCTAssertEqual(message, .cards([
            PluginCard(id: "c1", title: "Safari", subtitle: "now", image: .app("com.apple.Safari"), preview: .text("hello"),
                       actions: [PluginRowAction(id: "delete:c1", title: "Delete", symbol: "trash")]),
            PluginCard(title: "a.pdf", preview: .image(.file("/tmp/a.pdf")), file: "/tmp/a.pdf"),
            PluginCard(title: "Bare", symbol: "star"),
        ]))
        XCTAssertThrowsError(try PluginMessage.decode(line(#"{"type":"cards","cards":[{"title":"x","preview":{}}]}"#)),
                             "a preview says what it shows")
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"clear","target":"cards"}"#)), .clear(.cards))
    }

    func testCardsAreKeptInBounds() throws {
        let many = (0..<80).map { #"{"title":"c\#($0)"}"# }.joined(separator: ",")
        guard case .cards(let cards) = try PluginMessage.decode(line(#"{"type":"cards","cards":[\#(many)]}"#)) else { return XCTFail() }
        XCTAssertEqual(cards.count, PluginMessage.maxItems)

        let long = String(repeating: "x", count: 5000)
        let actions = (0..<10).map { #"{"id":"a\#($0)","title":"t"}"# }.joined(separator: ",")
        guard case .cards(let one) = try PluginMessage.decode(line(#"{"type":"cards","cards":[{"title":"\#(long)","preview":{"text":"\#(long)"},"actions":[\#(actions)]}]}"#)),
              let card = one.first else { return XCTFail() }
        XCTAssertEqual(card.title.count, PluginMessage.maxTextLength)
        XCTAssertEqual(card.preview, .text(String(repeating: "x", count: PluginMessage.maxSubtitleLength)))
        XCTAssertEqual(card.actions?.count, PluginRowAction.maxCount)
    }

    func testDropsReachAPluginThatAcceptsThem() throws {
        XCTAssertEqual(String(decoding: PluginEvent.drop(paths: ["/tmp/a.pdf"], urls: ["https://example.com"]).line, as: UTF8.self),
                       #"{"paths":["\/tmp\/a.pdf"],"type":"drop","urls":["https:\/\/example.com"]}"# + "\n")

        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"dropper","name":"Dropper","symbol":"tray","command":["/bin/cat"],"protocol":5,"accepts":["files"]}"#, id: "dropper", in: folder)
        _ = try writePlugin(#"{"id":"plain","name":"Plain","symbol":"x","command":["/bin/cat"],"protocol":1}"#, id: "plain", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let data = try makeFolder()
        let store = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs, defaults: defaults)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()

        let dropper = IslandTab.tab(forPlugin: "dropper"), plain = IslandTab.tab(forPlugin: "plain")
        XCTAssertTrue(try PluginManifest.load(from: folder.appendingPathComponent("dropper")).acceptsFiles)
        XCTAssertTrue(IslandDropTarget.accepts(dropper, plugins: store))
        XCTAssertFalse(IslandDropTarget.accepts(plain, plugins: store))
        XCTAssertFalse(IslandDropTarget.accepts(.music, plugins: store))
        XCTAssertFalse(IslandDropTarget.accepts(.files, plugins: store), "without the Files plugin, the Files tab takes nothing")

        // A drag goes to the tab showing if it takes drops, or else the first of your tabs that does
        tabs.setEnabled(.files, false)
        tabs.setEnabled(plain, true)
        tabs.setEnabled(dropper, true)
        XCTAssertEqual(IslandDropTarget.tab(preferring: plain, tabs: tabs, plugins: store), dropper)
        XCTAssertEqual(IslandDropTarget.tab(preferring: nil, tabs: tabs, plugins: store), dropper)
        tabs.setEnabled(.files, true)
        XCTAssertEqual(IslandDropTarget.tab(preferring: dropper, tabs: tabs, plugins: store), dropper)
        store.setEnabled("dropper", false)
        XCTAssertFalse(IslandDropTarget.accepts(dropper, plugins: store), "turned off, it takes nothing")
        XCTAssertEqual(IslandDropTarget.textFolder(for: dropper, plugins: store).path,
                       data.appendingPathComponent("dropper/Drops").path, "dropped text goes to the plugin's data folder")
    }

    func testADropIsReadAsPathsAndLinks() async throws {
        let folder = try makeFolder()
        let file = folder.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        let drop = await IslandDrop.read([
            try XCTUnwrap(NSItemProvider(contentsOf: file)),
            NSItemProvider(object: URL(string: "https://example.com/page")! as NSURL),
            NSItemProvider(object: "a note" as NSString),
        ], savingTextIn: folder.appendingPathComponent("Drops"))
        XCTAssertEqual(drop.urls, ["https://example.com/page"])
        XCTAssertEqual(drop.paths.count, 2)
        XCTAssertEqual(drop.paths.first, file.path)
        let note = try XCTUnwrap(drop.paths.last)
        XCTAssertTrue(note.hasPrefix(folder.appendingPathComponent("Drops").path), "text is saved as a file")
        XCTAssertEqual(try String(contentsOfFile: note, encoding: .utf8), "a note")

        XCTAssertEqual(IslandDrop.files([file, URL(string: "https://example.com")!]),
                       IslandDrop(paths: [file.path], urls: ["https://example.com"]))
    }

    func testMediaAndLyricsRead() throws {
        guard case .media(let media) = try PluginMessage.decode(line(#"{"type":"media","title":"Song","artist":"Artist","album":"Album","artwork":{"url":"https://example.com/a.jpg"},"app":"com.spotify.client","playing":true,"elapsed":42,"at":1000,"duration":215,"rate":1}"#))
        else { return XCTFail() }
        XCTAssertEqual(media, PluginMedia(title: "Song", artist: "Artist", album: "Album", artwork: .url(URL(string: "https://example.com/a.jpg")!),
                                          app: "com.spotify.client", playing: true, elapsed: 42, at: 1000, duration: 215, rate: 1))
        guard case .media(let bare) = try PluginMessage.decode(line(#"{"type":"media","title":"Radio","playing":false,"duration":-5,"rate":99}"#))
        else { return XCTFail() }
        XCTAssertNotNil(bare.at, "a position is as of now when the plugin doesn't say")
        XCTAssertNil(bare.duration, "an impossible length is unknown")
        XCTAssertEqual(bare.rate, 16)
        XCTAssertThrowsError(try PluginMessage.decode(line(#"{"type":"media","title":"No state"}"#)), "it says whether it plays")

        let lines = (0..<1200).map { #"{"time":\#($0),"text":"l\#($0)"}"# }.joined(separator: ",")
        guard case .lyrics(let lyrics) = try PluginMessage.decode(line(#"{"type":"lyrics","lines":[\#(lines)]}"#)) else { return XCTFail() }
        XCTAssertEqual(lyrics.count, PluginLyricLine.maxCount)
        XCTAssertEqual(lyrics.line(at: 2.5), "l2")
        XCTAssertEqual(lyrics.line(at: -1), "")
        XCTAssertEqual([PluginLyricLine(text: "a"), PluginLyricLine(text: "b")].plainText, "a\nb")

        XCTAssertEqual(String(decoding: PluginEvent.control("next").line, as: UTF8.self), #"{"command":"next","type":"control"}"# + "\n")
        XCTAssertEqual(String(decoding: PluginEvent.seek(80.5).line, as: UTF8.self), #"{"position":80.5,"type":"seek"}"# + "\n")
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"clear","target":"media"}"#)), .clear(.media))
    }

    func testTheIslandRunsAMediaPosition() {
        let at = Date(timeIntervalSince1970: 1000)
        var media = PluginMedia(title: "Song", playing: true, elapsed: 10, at: 1000, duration: 30, rate: 2)
        XCTAssertEqual(media.position(at: at.addingTimeInterval(5)), 20, "counted on at its rate")
        XCTAssertEqual(media.position(at: at.addingTimeInterval(60)), 30, "never past the end")
        media.playing = false
        XCTAssertEqual(media.position(at: at.addingTimeInterval(5)), 10, "paused, it stays")
        media.duration = nil
        media.playing = true
        XCTAssertEqual(media.position(at: at.addingTimeInterval(100)), 210, "unknown length, it keeps counting")
    }

    func testThePlayingTrackWinsAndTapsGoBackToItsSource() throws {
        let store = PluginStore(pluginsFolder: try makeFolder(), dataFolder: try makeFolder(), tabs: TabStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let nowPlaying = NowPlayingStore()
        nowPlaying.start(plugins: store)
        XCTAssertTrue(nowPlaying.isPlayerIdle)

        store.apply(.media(PluginMedia(title: "Paused", playing: false, at: 0)), from: "a")
        XCTAssertEqual(nowPlaying.current?.source, .plugin("a"))
        store.apply(.media(PluginMedia(title: "Playing", app: "com.spotify.client", playing: true, at: 0)), from: "b")
        XCTAssertEqual(nowPlaying.songTitle, "Playing", "a playing track wins over a paused one")
        XCTAssertEqual(nowPlaying.bundleIdentifier, "com.spotify.client")
        store.apply(.media(PluginMedia(title: "Paused again", playing: false, at: 0)), from: "a")
        XCTAssertEqual(nowPlaying.songTitle, "Playing", "even when the paused one changed last")

        store.apply(.lyrics([PluginLyricLine(time: 0, text: "first"), PluginLyricLine(time: 5, text: "second")]), from: "b")
        XCTAssertTrue(nowPlaying.hasSyncedLyrics)
        store.apply(.media(PluginMedia(title: "Next song", playing: true, at: 0)), from: "b")
        XCTAssertFalse(nowPlaying.hasSyncedLyrics, "another track drops the old one's lyrics")

        nowPlaying.seek(to: 12)
        XCTAssertEqual(nowPlaying.current?.media.elapsed, 12, "a seek shows at once")

        store.apply(.clear(.all), from: "b")
        XCTAssertEqual(nowPlaying.songTitle, "Paused again", "the other source takes over")
        store.apply(.clear(.media), from: "a")
        XCTAssertTrue(nowPlaying.isPlayerIdle)

        let onlyA = NowPlayingStore(only: .plugin("a"))
        onlyA.start(plugins: store)
        store.apply(.media(PluginMedia(title: "B's", playing: true, at: 0)), from: "b")
        XCTAssertTrue(onlyA.isPlayerIdle, "a plugin's tab shows only its own track")
    }

    func testCardsShowAndClear() throws {
        let store = PluginStore(pluginsFolder: try makeFolder(), dataFolder: try makeFolder(), tabs: TabStore(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        store.apply(.cards([PluginCard(id: "c", title: "Card")]), from: "echo")
        store.apply(.list([PluginRow(title: "Row")]), from: "echo")
        XCTAssertEqual(store.contents["echo"]?.cards.map(\.title), ["Card"])
        store.apply(.clear(.cards), from: "echo")
        XCTAssertEqual(store.contents["echo"]?.cards, [])
        XCTAssertEqual(store.contents["echo"]?.rows.map(\.title), ["Row"], "clearing the cards leaves the rows")
        XCTAssertTrue(PluginMessage.cards([]).canBeScheduled)
    }

    // MARK: - Protocol 4

    func testImagesActionsAndPresenceRead() throws {
        let row = try PluginMessage.decode(Data(#"{"type":"list","rows":[{"id":"r","title":"Photo","image":{"file":"/tmp/a.jpg"},"actions":[{"id":"del:r","title":"Delete","symbol":"trash"}]},{"title":"Safari","image":{"app":"com.apple.Safari"}}]}"#.utf8))
        XCTAssertEqual(row, .list([
            PluginRow(id: "r", title: "Photo", image: .file("/tmp/a.jpg"), actions: [PluginRowAction(id: "del:r", title: "Delete", symbol: "trash")]),
            PluginRow(title: "Safari", image: .app("com.apple.Safari")),
        ]))
        let compact = try PluginMessage.decode(Data(#"{"type":"compact","text":"Song","image":{"url":"https://example.com/a.png"}}"#.utf8))
        XCTAssertEqual(compact, .compact(PluginCompact(text: "Song", image: .url(URL(string: "https://example.com/a.png")!))))
        XCTAssertThrowsError(try PluginMessage.decode(Data(#"{"type":"compact","image":{"url":"http://example.com/a.png"}}"#.utf8)),
                             "plain http pictures are refused")
        let many = (0..<10).map { #"{"id":"a\#($0)","title":"t"}"# }.joined(separator: ",")
        guard case .list(let rows) = try PluginMessage.decode(Data(#"{"type":"list","rows":[{"title":"x","actions":[\#(many)]}]}"#.utf8)) else { return XCTFail() }
        XCTAssertEqual(rows.first?.actions?.count, PluginRowAction.maxCount)

        let folder = try makeFolder()
        let plugin = try writePlugin(#"{"id":"bg","name":"Bg","symbol":"x","command":["./x"],"protocol":4,"background":true,"priority":"high"}"#, id: "bg", in: folder)
        let manifest = try PluginManifest.load(from: plugin)
        XCTAssertTrue(manifest.runsInBackground)
        XCTAssertEqual(manifest.priority, .high)
    }

    func testAHighPriorityPluginShowsAheadOfPopupsAndMusic() {
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: true, pluginPopup: true, music: true, pluginCompact: true), .priorityPlugin)
        XCTAssertEqual(LiveActivity.pick(priorityPlugin: false, pluginPopup: false, music: true, pluginCompact: true), .music)
    }

    func testABackgroundPluginRunsWithoutItsTabUnlessTurnedOff() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"bg","name":"Bg","symbol":"x","command":["/bin/cat"],"protocol":4,"background":true,"priority":"high"}"#, id: "bg", in: folder)
        _ = try writePlugin(#"{"id":"tabbed","name":"Tabbed","symbol":"x","command":["/bin/cat"],"protocol":1}"#, id: "tabbed", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, dataFolder: try makeFolder(), tabs: tabs, defaults: defaults)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        XCTAssertNotNil(store.processID(of: "bg"), "runs with no tab")
        XCTAssertNil(store.processID(of: "tabbed"), "a plain plugin still waits for its tab")

        store.apply(.compact(PluginCompact(text: "Working")), from: "bg")
        XCTAssertEqual(store.priorityPlugin?.compact.text, "Working", "its compact content is the high-priority one")
        XCTAssertNil(store.compactPlugin)

        store.setEnabled("bg", false)
        XCTAssertFalse(store.isEnabled("bg"))
        XCTAssertNil(store.processID(of: "bg"), "turned off: it stops")
        XCTAssertNil(store.priorityPlugin)
        store.setEnabled("bg", true)
        XCTAssertNotNil(store.processID(of: "bg"))
        store.stop()
    }

    // MARK: - Bundled plugins

    func testBundledPluginsDrawTheirBuiltInTabAndCanBeTurnedOff() throws {
        let bundled = try makeFolder()
        let programs = try makeFolder()
        let user = try makeFolder()
        _ = try writePlugin(#"{"id":"agents","name":"Agents","symbol":"terminal","command":["./agents"],"protocol":4,"background":true,"priority":"high"}"#,
                            id: "agents", in: bundled)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/cat"), to: programs.appendingPathComponent("agents"))
        _ = try writePlugin(#"{"id":"agents","name":"Mine","symbol":"x","command":["/bin/cat"],"protocol":1}"#, id: "agents", in: user)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: user, dataFolder: try makeFolder(), tabs: tabs, defaults: defaults,
                                bundledFolder: bundled, bundledProgramFolder: programs)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()

        XCTAssertEqual(store.installed.map(\.id), ["agents"])
        XCTAssertTrue(store.installed[0].isBundled)
        XCTAssertEqual(store.broken.map(\.reason), ["the app has a plugin with this id"], "yours doesn't replace the app's")
        XCTAssertFalse(tabs.pluginTabs.contains(.plugin("agents")), "it takes over the built-in tab instead of adding one")
        XCTAssertTrue(store.isEnabled("agents"), "on from the start")
        XCTAssertNotNil(store.processID(of: "agents"), "its program runs from the app's Helpers, tab or not (background)")
        XCTAssertEqual(store.replacesBuiltInTab(.agents), "agents")
        XCTAssertEqual(IslandTab.tab(forPlugin: "agents"), .agents)

        store.setEnabled("agents", false)
        XCTAssertNil(store.processID(of: "agents"), "turned off in Settings > Plugins: it stops")
        XCTAssertEqual(store.replacesBuiltInTab(.agents), "agents", "and its tab says so")
        store.setEnabled("agents", true)
        XCTAssertNotNil(store.processID(of: "agents"))
        store.stop()
    }

    func testEachBundledPluginDescribesItselfAsItsPluginJSON() throws {
        for (id, tab) in IslandTab.builtInTabsOfPlugins {
            let program = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(id)")
            let process = Process()
            process.executableURL = program
            process.arguments = ["--describe"]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let described = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let folder = try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("Plugins/\(id)")
            let shipped = try Data(contentsOf: folder.appendingPathComponent("plugin.json"))
            XCTAssertEqual(try JSONSerialization.jsonObject(with: described) as? NSDictionary, try JSONSerialization.jsonObject(with: shipped) as? NSDictionary,
                           "BundledPlugins/\(id)/plugin.json is out of date: write it again with `\(id) --describe`")
            XCTAssertNoThrow(try PluginManifest.load(from: folder))
            XCTAssertEqual(IslandTab.tab(forPlugin: id), tab, "\(id) draws its built-in tab")
        }
        let files = try PluginManifest.load(from: try XCTUnwrap(Bundle.main.resourceURL).appendingPathComponent("Plugins/files"))
        XCTAssertTrue(files.acceptsFiles, "Files takes drops")
    }

    /// The bundled Agents plugin, turned on, on a socket of its own
    private func startAgentsPlugin() throws -> (store: PluginStore, socket: URL) {
        let socketFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ag-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: socketFolder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: socketFolder) }
        let socket = socketFolder.appendingPathComponent("h.sock")
        setenv("ISLAND_AGENTS_SOCKET", socket.path, 1)
        addTeardownBlock { unsetenv("ISLAND_AGENTS_SOCKET") }

        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let (preferences, _) = makePreferences()
        let store = PluginStore(pluginsFolder: try makeFolder(), dataFolder: try makeFolder(), tabs: TabStore(defaults: defaults),
                                preferences: preferences, defaults: defaults,
                                bundledFolder: Bundle.main.resourceURL?.appendingPathComponent("Plugins"),
                                bundledProgramFolder: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers"))
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        let manifest = try XCTUnwrap(store.installed.first { $0.id == "agents" }?.manifest)
        if let sounds = manifest.preferences?.first(where: { $0.key == "sounds" }) {
            preferences.set(.bool(false), of: sounds, for: "agents")
        }
        store.setEnabled("agents", true)
        XCTAssertTrue(waitUntil(5) { FileManager.default.fileExists(atPath: socket.path) }, "the plugin opened its socket")
        return (store, socket)
    }

    /// Runs the hook as Claude Code does for a request that waits for an answer; its stdout is the answer
    private func askThroughTheHook(_ input: String, socket: URL) throws -> (process: Process, output: Pipe) {
        let helper = Process()
        helper.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/island-claude-hook")
        helper.arguments = [socket.path, "claude", "wait"]
        let stdin = Pipe(), stdout = Pipe()
        helper.standardInput = stdin
        helper.standardOutput = stdout
        try helper.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        return (helper, stdout)
    }

    private func hookOutput(_ pipe: Pipe, of process: Process) -> [String: Any]? {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["hookSpecificOutput"] as? [String: Any]
    }

    /// The whole path, as Claude Code would use it: the hook asks, the Agents plugin shows the request through
    /// the plugin protocol, a tap on Allow goes back to the plugin, and the hook prints the decision
    func testTheAgentsPluginAnswersAPermissionRequestFromTheIsland() throws {
        let (store, socket) = try startAgentsPlugin()
        let hook = try askThroughTheHook(#"{"session_id":"e2e","hook_event_name":"PermissionRequest","cwd":"/tmp/demo","tool_name":"Bash","tool_input":{"command":"make test"}}"#,
                                         socket: socket)
        XCTAssertTrue(waitUntil(5) { store.contents["agents"]?.buttons.contains { $0.title == "Allow" } == true }, "the request shows with its buttons")
        let rows = store.contents["agents"]?.rows ?? []
        XCTAssertTrue(rows.contains { $0.subtitle == "make test" || $0.title.contains("make test") }, "\(rows)")
        XCTAssertEqual(rows.first?.state, .attention, "the request's row says the agent needs you: \(rows)")
        XCTAssertNotNil(store.priorityPlugin, "and beside the notch, ahead of music")
        XCTAssertEqual(store.contents["agents"]?.compact?.state, .attention, "and so does the glyph beside the notch")

        let allow = try XCTUnwrap(store.contents["agents"]?.buttons.first { $0.title == "Allow" })
        let tapped = Date()
        store.send(.action(allow.id), to: "agents")
        let output = hookOutput(hook.output, of: hook.process)
        let roundTrip = Date().timeIntervalSince(tapped)
        print("Agents plugin: tap to hook output in \(Int(roundTrip * 1000)) ms")
        XCTAssertEqual((output?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        XCTAssertLessThan(roundTrip, 0.5)
        store.stop()
    }

    func testTheAgentsPluginComesBackAfterACrash() throws {
        let (store, socket) = try startAgentsPlugin()
        let first = try XCTUnwrap(store.processID(of: "agents"))
        kill(first, SIGKILL)
        XCTAssertTrue(waitUntil(5) { (store.processID(of: "agents") ?? first) != first }, "restarted")
        // Meanwhile a hook finds nobody and leaves the question to the terminal. Once the new process shows
        // something it is listening again (it opens the socket before its first render), and it answers again
        XCTAssertTrue(waitUntil(5) { store.contents["agents"]?.rows.isEmpty == false })
        let hook = try askThroughTheHook(#"{"session_id":"e2e","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#,
                                         socket: socket)
        XCTAssertTrue(waitUntil(5) { store.contents["agents"]?.buttons.contains { $0.title == "Deny" } == true })
        let deny = try XCTUnwrap(store.contents["agents"]?.buttons.first { $0.title == "Deny" })
        store.send(.action(deny.id), to: "agents")
        XCTAssertEqual((hookOutput(hook.output, of: hook.process)?["decision"] as? [String: Any])?["behavior"] as? String, "deny")
        store.stop()
    }

    func testTheAgentsPluginAnswersAQuestionWithATap() throws {
        let (store, socket) = try startAgentsPlugin()
        let hook = try askThroughTheHook("""
            {"session_id":"e2e","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion",\
            "tool_input":{"questions":[{"question":"Which layout?","header":"Layout","multiSelect":false,\
            "options":[{"label":"Grid","description":"Cards in rows"},{"label":"List"}]}]}}
            """, socket: socket)
        XCTAssertTrue(waitUntil(5) { store.contents["agents"]?.rows.contains { $0.title == "List" } == true }, "the options show as rows")
        let list = try XCTUnwrap(store.contents["agents"]?.rows.first { $0.title == "List" }?.id)
        store.send(.action(list), to: "agents")
        let output = hookOutput(hook.output, of: hook.process)
        let answers = ((output?["decision"] as? [String: Any])?["updatedInput"] as? [String: Any])?["answers"] as? [String: String]
        XCTAssertEqual(answers, ["Which layout?": "List"], "one choice answers on tap")
        XCTAssertTrue(waitUntil(2) { store.contents["agents"]?.rows.contains { $0.title == "List" } != true }, "and the prompt goes")
        store.stop()
    }

    // MARK: - On demand

    func testTimelineDoneAndStatusRead() throws {
        let line = #"{"type":"timeline","entries":[{"at":200,"show":[{"type":"compact","text":"B"},{"type":"popup","text":"no"}]},{"at":100,"show":[{"type":"list","rows":[{"title":"A"}]}]}],"wake":300}"#
        guard case .timeline(var schedule) = try PluginMessage.decode(Data(line.utf8)) else { return XCTFail("not a timeline") }
        XCTAssertEqual(schedule.nextDate, Date(timeIntervalSince1970: 100), "entries are sorted")
        var due = schedule.takeDue(at: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(due.messages, [.list([PluginRow(title: "A")])])
        XCTAssertFalse(due.wake)
        due = schedule.takeDue(at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(due.messages, [.compact(PluginCompact(text: "B"))], "a popup can't be scheduled")
        XCTAssertTrue(due.wake)
        XCTAssertTrue(schedule.isEmpty)

        XCTAssertEqual(try PluginMessage.decode(Data(#"{"type":"done"}"#.utf8)), .done)
        XCTAssertEqual(try PluginMessage.decode(Data(#"{"type":"status","state":"loading"}"#.utf8)), .status(PluginNotice(state: .loading, text: nil)))
        XCTAssertEqual(try PluginMessage.decode(Data(#"{"type":"status","state":"idle"}"#.utf8)), .status(nil))
        XCTAssertEqual(String(decoding: PluginEvent.wake(reason: "timeline").line, as: UTF8.self), #"{"reason":"timeline","type":"wake"}"# + "\n")
    }

    /// A store with one on-demand plugin running `script` in sh, its tab on
    private func onDemandStore(_ script: String) throws -> (PluginStore, URL) {
        let folder = try makeFolder()
        let data = try makeFolder()
        let command = try String(data: JSONSerialization.data(withJSONObject: ["/bin/sh", "-c", script]), encoding: .utf8)!
        _ = try writePlugin(#"{"id":"cal","name":"Cal","symbol":"calendar","command":\#(command),"protocol":3,"lifecycle":"onDemand"}"#,
                            id: "cal", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: UserDefaults(suiteName: suiteName)!)
        let store = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        store.reload()
        tabs.setEnabled(.plugin("cal"), true)
        store.reload()
        return (store, data.appendingPathComponent("cal/in.txt"))
    }

    private func lines(of file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    /// Logs what it hears; on each wake it shows something and says it's done
    private let politeScript = #"""
    while read line; do
      echo "$line" >> "$ISLAND_DATA_DIR/in.txt"
      case "$line" in *'"type":"wake"'*) printf '{"type":"compact","text":"hi"}\n{"type":"done"}\n';; esac
    done
    """#

    func testAnOnDemandPluginRunsOnlyWhenNeeded() throws {
        let (store, input) = try onDemandStore(politeScript)
        XCTAssertTrue(waitUntil(3) { store.statuses["cal"] == .sleeping }, "started once to show itself, then asleep")
        XCTAssertEqual(store.contents["cal"]?.compact?.text, "hi", "what it showed stays while it sleeps")
        XCTAssertNil(store.processID(of: "cal"))
        XCTAssertEqual(lines(of: input), [#"{"tab":false,"type":"visible"}"#, #"{"reason":"launch","type":"wake"}"#])

        store.send(.action("refresh"), to: "cal")
        XCTAssertTrue(waitUntil(3) { lines(of: input).count == 5 && store.statuses["cal"] == .sleeping })
        XCTAssertEqual(lines(of: input).suffix(3), [#"{"tab":false,"type":"visible"}"#, #"{"id":"refresh","type":"action"}"#,
                                                    #"{"reason":"action","type":"wake"}"#], "the tap that woke it comes first")

        store.tabAppeared("cal")
        XCTAssertTrue(waitUntil(3) { lines(of: input).last == #"{"reason":"visible","type":"wake"}"# })
        XCTAssertTrue(lines(of: input).contains(#"{"tab":true,"type":"visible"}"#))
        store.tabDisappeared("cal")
        store.stop()
    }

    func testATimelineShowsLaterAndWakesThePlugin() throws {
        let (store, input) = try onDemandStore(politeScript)
        XCTAssertTrue(waitUntil(3) { store.statuses["cal"] == .sleeping })
        let soon = Date().addingTimeInterval(0.3)
        store.apply(.timeline(PluginSchedule(entries: [.init(at: soon, messages: [.compact(PluginCompact(text: "later"))])],
                                             wake: soon.addingTimeInterval(0.3))), from: "cal")
        XCTAssertTrue(waitUntil(2) { store.contents["cal"]?.compact?.text == "later" }, "switched by the island, plugin asleep")
        XCTAssertTrue(waitUntil(3) { lines(of: input).last == #"{"reason":"timeline","type":"wake"}"# }, "woken when it asked")
        XCTAssertTrue(waitUntil(3) { store.contents["cal"]?.compact?.text == "hi" && store.statuses["cal"] == .sleeping })
        store.stop()
    }

    func testAnOnDemandPluginLeftIdleIsStopped() throws {
        let (store, _) = try onDemandStore("cat > /dev/null")
        store.idleTimeout = 0.3
        store.send(.action("x"), to: "cal")
        XCTAssertTrue(waitUntil(1) { store.processID(of: "cal") != nil })
        XCTAssertTrue(waitUntil(3) { store.processID(of: "cal") == nil && store.statuses["cal"] == .sleeping },
                      "it never said done, so it is stopped once idle")
        store.stop()
    }

    func testAnOnDemandPluginThatKeepsFailingIsGivenUp() throws {
        let (store, _) = try onDemandStore("echo broken >&2; exit 3")
        for _ in 0..<8 {
            XCTAssertTrue(waitUntil(2) { store.processID(of: "cal") == nil })
            store.send(.action("again"), to: "cal")
        }
        XCTAssertTrue(waitUntil(2) {
            if case .stopped = store.statuses["cal"] { return true }
            return false
        })
        XCTAssertEqual(store.statuses["cal"], .stopped(reason: "broken"))
        store.restart("cal")
        XCTAssertNotEqual(store.statuses["cal"], .stopped(reason: "broken"), "Restart tries again")
        store.stop()
    }

    // MARK: - Process lifecycle

    private func client(_ command: [String]) -> PluginClient {
        PluginClient(manifest: manifest(command: command), folder: FileManager.default.temporaryDirectory,
                     dataFolder: FileManager.default.temporaryDirectory, restartDelay: 60)
    }

    /// Whether any process is left in the group
    private func groupAlive(_ pgid: pid_t) -> Bool { kill(-pgid, 0) == 0 }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func testAPluginThatDoesntReadNeverBlocksTheIsland() throws {
        let client = client(["/bin/sleep", "30"])
        client.start()
        let process = try XCTUnwrap(client.process)
        let started = Date()
        var dropped = 0
        for _ in 0..<100_000 where !process.write(PluginEvent.visible(true).line) { dropped += 1 }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "writing never waits for the plugin")
        XCTAssertGreaterThan(dropped, 0, "past the limit, events are dropped")
        client.stop()
    }

    func testAPluginThatIgnoresTerminationIsKilledWithWhatItStarted() throws {
        // Ignores SIGTERM and doesn't read, and starts a child of its own
        let client = client(["/usr/bin/perl", "-e", #"$SIG{TERM}="IGNORE"; system("sleep 30 &"); sleep 30"#])
        client.start()
        let pgid = try XCTUnwrap(client.process?.pid)
        XCTAssertTrue(waitUntil(2) { groupAlive(pgid) })
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        client.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(groupAlive(pgid), "it gets its grace period")
        XCTAssertTrue(waitUntil(PluginClient.terminationGrace + 1) { !groupAlive(pgid) }, "then it and its child are killed")
    }

    func testQuittingTheAppEndsEveryPlugin() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"stubborn","name":"x","symbol":"x","command":["/usr/bin/perl","-e","$SIG{TERM}=\"IGNORE\"; sleep 30"],"protocol":1}"#,
                            id: "stubborn", in: folder)
        let (store, tabs) = try makeStore(folder: folder)
        tabs.setEnabled(.plugin("stubborn"), true)
        store.reload()  // what start()'s subscription to your tabs does in the app
        XCTAssertTrue(waitUntil(2) { store.statuses["stubborn"] == .running })
        let pgid = try XCTUnwrap(store.processID(of: "stubborn"))

        let started = Date()
        store.stopForQuit()
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "quitting waits briefly")
        XCTAssertTrue(waitUntil(1) { !groupAlive(pgid) }, "and leaves nothing behind")
    }

    func testANextLaunchEndsPluginsACrashLeftBehind() throws {
        let folder = try makeFolder()
        let data = try makeFolder()
        // Ignores SIGTERM and never reads, so the end of its input after a crash doesn't make it quit
        _ = try writePlugin(#"{"id":"stubborn","name":"x","symbol":"x","command":["/usr/bin/perl","-e","$SIG{TERM}=\"IGNORE\"; sleep 30"],"protocol":1}"#,
                            id: "stubborn", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        tabs.setPluginTabs([(.plugin("stubborn"), TabStore.TabInfo(name: "x", symbol: "x"))])
        tabs.setEnabled(.plugin("stubborn"), true)
        let running = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs)
        running.reload()
        let pgid = try XCTUnwrap(running.processID(of: "stubborn"))
        // The app "crashes": nothing stops it. The next launch, with the plugin's tab off:
        let suite2 = "PluginTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite2) }
        let nextLaunch = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: TabStore(defaults: UserDefaults(suiteName: suite2)!))
        nextLaunch.start()
        XCTAssertTrue(waitUntil(1) { !groupAlive(pgid) }, "the leftover plugin is ended")
        nextLaunch.stop()
    }

    func testAPluginLearnsWhereItRuns() throws {
        let data = try makeFolder()
        let client = PluginClient(
            manifest: manifest(command: ["/bin/sh", "-c", #"printf '{"type":"compact","text":"%s|%s|%s"}\n' "$ISLAND_PROTOCOL" "$ISLAND_PLUGIN_ID" "$ISLAND_DATA_DIR"; sleep 5"#]),
            folder: FileManager.default.temporaryDirectory, dataFolder: data, restartDelay: 60)
        let received = expectation(description: "environment")
        client.onMessage = { message in
            XCTAssertEqual(message, .compact(PluginCompact(text: "\(PluginManifest.supportedProtocol)|echo|\(data.path)")))
            received.fulfill()
        }
        client.start()
        wait(for: [received], timeout: 5)
        client.stop()
    }

    // MARK: - Store: status, visibility, open

    private func makeStore(folder: URL) throws -> (PluginStore, TabStore) {
        let suiteName = "PluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: defaults)
        let store = PluginStore(pluginsFolder: folder, dataFolder: try makeFolder(), tabs: tabs, restartDelay: 0.05)
        store.reload()
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
        return (store, tabs)
    }

    func testAStoppedPluginSaysSoAndCanBeRestarted() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"crashy","name":"Crashy","symbol":"x","command":["/bin/sh","-c","echo broken config >&2; exit 3"],"protocol":1}"#,
                            id: "crashy", in: folder)
        let (store, tabs) = try makeStore(folder: folder)
        tabs.setEnabled(.plugin("crashy"), true)
        store.reload()  // what start()'s subscription to your tabs does in the app
        XCTAssertTrue(waitUntil(5) { store.statuses["crashy"] == .stopped(reason: "broken config") },
                      "its last error says why; got \(String(describing: store.statuses["crashy"]))")

        store.restart("crashy")
        XCTAssertNotEqual(store.statuses["crashy"], .stopped(reason: "broken config"), "a restart starts afresh")
    }

    func testTheTabIsVisibleWhileAnyIslandShowsIt() throws {
        let folder = try makeFolder()
        // Echoes each visible event back as compact text
        _ = try writePlugin(#"{"id":"seen","name":"x","symbol":"x","command":["/usr/bin/sed","-l","-E","s/.*\"tab\":(true|false).*/{\"type\":\"compact\",\"text\":\"\\1\"}/"],"protocol":1}"#,
                            id: "seen", in: folder)
        let (store, tabs) = try makeStore(folder: folder)
        tabs.setEnabled(.plugin("seen"), true)
        store.reload()  // what start()'s subscription to your tabs does in the app
        func shown() -> String? { store.contents["seen"]?.compact?.text }
        XCTAssertTrue(waitUntil(2) { shown() == "false" }, "it hears right away that its tab isn't showing")

        store.tabAppeared("seen")
        XCTAssertTrue(waitUntil(2) { shown() == "true" })
        store.tabAppeared("seen")    // a second display
        store.tabDisappeared("seen")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(shown(), "true", "still showing on the other display")
        store.tabDisappeared("seen")
        XCTAssertTrue(waitUntil(2) { shown() == "false" })
    }

    func testAPluginOpensTheIslandOnlyOnItsTabAndNotTooOften() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"opener","name":"x","symbol":"x","command":["/bin/cat"],"protocol":1}"#, id: "opener", in: folder)
        let (store, tabs) = try makeStore(folder: folder)
        var opened: [String] = []
        var closed: [String] = []
        store.onOpen = { id, hold in opened.append(hold ? "\(id) held" : id) }
        store.onClose = { closed.append($0) }

        store.apply(.open(hold: false), from: "opener")
        XCTAssertEqual(opened, [], "its tab isn't one of yours")
        tabs.setEnabled(.plugin("opener"), true)
        store.apply(.open(hold: true), from: "opener")
        store.apply(.open(hold: false), from: "opener")
        XCTAssertEqual(opened, ["opener held"], "once, then not again within \(PluginStore.openInterval) seconds")
        store.apply(.close, from: "opener")
        XCTAssertEqual(closed, ["opener"], "close lets go of what hold kept open")
    }

    // MARK: - New messages and countdown

    func testInputOpenConfirmAndCountdownRead() throws {
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"open"}"#)), .open(hold: false))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"open","hold":true}"#)), .open(hold: true))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"close"}"#)), .close)
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"input","id":"m","placeholder":"Minutes"}"#)),
                       .input(PluginInput(id: "m", placeholder: "Minutes")))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"buttons","buttons":[{"id":"s","title":"Stop","confirm":"Sure?"}]}"#)),
                       .buttons([PluginButton(id: "s", title: "Stop", confirm: "Sure?")]))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"compact","until":100,"total":60}"#)),
                       .compact(PluginCompact(until: 100, total: 60)))
        XCTAssertEqual(try PluginMessage.decode(line(#"{"type":"clear","target":"input"}"#)), .clear(.input))
        XCTAssertEqual(String(decoding: PluginEvent.submit(id: "m", text: "5").line, as: UTF8.self),
                       #"{"id":"m","text":"5","type":"submit"}"# + "\n")
    }

    func testTheIslandCountsDown() {
        let now = Date(timeIntervalSince1970: 1000)
        let compact = PluginCompact(text: "ignored", until: 1299.2, total: 300)
        XCTAssertEqual(compact.displayText(at: now), "05:00", "rounded up: 299.2 seconds left reads 05:00")
        XCTAssertEqual(compact.displayProgress(at: now)!, 299.2 / 300, accuracy: 0.0001)
        XCTAssertEqual(compact.displayText(at: Date(timeIntervalSince1970: 2000)), "00:00", "it stops at zero")
        XCTAssertEqual(PluginCountdown.text(remaining: 3725), "1:02:05")
        XCTAssertEqual(PluginCompact(text: "hi").displayText(at: now), "hi", "without until, the plugin's text")
    }

    func testAnUnpublishedCatalogIsntAnError() async throws {
        let client = PluginCatalogClient(pluginsFolder: try makeFolder())
        do {
            _ = try await client.fetchIndex(from: try makeFolder().appendingPathComponent("index.json"))
            XCTFail("expected notPublished")
        } catch PluginCatalogClient.CatalogError.notPublished {
        }
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
        let store = PluginStore(pluginsFolder: folder, dataFolder: try makeFolder(), tabs: tabs)
        addTeardownBlock { await MainActor.run { store.stopForQuit() } }
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

    // MARK: - The hub

    func testAChecksumGuardsAnInstallAndALocalZipInstalls() async throws {
        let repo = try makeFolder()
        let installed = try makeFolder()
        let source = try writePlugin(#"{"id":"timer","name":"Timer","symbol":"timer","command":["./timer"],"protocol":1,"version":"1.0.0"}"#,
                                     id: "timer", in: repo)
        let archive = repo.appendingPathComponent("timer.zip")
        try zip(source, to: archive)
        var client = PluginCatalogClient(pluginsFolder: installed)
        client.movesToTrash = false

        var entry = PluginCatalogEntry(id: "timer", name: "Timer", version: "1.0.0", protocol: 1, archive: archive)
        entry.sha256 = String(repeating: "0", count: 64)
        do {
            try await client.install(entry)
            XCTFail("a download that doesn't match the index's checksum is refused")
        } catch let error as PluginCatalogClient.CatalogError {
            XCTAssertEqual(error, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.appendingPathComponent("timer").path))

        entry.sha256 = try PluginCatalogClient.sha256(of: archive).uppercased()
        var phases: [PluginCatalogClient.Phase] = []
        try await client.install(entry) { phases.append($0) }
        XCTAssertEqual(phases, [.downloading, .verifying, .installing])
        XCTAssertEqual(try PluginManifest.load(from: installed.appendingPathComponent("timer")).version, "1.0.0")

        // The index says one version, the archive holds another
        entry.sha256 = nil
        entry = PluginCatalogEntry(id: "timer", name: "Timer", version: "9.0.0", protocol: 1, archive: archive)
        do {
            try await client.install(entry)
            XCTFail("a mismatched version is refused")
        } catch let error as PluginCatalogClient.CatalogError {
            XCTAssertEqual(error, .wrongVersion(expected: "9.0.0", found: "1.0.0"))
        }

        // From this Mac: a zip, or the folder itself
        try client.remove("timer")
        let fromZip = try await client.install(from: archive)
        XCTAssertEqual(fromZip.id, "timer")
        try client.remove("timer")
        let fromFolder = try await client.install(from: source)
        XCTAssertEqual(fromFolder.id, "timer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "a folder is copied, not moved")
        do {
            _ = try await client.install(from: repo.appendingPathComponent("nothing.txt"))
            XCTFail("not a plugin")
        } catch {}
    }

    func testTheCatalogKnowsWhichInstalledPluginsHaveUpdates() throws {
        let folder = try makeFolder()
        _ = try writePlugin(#"{"id":"timer","name":"Timer","symbol":"timer","command":["/bin/cat"],"protocol":1,"version":"1.2.0"}"#, id: "timer", in: folder)
        _ = try writePlugin(#"{"id":"notes","name":"Notes","symbol":"note","command":["/bin/cat"],"protocol":1,"version":"2.0.0"}"#, id: "notes", in: folder)
        let (store, _) = try makeStore(folder: folder)
        let catalog = PluginCatalogStore(plugins: store, cacheFile: try makeFolder().appendingPathComponent("catalog.json"))
        let archive = folder.appendingPathComponent("x.zip")
        catalog.use([
            PluginCatalogEntry(id: "timer", name: "Timer", version: "1.10.0", protocol: 1, archive: archive),
            PluginCatalogEntry(id: "notes", name: "Notes", version: "1.9.0", protocol: 1, archive: archive),
            PluginCatalogEntry(id: "new", name: "Brand New", version: "1.0.0", protocol: 1, description: "Shiny", archive: archive, author: "someone"),
            PluginCatalogEntry(id: "future", name: "Future", version: "1.0.0", protocol: 99, archive: archive),
        ])
        XCTAssertEqual(catalog.updates.map(\.id), ["timer"], "1.10 is newer than 1.2; 1.9 is older than 2.0")
        XCTAssertEqual(catalog.update(for: "timer")?.entry.version, "1.10.0")
        XCTAssertEqual(catalog.available.map(\.id), ["new", "future"], "what isn't installed")
        catalog.search = "shiny"
        XCTAssertEqual(catalog.available.map(\.id), ["new"], "found by its description")
        catalog.search = "SOMEONE"
        XCTAssertEqual(catalog.available.map(\.id), ["new"], "found by its author")
        XCTAssertEqual(catalog.available[0].summary, "1.0.0 · by someone")
        store.stop()
    }

    func testAnOnDemandPluginShowsWhatItLeftWithoutRunningAgain() throws {
        let folder = try makeFolder()
        let data = try makeFolder()
        let command = try String(data: JSONSerialization.data(withJSONObject: ["/bin/sh", "-c", politeScript]), encoding: .utf8)!
        _ = try writePlugin(#"{"id":"cal","name":"Cal","symbol":"calendar","command":\#(command),"protocol":3,"lifecycle":"onDemand"}"#,
                            id: "cal", in: folder)
        let suiteName = "PluginTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let tabs = TabStore(defaults: UserDefaults(suiteName: suiteName)!)
        let first = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs)
        first.reload()
        tabs.setEnabled(.plugin("cal"), true)
        first.reload()
        XCTAssertTrue(waitUntil(3) { first.statuses["cal"] == .sleeping && first.contents["cal"]?.compact?.text == "hi" })
        first.stopForQuit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: data.appendingPathComponent("cal/.shown.json").path), "what it showed is kept")

        // The next launch: shown at once, without running it
        let input = data.appendingPathComponent("cal/in.txt")
        let heard = lines(of: input).count
        let second = PluginStore(pluginsFolder: folder, dataFolder: data, tabs: tabs)
        addTeardownBlock { await MainActor.run { second.stopForQuit() } }
        second.reload()
        XCTAssertEqual(second.statuses["cal"], .sleeping)
        XCTAssertEqual(second.contents["cal"]?.compact?.text, "hi")
        XCTAssertNil(second.processID(of: "cal"))
        XCTAssertFalse(waitUntil(0.5) { lines(of: input).count > heard }, "it wasn't started")

        // A tap still wakes it
        second.send(.action("refresh"), to: "cal")
        XCTAssertTrue(waitUntil(3) { lines(of: input).count > heard && second.statuses["cal"] == .sleeping })
        second.stop()
    }
}
