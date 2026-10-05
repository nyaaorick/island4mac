import SwiftUI

struct AgentsEmptyView: View {
    @State private var connected = Set(AgentHookInstaller.all.filter(\.isInstalled).map(\.agent))
    @State private var note: String?
    @State private var errorText: String?

    /// Agents used on this Mac that aren't connected yet; all of them when none has been used
    private var connectable: [AgentHookInstaller] {
        let installers = AgentHookInstaller.all.filter { !connected.contains($0.agent) }
        let present = installers.filter(\.isAgentPresent)
        return present.isEmpty && connected.isEmpty ? installers : present
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))

            if connected.isEmpty {
                Text("No agent is connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text("No agent sessions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Sessions show up here once you send an agent a prompt")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if !connectable.isEmpty {
                HStack(spacing: 8) {
                    ForEach(connectable, id: \.agent) { installer in
                        connectButton(installer)
                    }
                }
            }

            if let caption = errorText ?? note ?? (connectable.isEmpty ? nil : "Adds hooks to the agent's config file (backed up first)") {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(errorText == nil ? .white.opacity(0.4) : .red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func connectButton(_ installer: AgentHookInstaller) -> some View {
        let button = Button("Connect \(installer.agent.displayName)") {
            do {
                try installer.install()
                connected.insert(installer.agent)
                errorText = nil
                // Codex runs a new hook only once you've trusted it
                note = installer.agent == .codex ? "In Codex, run /hooks and trust the new hooks" : nil
            } catch {
                errorText = error.localizedDescription
            }
        }
        .tint(installer.agent.color)
        // The main call to action until an agent is connected
        if connected.isEmpty {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
