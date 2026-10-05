import SwiftUI

/// The session's task list: counts, then a few items around the one the agent is on
struct AgentTaskChecklist: View {
    let tasks: [AgentTask]
    private let limit = 4

    var body: some View {
        let done = tasks.filter(\.isCompleted).count
        let inProgress = tasks.filter { $0.isActive && !$0.isCompleted }.count
        let current = tasks.firstIndex { !$0.isCompleted } ?? tasks.count
        let first = max(0, min(current - 1, tasks.count - limit))
        let shown = Array(tasks[first..<min(tasks.count, first + limit)])
        let remaining = tasks.count - first - shown.count

        VStack(alignment: .leading, spacing: 3) {
            Text("\(Text("Tasks").fontWeight(.semibold)) (\(done) done, \(inProgress) in progress, \(tasks.count - done - inProgress) pending)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

            if first > 0 {
                Text("\(first) done above")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            ForEach(shown) { task in
                HStack(spacing: 6) {
                    Image(systemName: task.isCompleted ? "checkmark.square.fill" : task.isActive ? "circle.dotted.circle" : "square")
                        .font(.system(size: 10))
                        .foregroundStyle(task.isCompleted ? .white.opacity(0.35) : task.isActive ? .orange : .white.opacity(0.5))
                    Text(task.title)
                        .font(.system(size: 11, weight: task.isActive ? .semibold : .regular))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .white.opacity(0.35) : .white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            if remaining > 0 {
                Text("+\(remaining) more")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandInset(cornerRadius: 8)
    }
}
