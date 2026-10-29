import Cocoa

/// The menu bar item: show or hide the island, open Settings, quit
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let appState: AppState
    private let islandController: IslandController

    init(appState: AppState, islandController: IslandController) {
        self.appState = appState
        self.islandController = islandController
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.pillIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "island4mac"
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, action, key) in [
            ("Show Island", #selector(onShow), "s"),
            ("Hide Island", #selector(onHide), "h"),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(onSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let reset = NSMenuItem(title: "Reset Island Position", action: #selector(onReposition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit island4mac", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func onShow() {
        NSApp.activate(ignoringOtherApps: true)
        islandController.show()
    }

    @objc private func onHide() { islandController.hide() }

    @objc private func onSettings() { SettingsWindowController.shared.showSettings() }

    /// Puts every island back where it belongs, collapsed
    @objc private func onReposition() {
        islandController.reposition()
        appState.isIslandVisible = true
        appState.islandMode = .compact
    }

    @objc private func onQuit() { NSApp.terminate(nil) }

    /// A small pill, like the island itself; a template image, so it follows the menu bar's appearance
    private static func pillIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: 5, width: 12, height: 6), xRadius: 3, yRadius: 3).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
