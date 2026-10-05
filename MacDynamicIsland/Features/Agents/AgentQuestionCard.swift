import SwiftUI

/// A question an agent is waiting on, answered right in the island. With a single question that takes one
/// choice, picking an option answers it; otherwise you pick, then submit.
struct AgentQuestionCard: View {
    let prompt: AgentPrompt
    let questions: [AgentQuestion]
    let session: AgentSession?
    /// Question text → the labels you picked
    @State private var picked: [String: Set<String>] = [:]
    /// Question text → your own answer
    @State private var typed: [String: String] = [:]

    private var answersOnTap: Bool {
        questions.count == 1 && !questions[0].allowsMultipleSelection && !questions[0].options.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentPromptHeader(
                prompt: prompt,
                session: session,
                symbol: "questionmark.bubble.fill",
                title: "\(prompt.agent.shortName) is asking you",
                hint: answersOnTap ? "Pick an answer here, or answer in the terminal" : "Answer here and submit, or answer in the terminal"
            )

            ForEach(questions) { item in
                questionView(item)
            }

            if prompt.canAnswer && !answersOnTap {
                HStack {
                    Spacer()
                    Button("Submit") { submit() }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                        .foregroundStyle(.black)
                        .controlSize(.small)
                        .disabled(answers == nil)
                }
            }
        }
        .agentPromptCard()
    }

    private func questionView(_ item: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let header = item.header {
                    Text(header)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.15)))
                }
                Text(item.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(item.options, id: \.label) { option in
                optionRow(option, of: item)
            }

            TextField(item.options.isEmpty ? "Your answer" : "Other…", text: typedBinding(for: item))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .islandInset(cornerRadius: 6)
                .disabled(!prompt.canAnswer)
                .onSubmit { if answers != nil { submit() } }
        }
    }

    private func optionRow(_ option: AgentQuestion.Option, of item: AgentQuestion) -> some View {
        let isPicked = picked[item.text, default: []].contains(option.label)
        let symbol = item.allowsMultipleSelection
            ? (isPicked ? "checkmark.square.fill" : "square")
            : (isPicked ? "largecircle.fill.circle" : "circle")
        return Button {
            pick(option.label, in: item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(isPicked ? .yellow : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    if let description = option.description {
                        Text(description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .islandInset(cornerRadius: 6, highlighted: isPicked)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!prompt.canAnswer)
    }

    private func pick(_ label: String, in item: AgentQuestion) {
        if item.allowsMultipleSelection {
            picked[item.text, default: []].formSymmetricDifference([label])
            return
        }
        picked[item.text] = [label]
        typed[item.text] = nil
        if answersOnTap { submit() }
    }

    private func typedBinding(for item: AgentQuestion) -> Binding<String> {
        Binding(
            get: { typed[item.text] ?? "" },
            set: { text in
                typed[item.text] = text
                // Your own words replace a single choice
                if !item.allowsMultipleSelection && !text.isEmpty { picked[item.text] = nil }
            }
        )
    }

    /// Every question's answer, or nil while one is unanswered
    private var answers: [String: String]? {
        var answers: [String: String] = [:]
        for item in questions {
            let own = (typed[item.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = item.options.map(\.label).filter { picked[item.text, default: []].contains($0) }
            let parts = item.allowsMultipleSelection ? chosen + (own.isEmpty ? [] : [own]) : [own.isEmpty ? chosen.first : own].compactMap { $0 }
            guard !parts.isEmpty else { return nil }
            answers[item.text] = parts.joined(separator: ", ")
        }
        return answers
    }

    private func submit() {
        guard prompt.canAnswer, let answers else { return }
        withAnimation(boringInteractiveSpring) {
            AgentSessionStore.shared.answer(prompt.id, with: answers)
        }
    }
}
