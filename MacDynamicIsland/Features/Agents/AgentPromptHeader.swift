import SwiftUI

/// Top of a prompt card: who's asking, a way to leave it to the terminal, and what you can do here
struct AgentPromptHeader: View {
    let prompt: AgentPrompt
    let session: AgentSession?
    let symbol: String
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.yellow)
                Text("\(session?.projectName ?? prompt.agent.displayName) · \(title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    AgentSessionStore.shared.dismissPrompt(prompt.id)
                    if let session { TerminalFocuser.focus(session.terminal) }
                } label: {
                    Text("Answer in terminal")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Leave this to the terminal and bring it to the front")
            }
            Text(prompt.canAnswer ? hint : "Answer this one in the terminal: the session started before the island could answer for it")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

extension View {
    /// Yellow card behind a prompt the island can answer (permission or question)
    func agentPromptCard() -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                    )
            )
    }
}
