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
            let windowSize = NSSize(width: 750, height: 500)

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

// MARK: - Main Settings View (The Tabbed Interface)

struct MainSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("settings.tab.general"), systemImage: "gear")
                }
            
            AppearanceSettingsView()
                .tabItem {
                    Label(L("settings.tab.appearance"), systemImage: "paintpalette")
                }
            
            MediaSettingsView()
                .tabItem {
                    Label(L("settings.tab.media"), systemImage: "music.note")
                }
            
            AgentSettingsView()
                .tabItem {
                    Label("Agents", systemImage: "terminal")
                }

            ClipboardSettingsWindow(hubStore: OverlayWindowController.shared.getAppState().clipVault)
                .tabItem {
                    Label(L("settings.tab.clipboard"), systemImage: "doc.on.clipboard")
                }

            ShelfSettingsView()
                .tabItem {
                    Label(L("settings.tab.shelf"), systemImage: "shippingbox")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label(L("settings.tab.shortcuts"), systemImage: "keyboard")
                }
            
            AdvancedSettingsView()
                .tabItem {
                    Label(L("settings.tab.advanced"), systemImage: "slider.horizontal.3")
                }
             
             AboutView()
                 .tabItem {
                     Label(L("settings.tab.about"), systemImage: "info.circle")
                 }
        }
        .frame(minWidth: 750, minHeight: 500)
        .padding()
    }
}

