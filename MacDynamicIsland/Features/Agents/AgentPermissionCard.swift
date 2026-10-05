import SwiftUI

/// A tool call Claude Code wants to make, allowed or denied right in the island
struct AgentPermissionCard: View {
    let prompt: AgentPrompt
    let permission: AgentPermission
    let session: AgentSession?
    /// What Claude should do instead; denying with it lets Claude carry on
    @State private var note = ""

    private var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentPromptHeader(
                prompt: prompt,
                session: session,
                symbol: "hand.raised.fill",
                title: "\(prompt.agent.shortName) wants to use \(permission.toolName)",
                hint: "Allow or deny here, or answer in the terminal"
            )

            Text(permission.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            if let detail = permission.detail, detail != permission.summary {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .islandInset(cornerRadius: 6)
            }

            if prompt.canAnswer {
                TextField("Or tell Claude what to do instead…", text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .islandInset(cornerRadius: 6)
                    .onSubmit { if hasNote { respond { $0.deny(prompt.id, note: note) } } }

                HStack(spacing: 8) {
                    Button(hasNote ? "Deny with note" : "Deny") {
                        respond { $0.deny(prompt.id, note: note) }
                    }
                    .help(hasNote ? "Deny, and Claude carries on with your note" : "Deny and stop Claude, like Esc in the terminal")

                    if let always = permission.alwaysAllowDescription {
                        Button("Always allow") {
                            respond { $0.allow(prompt.id, always: true) }
                        }
                        .help("Allow, and don't ask again for \(always)")
                    }

                    Spacer()

                    // Only a click allows: as the default button, Return in the note above would allow the call
                    // instead of sending the note, and so would Return anywhere else in the island
                    Button("Allow") {
                        respond { $0.allow(prompt.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
                }
                .controlSize(.small)

                if let always = permission.alwaysAllowDescription {
                    Text("Always allow adds \(always)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }
            }
        }
        .agentPromptCard()
    }

    private func respond(_ action: (AgentSessionStore) -> Void) {
        withAnimation(boringInteractiveSpring) { action(AgentSessionStore.shared) }
    }
}
