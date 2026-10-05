import Foundation
import AppKit
import Combine
import Darwin
import os

/// The installed plugins and what each wants shown. A plugin runs (PluginClient) while its tab is one of
/// your tabs; its compact content and popups take the slot beside the notch after agents (popups also ahead of
/// now playing, PluginCompact after it)
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore(pluginsFolder: defaultFolder, dataFolder: defaultDataFolder, tabs: .shared, preferences: .shared,
                                    bundledFolder: Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true),
                                    bundledProgramFolder: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true))

    /// What one plugin last asked to show
    struct Content: Equatable {
        var compact: PluginCompact?
        var rows: [PluginRow] = []
        var cards: [PluginCard] = []
        /// What it plays (protocol 5), and that track's lyrics
        var media: PluginMedia?
        var lyrics: [PluginLyricLine] = []
        var buttons: [PluginButton] = []
        var input: PluginInput?
        /// "Loading" or "couldn't load", drawn as one standard row
        var notice: PluginNotice?
    }

    /// Whether a plugin of one of your tabs is running, or why it isn't
    enum Status: Equatable {
        case running
        case stopped(reason: String)
        /// A required preference is empty, so it isn't started (Settings > Plugins)
        case needsSetup
        /// Runs on demand and isn't running now; what it showed stays
        case sleeping
    }

    struct Installed: Identifiable, Equatable {
        let manifest: PluginManifest
        let folder: URL
        /// Ships inside the app: updated with it, and can be turned off but not removed
        var isBundled = false
        /// Where its program is, when not in its folder: a bundled plugin's is in the app's Contents/Helpers,
        /// since code can't sit among resources in a signed app
        var programFolder: URL?
        var id: String { manifest.id }

        var executableURL: URL { manifest.executableURL(in: programFolder ?? folder) }
    }

    struct ActivePopup: Equatable {
        let pluginID: String
        let popup: PluginPopup
        /// Tells two equal popups in a row apart, so the second one restarts the timer
        let serial: Int
    }

    @Published private(set) var installed: [Installed] = []
    /// Folders in the plugins folder that aren't usable plugins, with the reason (shown in Settings)
    @Published private(set) var broken: [(folder: String, reason: String)] = []
    @Published private(set) var contents: [String: Content] = [:]
    @Published private(set) var popup: ActivePopup?
    /// Whether each plugin of your tabs runs, or why it stopped for good; shown in its tab and in Settings
    @Published private(set) var statuses: [String: Status] = [:]

    /// `~/Library/Application Support/MacDynamicIsland/Plugins`: one folder per plugin
    let pluginsFolder: URL
    /// `~/Library/Application Support/MacDynamicIsland/PluginData`: one folder per plugin for what it keeps
    /// (ISLAND_DATA_DIR), apart from its install folder so an update doesn't wipe it
    let dataFolder: URL
    /// Opens the island on a plugin's tab ({"type":"open"}); IslandController sets it
    var onOpen: (_ pluginID: String, _ hold: Bool) -> Void = { _, _ in }
    /// Closes the islands a plugin opened with `hold` ({"type":"close"}); IslandController sets it
    var onClose: (String) -> Void = { _ in }

    /// One plugin opens the island at most this often
    static let openInterval: TimeInterval = 10

    private let tabs: TabStore
    private let defaults: UserDefaults
    /// The plugins inside the app (Contents/Resources/Plugins), and where their programs are
    let bundledFolder: URL?
    let bundledProgramFolder: URL?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "Plugin")
    private var clients: [String: PluginClient] = [:]
    private var tabsCancellable: AnyCancellable?
    private var popupSerial = 0
    private var popupDismissal: DispatchWorkItem?
    /// How many of the islands show each plugin's tab right now (one per display with "all screens" on)
    private var visibleCounts: [String: Int] = [:]
    private var lastOpened: [String: Date] = [:]
    /// What each plugin's files looked like when it was last started, to tell which ones changed
    private var fingerprints: [String: Fingerprint] = [:]
    private var folderMonitor: PluginFolderMonitor?
    let preferences: PluginPreferencesStore
    private var preferencesCancellable: AnyCancellable?
    /// Preference changes wait this long for more (typing) before they go to the plugin
    static let preferencesDelay: TimeInterval = 0.5
    private var pendingPreferences: [String: DispatchWorkItem] = [:]

    // Plugins that run on demand (PluginLifecycle.onDemand)
    /// What each one left to show later, and when to wake it
    private var schedules: [String: PluginSchedule] = [:]
    private var scheduleTimer: Timer?
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var idleTimeouts: [String: DispatchWorkItem] = [:]
    private var lastTimelineWake: [String: Date] = [:]
    /// When each one last exited with an error, to give up on one that keeps failing
    private var recentFailures: [String: [Date]] = [:]
    /// One left running with its tab hidden and nothing to say is stopped after this
    var idleTimeout: TimeInterval = 30
    /// A timeline wakes one plugin at most this often
    static let minimumWakeInterval: TimeInterval = 10
    /// The time, for schedules; tests set it
    var clock: () -> Date = Date.init

    nonisolated static let defaultFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacDynamicIsland/Plugins", isDirectory: true)
    nonisolated static let defaultDataFolder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacDynamicIsland/PluginData", isDirectory: true)

    private let restartDelay: TimeInterval

    init(pluginsFolder: URL, dataFolder: URL, tabs: TabStore, preferences: PluginPreferencesStore = .shared,
         defaults: UserDefaults = .standard, bundledFolder: URL? = nil, bundledProgramFolder: URL? = nil,
         restartDelay: TimeInterval = 1) {
        self.defaults = defaults
        self.bundledFolder = bundledFolder
        self.bundledProgramFolder = bundledProgramFolder
        self.pluginsFolder = pluginsFolder
        self.dataFolder = dataFolder
        self.tabs = tabs
        self.preferences = preferences
        self.restartDelay = restartDelay
        preferencesCancellable = preferences.changes.sink { [weak self] pluginID in self?.preferencesChanged(pluginID) }
    }

    func start() {
        try? FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
        killLeftovers()
        reload()
        // An install, an update or `island-plugin dev` restarts only the plugin it touched
        folderMonitor = PluginFolderMonitor(folder: pluginsFolder) { [weak self] in self?.refresh() }
        folderMonitor?.start()
        // Timers don't run while the Mac sleeps and don't follow a clock change: catch up on both
        let workspace = NSWorkspace.shared.notificationCenter
        systemObservers = [
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runSchedules() }
            }),
            (NotificationCenter.default, NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runSchedules() }
            }),
        ]
        // Runs the plugins of the tabs you switch on, stops the ones you switch off. On the next turn:
        // @Published sends before the new list is stored
        tabsCancellable = tabs.$enabledTabs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncClients() }
    }

    func stop() {
        tabsCancellable = nil
        folderMonitor?.stop()
        folderMonitor = nil
        stopScheduling()
        clients.values.forEach { $0.stop() }
        clients.removeAll()
        saveRunning()
    }

    /// For quitting the app: asks every plugin to quit, waits up to `timeout` seconds in all, then kills what's
    /// left with everything it started. Blocks, since nothing runs after the app quits
    func stopForQuit(timeout: TimeInterval = 0.5) {
        tabsCancellable = nil
        folderMonitor?.stop()
        folderMonitor = nil
        stopScheduling()
        let processes = clients.values.compactMap(\.process)
        clients.values.forEach { $0.stopWithoutKilling() }
        clients.removeAll()
        for process in processes {
            process.closeInput()
            process.signalGroup(SIGTERM)
        }
        let deadline = Date().addingTimeInterval(timeout)
        for process in processes {
            _ = process.waitForExit(timeout: max(0, deadline.timeIntervalSinceNow))
            process.signalGroup(SIGKILL)
        }
        saveRunning()
    }

    /// Starts a plugin that stopped for good
    func restart(_ pluginID: String) {
        statuses[pluginID] = nil
        if installed.first(where: { $0.id == pluginID })?.manifest.runsOnDemand == true {
            recentFailures[pluginID] = nil
            clients[pluginID]?.stop()
            clients[pluginID] = nil
            wake(pluginID, reason: "launch")
        } else {
            clients[pluginID]?.restart()
        }
    }

    /// The running process of a plugin (also its process group)
    func processID(of pluginID: String) -> pid_t? {
        clients[pluginID]?.process?.pid
    }

    /// The data folder of one plugin, removed with the plugin
    func dataFolder(for pluginID: String) -> URL {
        dataFolder.appendingPathComponent(pluginID, isDirectory: true)
    }

    /// Scans the plugins folder again and restarts every plugin (Settings > Plugins > Reload)
    func reload() {
        scan(restartAll: true)
    }

    /// Scans the plugins folder again and restarts only the plugins whose files changed, or stops the ones that
    /// went: after an install, update or removal
    func refresh() {
        scan(restartAll: false)
    }

    private func scan(restartAll: Bool) {
        func folders(in parent: URL?) -> [URL] {
            guard let parent else { return [] }
            return ((try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        var found: [Installed] = []
        var problems: [(folder: String, reason: String)] = []
        // The app's own plugins first: one you installed with the same id doesn't replace them
        let candidates = folders(in: bundledFolder).map { ($0, true) } + folders(in: pluginsFolder).map { ($0, false) }
        for (folder, isBundled) in candidates {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                let manifest = try PluginManifest.load(from: folder)
                guard manifest.id == folder.lastPathComponent else {
                    problems.append((folder.lastPathComponent, "id \"\(manifest.id)\" doesn't match its folder"))
                    continue
                }
                guard !found.contains(where: { $0.id == manifest.id }) else {
                    problems.append((folder.lastPathComponent, "the app has a plugin with this id"))
                    continue
                }
                found.append(Installed(manifest: manifest, folder: folder, isBundled: isBundled,
                                       programFolder: isBundled ? bundledProgramFolder : nil))
            } catch {
                problems.append((folder.lastPathComponent, String(describing: error)))
                logger.error("Plugin folder \(folder.lastPathComponent, privacy: .public) skipped: \(String(describing: error), privacy: .public)")
            }
        }
        installed = found
        broken = problems
        // A plugin that takes over a built-in tab gets no tab of its own
        tabs.setPluginTabs(found.filter { IslandTab.builtInTabsOfPlugins[$0.id] == nil }
            .map { (IslandTab.plugin($0.id), TabStore.TabInfo(name: $0.manifest.name, symbol: $0.manifest.symbol)) })
        // Restart the ones whose files changed; what they showed goes with them
        let newFingerprints = Dictionary(uniqueKeysWithValues: found.map { ($0.id, Fingerprint(of: $0)) })
        // Asleep ones too (no client), so a new build of an on-demand plugin is started to show itself
        for id in Set(clients.keys).union(statuses.keys) where restartAll || newFingerprints[id] != fingerprints[id] {
            clients[id]?.stop()
            clients[id] = nil
            contents[id] = nil
            statuses[id] = nil
            schedules[id] = nil
            recentFailures[id] = nil
        }
        fingerprints = newFingerprints
        syncClients()
    }

    /// A plugin's plugin.json and the identity of its program: a new build or an update changes one of them
    struct Fingerprint: Equatable {
        let manifest: Data?
        let programNumber: Int?
        let programSize: Int?
        let programModified: Date?

        init(of plugin: Installed) {
            manifest = try? Data(contentsOf: plugin.folder.appendingPathComponent(PluginManifest.fileName))
            let attributes = try? FileManager.default.attributesOfItem(atPath: plugin.executableURL.path)
            programNumber = (attributes?[.systemFileNumber] as? NSNumber)?.intValue
            programSize = (attributes?[.size] as? NSNumber)?.intValue
            programModified = attributes?[.modificationDate] as? Date
        }
    }

    private func syncClients() {
        let wanted = wantedPluginIDs
        for (id, client) in clients where !wanted.contains(id) {
            client.stop()
            clients[id] = nil
        }
        for id in Set(statuses.keys).union(contents.keys).union(schedules.keys) where !wanted.contains(id) {
            contents[id] = nil
            statuses[id] = nil
            schedules[id] = nil
        }
        for plugin in installed where wanted.contains(plugin.id) && clients[plugin.id] == nil {
            guard !preferences.needsSetup(plugin.manifest) else {
                statuses[plugin.id] = .needsSetup
                continue
            }
            if statuses[plugin.id] == .needsSetup { statuses[plugin.id] = nil }
            if plugin.manifest.runsOnDemand {
                // Asleep until needed; the first time, it runs once to say what to show
                if statuses[plugin.id] == nil { wake(plugin.id, reason: "launch") }
                continue
            }
            startClient(plugin)
        }
        saveRunning()
        runSchedules()
    }

    @discardableResult
    private func startClient(_ plugin: Installed) -> PluginClient {
        let client = PluginClient(manifest: plugin.manifest, folder: plugin.folder, dataFolder: dataFolder(for: plugin.id),
                                  programFolder: plugin.programFolder, restartDelay: restartDelay)
        client.onMessage = { [weak self] message in self?.apply(message, from: plugin.id) }
        client.onLaunch = { [weak self] in
            guard let self else { return }
            // A restarted process starts from scratch, so whatever the last one showed (a countdown) is stale.
            // One that runs on demand picks up where it left off, so what it left shows until it says otherwise
            if !plugin.manifest.runsOnDemand { self.contents[plugin.id] = nil }
            self.statuses[plugin.id] = .running
            // It learns its settings first, then whether its tab is showing
            if plugin.manifest.preferences?.isEmpty == false {
                self.clients[plugin.id]?.send(.preferences(self.preferences.values(for: plugin.manifest)))
            }
            self.clients[plugin.id]?.send(.visible((self.visibleCounts[plugin.id] ?? 0) > 0))
            self.saveRunning()
        }
        client.onGiveUp = { [weak self] reason in
            self?.contents[plugin.id] = nil
            self?.statuses[plugin.id] = .stopped(reason: reason)
            self?.saveRunning()
        }
        if plugin.manifest.runsOnDemand {
            client.restartsOnExit = false
            client.onExit = { [weak self, weak client] status in
                self?.pluginExited(plugin.id, status: status, errors: client?.recentErrors ?? [])
            }
        }
        clients[plugin.id] = client
        client.start()
        return client
    }

    // MARK: - On demand

    /// Starts a plugin that runs on demand, unless it is running, and tells it why. `event` (the tap that woke
    /// it) goes first; a running one just gets the event
    private func wake(_ pluginID: String, reason: String, with event: PluginEvent? = nil) {
        guard let plugin = installed.first(where: { $0.id == pluginID }), plugin.manifest.runsOnDemand,
              isWanted(pluginID), !preferences.needsSetup(plugin.manifest) else { return }
        if case .stopped = statuses[pluginID] { return }
        if let client = clients[pluginID], client.process != nil {
            if let event { client.send(event) }
            return
        }
        let client = startClient(plugin)
        guard client.process != nil else { return }
        if let event { client.send(event) }
        client.send(.wake(reason: reason))
        armIdleTimeout(pluginID)
    }

    /// It said it has nothing more to do: it is stopped, and what it showed stays
    private func finish(_ pluginID: String) {
        guard let client = clients[pluginID], client.manifest.runsOnDemand else { return }
        idleTimeouts[pluginID]?.cancel()
        idleTimeouts[pluginID] = nil
        client.stop()
        clients[pluginID] = nil
        statuses[pluginID] = .sleeping
        saveRunning()
    }

    /// It quit on its own. Quitting is fine; failing too often in a minute stops it for good, like a plugin that
    /// keeps exiting
    private func pluginExited(_ pluginID: String, status: Int32, errors: [String]) {
        guard clients[pluginID]?.process == nil else { return }
        clients[pluginID] = nil
        idleTimeouts[pluginID]?.cancel()
        idleTimeouts[pluginID] = nil
        if status != 0 {
            let now = Date()
            let failures = (recentFailures[pluginID] ?? []).filter { now.timeIntervalSince($0) < 60 } + [now]
            recentFailures[pluginID] = failures
            if failures.count > 5 {
                logger.error("Plugin \(pluginID, privacy: .public) keeps failing (status \(status)); giving up")
                contents[pluginID] = nil
                schedules[pluginID] = nil
                statuses[pluginID] = .stopped(reason: errors.last ?? "failed \(failures.count) times in a minute (status \(status))")
                saveRunning()
                return
            }
        }
        statuses[pluginID] = .sleeping
        saveRunning()
    }

    /// One that keeps running with its tab hidden and says nothing is stopped
    private func armIdleTimeout(_ pluginID: String) {
        idleTimeouts[pluginID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if (self.visibleCounts[pluginID] ?? 0) > 0 {
                self.armIdleTimeout(pluginID)
            } else {
                self.logger.notice("Plugin \(pluginID, privacy: .public) stayed running with nothing to do; stopped")
                self.finish(pluginID)
            }
        }
        idleTimeouts[pluginID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleTimeout, execute: work)
    }

    // MARK: - Schedules

    /// Shows what is due in each plugin's timeline, wakes the plugins whose time came, and sets one timer for
    /// the next thing due
    func runSchedules() {
        let now = clock()
        for id in Array(schedules.keys) {
            guard var schedule = schedules[id] else { continue }
            let due = schedule.takeDue(at: now)
            schedules[id] = schedule.isEmpty ? nil : schedule
            for message in due.messages { apply(message, from: id) }
            if due.wake { wakeForTimeline(id, now: now) }
        }
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        guard let next = schedules.values.compactMap(\.nextDate).min() else { return }
        let timer = Timer(fire: max(next, now), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.runSchedules() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    /// A timeline's wake: at most every minimumWakeInterval, so one that keeps asking for "now" can't spin
    private func wakeForTimeline(_ pluginID: String, now: Date) {
        if let last = lastTimelineWake[pluginID], now.timeIntervalSince(last) < Self.minimumWakeInterval {
            var schedule = schedules[pluginID] ?? PluginSchedule(entries: [], wake: nil)
            schedule.postponeWake(to: last.addingTimeInterval(Self.minimumWakeInterval))
            schedules[pluginID] = schedule
            return
        }
        // A running one keeps its own time
        guard clients[pluginID]?.process == nil else { return }
        lastTimelineWake[pluginID] = now
        wake(pluginID, reason: "timeline")
    }

    private func stopScheduling() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        idleTimeouts.values.forEach { $0.cancel() }
        idleTimeouts.removeAll()
        for (center, observer) in systemObservers { center.removeObserver(observer) }
        systemObservers.removeAll()
    }

    // MARK: - Which plugins run

    /// UserDefaults key: the ids of plugins you turned off in Settings > Plugins
    static let disabledKey = "disabledPlugins"

    /// Turned on in Settings > Plugins (the default). A plugin that's off doesn't run, even with its tab on
    func isEnabled(_ pluginID: String) -> Bool {
        !(defaults.stringArray(forKey: Self.disabledKey) ?? []).contains(pluginID)
    }

    func setEnabled(_ pluginID: String, _ enabled: Bool) {
        guard enabled != isEnabled(pluginID) else { return }
        var disabled = Set(defaults.stringArray(forKey: Self.disabledKey) ?? [])
        if enabled { disabled.remove(pluginID) } else { disabled.insert(pluginID) }
        objectWillChange.send()
        defaults.set(disabled.sorted(), forKey: Self.disabledKey)
        syncClients()
    }

    /// The installed plugin that draws this built-in tab (the Agents plugin draws Agents), turned on or not
    func replacesBuiltInTab(_ tab: IslandTab) -> String? {
        guard let id = IslandTab.builtInTabsOfPlugins.first(where: { $0.value == tab })?.key,
              installed.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The plugins of your tabs, in their order: plugin tabs, and built-in tabs a plugin took over
    private var tabPluginIDs: [String] {
        tabs.enabledTabs.compactMap { $0.pluginID ?? replacesBuiltInTab($0) }
    }

    /// The plugins to run: turned on, and either one of your tabs or running in the background
    var wantedPluginIDs: Set<String> {
        let tabIDs = Set(tabPluginIDs)
        return Set(installed.filter { (tabIDs.contains($0.id) || $0.manifest.runsInBackground) && isEnabled($0.id) }.map(\.id))
    }

    func isWanted(_ pluginID: String) -> Bool { wantedPluginIDs.contains(pluginID) }

    // MARK: - Preferences

    /// You changed a plugin's preference: once you stop typing, it hears the new values; one that now lacks a
    /// required value stops, and one that was waiting for it starts
    private func preferencesChanged(_ pluginID: String) {
        pendingPreferences[pluginID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPreferences[pluginID] = nil
            self.applyPreferences(of: pluginID)
        }
        pendingPreferences[pluginID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.preferencesDelay, execute: work)
    }

    func applyPreferences(of pluginID: String) {
        guard let plugin = installed.first(where: { $0.id == pluginID }) else { return }
        let wanted = isWanted(pluginID)
        if preferences.needsSetup(plugin.manifest) {
            clients[pluginID]?.stop()
            clients[pluginID] = nil
            contents[pluginID] = nil
            statuses[pluginID] = wanted ? .needsSetup : nil
            saveRunning()
        } else if let client = clients[pluginID], client.process != nil {
            client.send(.preferences(preferences.values(for: plugin.manifest)))
        } else if plugin.manifest.runsOnDemand && statuses[pluginID] == .sleeping {
            wake(pluginID, reason: "preferences")
        } else {
            syncClients()
        }
    }

    // MARK: - Tab visibility

    /// A plugin's tab came into view on one island. The plugin hears of it when the first one shows it
    func tabAppeared(_ pluginID: String) {
        let count = visibleCounts[pluginID, default: 0] + 1
        visibleCounts[pluginID] = count
        guard count == 1 else { return }
        if clients[pluginID]?.process == nil, statuses[pluginID] == .sleeping {
            // Woken to show its tab; it learns it's visible as it starts
            wake(pluginID, reason: "visible")
        } else {
            send(.visible(true), to: pluginID)
        }
    }

    /// A plugin's tab left view on one island. The plugin hears of it once no island shows it
    func tabDisappeared(_ pluginID: String) {
        let count = max(0, visibleCounts[pluginID, default: 0] - 1)
        visibleCounts[pluginID] = count
        if count == 0 { send(.visible(false), to: pluginID) }
    }

    /// A tap or a submitted text; one that runs on demand is woken for it
    func send(_ event: PluginEvent, to pluginID: String) {
        if clients[pluginID]?.process == nil, statuses[pluginID] == .sleeping {
            wake(pluginID, reason: "action", with: event)
        } else {
            clients[pluginID]?.send(event)
            // A tap is activity too: an on-demand plugin isn't idle
            if idleTimeouts[pluginID] != nil { armIdleTimeout(pluginID) }
        }
    }

    func apply(_ message: PluginMessage, from pluginID: String) {
        // Saying something is activity: an on-demand plugin isn't idle
        if idleTimeouts[pluginID] != nil { armIdleTimeout(pluginID) }
        var content = contents[pluginID] ?? Content()
        switch message {
        case .compact(let compact): content.compact = compact
        case .list(let rows): content.rows = rows
        case .cards(let cards): content.cards = cards
        case .clear(.cards): content.cards = []
        case .media(let media):
            // Another track: the old one's lyrics go
            if content.media?.title != media.title || content.media?.artist != media.artist { content.lyrics = [] }
            content.media = media
        case .lyrics(let lines): content.lyrics = lines
        case .clear(.media):
            content.media = nil
            content.lyrics = []
        case .clear(.lyrics): content.lyrics = []
        case .buttons(let buttons): content.buttons = buttons
        case .clear(.compact): content.compact = nil
        case .clear(.list): content.rows = []
        case .clear(.buttons): content.buttons = []
        case .input(let input): content.input = input
        case .clear(.input): content.input = nil
        case .clear(.all): content = Content()
        case .popup(let popup):
            show(popup, from: pluginID)
            return
        case .open(let hold):
            open(from: pluginID, hold: hold)
            return
        case .close:
            onClose(pluginID)
            return
        case .status(let notice): content.notice = notice
        case .timeline(let schedule):
            schedules[pluginID] = schedule
            runSchedules()
            return
        case .done:
            finish(pluginID)
            return
        }
        if contents[pluginID] != content { contents[pluginID] = content }
    }

    /// Opens the island on the plugin's tab, when its tab is one of yours, you allow it, and it hasn't just done so
    private func open(from pluginID: String, hold: Bool, now: Date = Date()) {
        // "Let plugins open the island" is about plugins you install; the app's own answer to their own settings
        let isBundled = installed.first { $0.id == pluginID }?.isBundled ?? false
        guard isBundled || SettingsDefaults.shared.get(SettingsDefaults.pluginsMayOpenIsland),
              tabs.isEnabled(IslandTab.tab(forPlugin: pluginID)) else { return }
        if let last = lastOpened[pluginID], now.timeIntervalSince(last) < Self.openInterval {
            logger.notice("Plugin \(pluginID, privacy: .public) asked to open the island again too soon; ignored")
            return
        }
        lastOpened[pluginID] = now
        onOpen(pluginID, hold)
    }

    /// Takes the popup away now (tests)
    func dismissPopup() {
        popupDismissal?.cancel()
        popup = nil
    }

    private func show(_ popup: PluginPopup, from pluginID: String) {
        popupSerial += 1
        self.popup = ActivePopup(pluginID: pluginID, popup: popup, serial: popupSerial)
        popupDismissal?.cancel()
        let serial = popupSerial
        let dismissal = DispatchWorkItem { [weak self] in
            guard self?.popup?.serial == serial else { return }
            self?.popup = nil
        }
        popupDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + popup.duration, execute: dismissal)
    }

    // MARK: - Beside the notch

    /// The first plugin with something to show beside the notch, of the given priority: your plugin tabs in
    /// their order, then plugins running in the background
    func compactPlugin(priority: PluginPriority) -> (manifest: PluginManifest, compact: PluginCompact)? {
        let tabIDs = tabPluginIDs
        let backgroundIDs = installed.filter { $0.manifest.runsInBackground && !tabIDs.contains($0.id) && isEnabled($0.id) }.map(\.id)
        for id in tabIDs + backgroundIDs {
            guard let compact = contents[id]?.compact, let plugin = installed.first(where: { $0.id == id }),
                  (plugin.manifest.priority ?? .normal) == priority else { continue }
            return (plugin.manifest, compact)
        }
        return nil
    }

    var compactPlugin: (manifest: PluginManifest, compact: PluginCompact)? { compactPlugin(priority: .normal) }
    var priorityPlugin: (manifest: PluginManifest, compact: PluginCompact)? { compactPlugin(priority: .high) }

    private var showsBesideNotch: Bool { SettingsDefaults.shared.get(SettingsDefaults.showPluginLiveActivity) }
    /// A popup to show beside the notch now
    var showsPopupLiveActivity: Bool { showsBesideNotch && popup != nil }
    /// Compact content to show beside the notch when nothing ahead of it needs the space
    var showsCompactContent: Bool { showsBesideNotch && compactPlugin != nil }
    /// A high-priority plugin's compact content, ahead of popups and now playing
    var showsPriorityContent: Bool { showsBesideNotch && priorityPlugin != nil }

    // MARK: - Leftovers

    private var runningFile: URL { dataFolder.appendingPathComponent(".running.json") }

    private struct RunningEntry: Codable {
        let pid: Int32
        let path: String
    }

    /// Notes the running plugins, so a later launch can end any the app left behind if it crashed
    private func saveRunning() {
        let entries = clients.values.compactMap { client in
            client.process.map { RunningEntry(pid: $0.pid, path: client.executableURL.path) }
        }
        try? FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: runningFile, options: .atomic)
    }

    /// Ends plugins (and what they started) that a crashed app left running. Only a process still running the
    /// plugin's program is ended, so a reused process id is left alone
    private func killLeftovers() {
        guard let data = try? Data(contentsOf: runningFile),
              let entries = try? JSONDecoder().decode([RunningEntry].self, from: data) else { return }
        for entry in entries where Self.executablePath(of: entry.pid) == entry.path {
            logger.notice("Ending plugin process \(entry.pid) left from the last run")
            _ = kill(-entry.pid, SIGKILL)
        }
        try? FileManager.default.removeItem(at: runningFile)
    }

    nonisolated static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
