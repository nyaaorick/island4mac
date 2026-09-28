import SwiftUI

/// About section in settings
struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        SettingsForm {
            // App icon and name: the one heading in Settings
            Section {
                HStack(spacing: 12) {
                    if let iconImage = NSImage(named: "AppIcon") {
                        Image(nsImage: iconImage)
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
                LabeledContent("Developer") {
                    link("nyaaorick", to: Self.developerURL)
                }
                LabeledContent("Based on") {
                    link("Mac Dynamic Island Team", to: Self.upstreamURL)
                }
                LabeledContent("macOS", value: SystemPreferencesManager.shared.osVersion)
            }

            Section {
                link("GitHub repository", to: Self.repositoryURL)
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
    /// The project this one is forked from
    private static let upstreamURL = URL(string: "https://github.com/RayTracingON/mac-dynamic-island")!

    private func link(_ title: String, to url: URL) -> some View {
        Button(title) {
            openURL(url)
        }
        .buttonStyle(.link)
    }
}

#Preview("About View") {
    AboutView()
        .frame(width: 500, height: 600)
}
