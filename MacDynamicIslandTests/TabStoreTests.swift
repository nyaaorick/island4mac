import XCTest
@testable import MacDynamicIsland

@MainActor
final class TabStoreTests: XCTestCase {

    /// A store backed by a throwaway defaults domain, so tests never touch your tabs.
    private func makeStore() -> (TabStore, UserDefaults) {
        let suiteName = "TabStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        return (TabStore(defaults: defaults), defaults)
    }

    private func plugins(_ ids: [String]) -> [(tab: IslandTab, info: TabStore.TabInfo)] {
        ids.map { (IslandTab.plugin($0), TabStore.TabInfo(name: $0, symbol: "star")) }
    }

    func testTheBuiltInTabsShowByDefault() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.enabledTabs, IslandTab.builtIn)
    }

    func testAtMostSixTabsShow() {
        let (store, _) = makeStore()
        store.setPluginTabs(plugins(["a", "b", "c"]))
        store.setEnabled(.plugin("a"), true)
        store.setEnabled(.plugin("b"), true)
        XCTAssertEqual(store.enabledTabs.count, TabStore.maxEnabled)
        XCTAssertFalse(store.canToggle(.plugin("c")), "a seventh tab can't be switched on")
        store.setEnabled(.plugin("c"), true)
        XCTAssertFalse(store.isEnabled(.plugin("c")))
    }

    func testTheLastTabStays() {
        let (store, _) = makeStore()
        for tab in IslandTab.builtIn { store.setEnabled(tab, false) }
        XCTAssertEqual(store.enabledTabs, [.agents], "the island always has a tab to open on")
        XCTAssertFalse(store.canToggle(.agents))
    }

    func testOrderIsSaved() {
        let (store, defaults) = makeStore()
        store.moveEnabled(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(store.enabledTabs, [.agents, .music, .clipboard, .files])
        XCTAssertEqual(TabStore(defaults: defaults).enabledTabs, [.agents, .music, .clipboard, .files])
    }

    func testAPluginTabWaitsForItsPlugin() {
        let (store, defaults) = makeStore()
        store.setPluginTabs(plugins(["timer"]))
        store.setEnabled(.plugin("timer"), true)

        // Next launch: the plugin hasn't loaded yet, then it has
        let relaunched = TabStore(defaults: defaults)
        XCTAssertFalse(relaunched.isEnabled(.plugin("timer")))
        relaunched.setEnabled(.music, false)
        relaunched.setPluginTabs(plugins(["timer"]))
        XCTAssertEqual(relaunched.enabledTabs, [.clipboard, .files, .agents, .plugin("timer")],
                       "it keeps its place through a change made while it was missing")
    }

    func testUnknownTabsAreDropped() {
        let (_, defaults) = makeStore()
        defaults.set(["music", "nonsense", "music", "files"], forKey: SettingsDefaults.enabledTabs.key)
        XCTAssertEqual(TabStore(defaults: defaults).enabledTabs, [.music, .files])
    }

    func testPluginTabIDs() {
        XCTAssertEqual(IslandTab.plugin("timer").pluginID, "timer")
        XCTAssertNil(IslandTab.music.pluginID)
    }

    // MARK: - Tab labels

    /// Six tabs beside a MacBook camera (about 200 pt wide) all fit whole, with no sideways scrolling
    func testSixTabsFitBesideTheCamera() {
        let side = (NotchMetrics.expandedWidth - 2 * NotchMetrics.expandedTopRadius - 200) / 2 - 16
        let groups = [["Clipboard", "Timer", "Agents"], ["Files", "Music", "System"]]
        let layout = TabBarLayout.fitting(groups, in: side)
        XCTAssertFalse(layout.scrolls)
        for group in groups { XCTAssertLessThanOrEqual(layout.width(of: group), side) }
    }

    /// The roomiest style that fits wins; labels that fit no style scroll rather than get cut short
    func testLayoutTightensBeforeItScrolls() {
        XCTAssertEqual(TabBarLayout.fitting([["Music"]], in: 300), .regular)
        let labels = ["Clipboard", "Agents", "Battery"]
        XCTAssertEqual(TabBarLayout.fitting([labels], in: TabBarLayout.tight.width(of: labels)), .tight)
        XCTAssertEqual(TabBarLayout.fitting([labels], in: TabBarLayout.labelsOnly.width(of: labels)), .labelsOnly)
        XCTAssertTrue(TabBarLayout.fitting([labels], in: 40).scrolls)
    }
}
