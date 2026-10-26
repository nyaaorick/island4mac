import Foundation

extension AgentSession {
    var statusText: String {
        switch status {
        case .idle: return "Ready"
        case .working: return runningSubagents > 0 ? "Working · \(runningSubagents) subagents" : "Working"
        case .needsPermission: return isAsking ? "Has a question" : "Needs permission"
        case .compacting: return "Compacting"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }

    /// Beside the notch: finished tasks out of all of them, otherwise how long the turn has run
    func progressText(at now: Date) -> String? {
        if !tasks.isEmpty { return "\(completedTaskCount)/\(tasks.count)" }
        return elapsed(at: now).map(Self.formatDuration)
    }

    /// The colored line under "You: …" while the agent works or waits
    var statusLineText: String {
        switch status {
        case .needsPermission:
            if isAsking { return "Waiting for your answer" }
            return ["Needs permission", activity].compactMap { $0 }.joined(separator: " · ")
        case .compacting:
            return "Compacting the conversation"
        default:
            let subagents = runningSubagents > 0 ? " · \(runningSubagents) subagents" : ""
            return (activity ?? "Working") + subagents
        }
    }

    /// How long ago, in the list: "now", "5m", "3h", "2d"
    nonisolated static func formatAge(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
