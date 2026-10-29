import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 12) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("island4mac")
                            .font(.title3.weight(.semibold))
                        SettingsNote("Version \(appVersion) (\(buildNumber))")
                    }
                }
            }

            Section(header: Text("Info")) {
                LabeledContent("Developer") { link("nyaaorick", to: Self.developerURL) }
                LabeledContent("Based on") { link("boring.notch", to: Self.boringNotchURL) }
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            }

            Section {
                link("GitHub repository", to: Self.repositoryURL)
                link("Plugins", to: Self.pluginsURL)
                link("Report an issue", to: Self.repositoryURL.appending(path: "issues"))
            } header: {
                Text("Links")
            } footer: {
                SettingsNote("© 2026 nyaaorick")
            }
        }
    }

    private static let developerURL = URL(string: "https://github.com/nyaaorick")!
    private static let repositoryURL = URL(string: "https://github.com/nyaaorick/island4mac")!
    private static let pluginsURL = URL(string: "https://github.com/nyaaorick/island4mac-plugins")!
    /// The window physics, drag detection and now-playing approach come from there
    private static let boringNotchURL = URL(string: "https://github.com/TheBoredTeam/boring.notch")!

    private func link(_ title: String, to url: URL) -> some View {
        Button(title) { openURL(url) }
            .buttonStyle(.link)
    }
}
