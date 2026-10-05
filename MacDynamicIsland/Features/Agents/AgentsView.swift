import SwiftUI

struct AgentsView: View {
    @ObservedObject private var store = AgentSessionStore.shared

    var body: some View {
        if store.sessions.isEmpty {
            AgentsEmptyView()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                // Room between and below the panes for their shadows (IslandSurface)
                LazyVStack(spacing: 10) {
                    // What an agent is waiting on you for comes first
                    ForEach(store.pendingPrompts) { prompt in
                        let session = store.sessions.first { $0.id == prompt.sessionID }
                        switch prompt.kind {
                        case .question(let questions):
                            AgentQuestionCard(prompt: prompt, questions: questions, session: session)
                        case .permission(let permission):
                            AgentPermissionCard(prompt: prompt, permission: permission, session: session)
                        }
                    }
                    ForEach(store.sessions) { session in
                        AgentSessionRow(session: session)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 22)
            }
        }
    }
}
