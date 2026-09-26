import Combine
import SwiftUI

/// About section in settings
struct AboutView: View {
    @Environment(\.openURL) var openURL
    
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        VStack(spacing: 24) {
            // App icon and name
            VStack(spacing: 12) {
                if let iconImage = NSImage(named: "AppIcon") {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                }
                
                Text("Mac Dynamic Island")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Info
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(title: "Developer", value: "Mac Dynamic Island Team")
                InfoRow(title: "Based on", value: "boringNotch")
                InfoRow(title: "macOS", value: SystemPreferencesManager.shared.osVersion)
            }
            
            Divider()
            
            // Links
            VStack(spacing: 8) {
                Button("GitHub Repository") {
                    if let url = URL(string: "https://github.com/") {
                        openURL(url)
                    }
                }
                
                Button("Report an Issue") {
                    if let url = URL(string: "https://github.com/") {
                        openURL(url)
                    }
                }
                
                Button("Privacy Policy") {
                    if let url = URL(string: "https://github.com/") {
                        openURL(url)
                    }
                }
            }
            .buttonStyle(.link)
            
            Spacer()
            
            // Copyright
            Text("© 2024 Mac Dynamic Island. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview("About View") {
    AboutView()
        .frame(width: 500, height: 600)
}
