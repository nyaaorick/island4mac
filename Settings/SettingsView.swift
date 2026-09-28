import Cocoa
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    private override init() {}
    
    public func showSettings() {
        if window == nil {
            let appState = OverlayWindowController.shared.getAppState()
            let settingsView = MainSettingsView()
                .environmentObject(appState)
            
            let hostingController = NSHostingController(rootView: settingsView)
            
            // Fixed size window for settings, standard macOS style
            let windowSize = NSSize(width: 820, height: 560)

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: windowSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.center()
            w.setFrameAutosaveName("SettingsWindow")
            w.title = L("settings.title")
            w.contentViewController = hostingController
            w.isReleasedWhenClosed = false
            w.titlebarAppearsTransparent = true
            
            // Creating a nice toolbar appearance like System Settings
            w.toolbarStyle = .preference
            
            self.window = w
        }
        
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}

// MARK: - Main Settings View (Sidebar, like System Settings)

/// One page of the settings window
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, media, agents, clipboard, shelf, shortcuts, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L("settings.tab.general")
        case .appearance: return L("settings.tab.appearance")
        case .media: return L("settings.tab.media")
        case .agents: return L("settings.tab.agents")
        case .clipboard: return L("settings.tab.clipboard")
        case .shelf: return L("settings.tab.shelf")
        case .shortcuts: return L("settings.tab.shortcuts")
        case .advanced: return L("settings.tab.advanced")
        case .about: return L("settings.tab.about")
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintpalette"
        case .media: return "music.note"
        case .agents: return "terminal"
        case .clipboard: return "doc.on.clipboard"
        case .shelf: return "shippingbox"
        case .shortcuts: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

/// A sidebar rather than tabs: the window's content runs under its transparent title bar, which hid the tab row
struct MainSettingsView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.iconName)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .media: MediaSettingsView()
        case .agents: AgentSettingsView()
        case .clipboard: ClipboardSettingsWindow(hubStore: OverlayWindowController.shared.getAppState().clipVault)
        case .shelf: ShelfSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .advanced: AdvancedSettingsView()
        case .about: AboutView()
        }
    }
}
