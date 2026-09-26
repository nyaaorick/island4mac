import SwiftUI

struct AgentSettingsView: View {
    var body: some View {
        Form {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                Section(header: Text(agent.displayName)) {
                    AgentConnectionRow(installer: .standard(agent))
                }
            }

            Section(header: Text("General")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showAgentLiveActivity,
                    title: "Show progress next to the notch",
                    help: "Show status and progress beside the collapsed island while an agent is working, waiting for your approval, or just finished"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.agentPromptsOpenIsland,
                    title: "Expand automatically when input is needed",
                    help: "When Claude asks for permission or needs an answer or a choice, the island expands so you can handle it right there (the terminal still works too)"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.agentSoundsEnabled,
                    title: "Alert sound",
                    help: "Play a system sound when an agent needs approval, finishes, or hits an error"
                )
            }
        }
    }
}

/// Connect or disconnect one agent
private struct AgentConnectionRow: View {
    let installer: AgentHookInstaller
    @State private var isInstalled = false
    @State private var errorText: String?

    var body: some View {
        HStack {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundColor(isInstalled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(isInstalled ? "Connected" : "Not connected")
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isInstalled ? "Disconnect" : "Connect \(installer.agent.displayName)") {
                toggleInstallation()
            }
        }
        .onAppear { isInstalled = installer.isInstalled }

        if let errorText {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var help: String {
        let file = (installer.settingsURL.path as NSString).abbreviatingWithTildeInPath
        let base = "Connecting adds hooks to \(file) (backed up before the first change); existing hooks are left alone"
        switch installer.agent {
        case .claude:
            return base
        case .codex:
            return base + ". Codex only runs new hooks once you trust them: after connecting, type /hooks in Codex to confirm"
        case .zcode:
            return base + ", and turns on config-file hooks (hooks.enabled)"
        }
    }

    private func toggleInstallation() {
        do {
            if isInstalled {
                try installer.uninstall()
            } else {
                try installer.install()
            }
            isInstalled = installer.isInstalled
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
