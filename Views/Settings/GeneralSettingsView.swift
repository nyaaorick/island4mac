import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    // Redraws the hover delay's value as the slider moves
    @ObservedObject private var settings = SettingsDefaults.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var chosenDisplay = SettingsDefaults.shared.get(SettingsDefaults.preferredDisplayUUID)
    @State private var displays = ConnectedDisplay.all
    
    // Sizing state
    @State private var notchHeightMode: Int = SettingsDefaults.shared.get(SettingsDefaults.notchHeight)
    @State private var nonNotchHeightValue: Double = SettingsDefaults.shared.get(SettingsDefaults.nonNotchHeight)
    
    var body: some View {
        SettingsForm {
            // 0. Permissions
            Section(header: Text("Permissions")) {
                StatusSettingsRow(
                    title: "Accessibility",
                    isOK: appState.isAXAuthorized,
                    note: appState.isAXAuthorized
                        ? "Authorized"
                        : "Not authorized. Required to read now-playing state from third-party apps such as QQ Music and NetEase Cloud Music."
                ) {
                    if !appState.isAXAuthorized {
                        Button("Grant access") {
                            appState.requestAXPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            // 1. System Features
            Section(header: Text(L("settings.startup.header"))) {
                ToggleSettingsRow(
                    key: SettingsDefaults.launchAtLogin,
                    title: L("settings.startup.launch_at_login"),
                    help: "Launch the island automatically after your Mac restarts"
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.menubarIcon,
                    title: "Show menu bar icon",
                    help: "Toggle the visibility of the menu bar status icon"
                )
            }
            
            // 2. Display
            Section(header: Text(L("settings.display.header"))) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showOnAllDisplays,
                    title: L("settings.display.mode.all"),
                    help: "Show the island on every connected display"
                )
                
                Picker(L("settings.display.show_on"), selection: $chosenDisplay) {
                    Text("Default display").tag("")
                    ForEach(displays) { display in
                        Text(display.name).tag(display.uuid)
                    }
                    if !chosenDisplay.isEmpty && !displays.contains(where: { $0.uuid == chosenDisplay }) {
                        Text("Disconnected display").tag(chosenDisplay)
                    }
                }
                .help("The default display is the built-in display with the notch, and the island falls back to it when the chosen display isn't connected. With \"All displays\" on, the shortcuts and the clipboard open the island on this display")
                // When following the mouse, the island isn't tied to one display
                .disabled(SettingsDefaults.shared.get(SettingsDefaults.automaticallySwitchDisplay)
                          && !SettingsDefaults.shared.get(SettingsDefaults.showOnAllDisplays))
                .onChange(of: chosenDisplay) { _, uuid in
                    SettingsDefaults.shared.set(SettingsDefaults.preferredDisplayUUID, value: uuid)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    displays = ConnectedDisplay.all
                }

                ToggleSettingsRow(
                    key: SettingsDefaults.automaticallySwitchDisplay,
                    title: "Follow mouse across displays",
                    help: "The island moves to whichever display the mouse is on"
                )
                // No need to follow when every display has an island
                .disabled(SettingsDefaults.shared.get(SettingsDefaults.showOnAllDisplays))

                ToggleSettingsRow(
                    key: SettingsDefaults.hideForFullScreenVideo,
                    title: "Hide during full-screen video",
                    help: "When the app that's playing (a video player, or the browser a web video plays in) goes full screen, the island on that display hides and comes back when it leaves full screen. Other full-screen apps, like a terminal or an editor, aren't affected"
                )
            }
            
            // 3. Notch Behavior
            Section(header: Text(L("settings.behavior.header"))) {
                ToggleSettingsRow(
                    key: SettingsDefaults.openNotchOnHover,
                    title: L("settings.behavior.show_on_hover"),
                    help: L("settings.behavior.show_on_hover_help")
                )
                
                SliderSettingsRow(
                    title: L("settings.behavior.hover_delay"),
                    value: Binding(
                        get: { settings.get(SettingsDefaults.minimumHoverDuration) },
                        set: { settings.set(SettingsDefaults.minimumHoverDuration, value: $0) }
                    ),
                    range: 0.0...1.0,
                    step: 0.05,
                    valueText: String(format: "%.2f s", settings.get(SettingsDefaults.minimumHoverDuration))
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.enableHaptics,
                    title: L("settings.behavior.haptic_feedback"),
                    help: L("settings.behavior.haptic_feedback_help")
                )
                
                ToggleSettingsRow(
                    key: SettingsDefaults.rememberLastTab,
                    title: "Remember last used tab",
                    help: "Reopen the section you used last when expanding"
                )
            }
            
            // 4. Auto Close
            Section(header: Text("Auto-collapse")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.autoCloseEnabled,
                    title: "Collapse when idle",
                    help: "Collapse the island after a period of inactivity"
                )
                
                LabeledContent("Collapse delay") {
                    HStack(spacing: 8) {
                        TextField("", value: Binding(
                            get: { SettingsDefaults.shared.get(SettingsDefaults.autoCloseTimeout) },
                            set: { SettingsDefaults.shared.set(SettingsDefaults.autoCloseTimeout, value: $0) }
                        ), formatter: NumberFormatter())
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text(L("settings.media.timeout_unit"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // 5. Gestures
            Section(header: Text("Gestures")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.enableGestures,
                    title: "Swipe to open and close",
                    help: "Swipe down with two fingers on the trackpad to open the island, and up to close it"
                )
            }
        }
    }
}

/// A display offered in the "show island on" picker
private struct ConnectedDisplay: Identifiable {
    let uuid: String
    let name: String
    var id: String { uuid }

    static var all: [ConnectedDisplay] {
        NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { ConnectedDisplay(uuid: $0, name: screen.localizedName) }
        }
    }
}
