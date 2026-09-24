import SwiftUI

struct AgentSettingsView: View {
    @State private var isInstalled = ClaudeHookInstaller.standard.isInstalled
    @State private var errorText: String?

    var body: some View {
        Form {
            Section(header: Text("Claude Code")) {
                HStack {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundColor(isInstalled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isInstalled ? "已接入" : "未接入")
                        Text("接入后会在 ~/.claude/settings.json 里添加钩子（首次修改前会备份），已有的钩子不受影响")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isInstalled ? "断开" : "接入 Claude Code") {
                        toggleInstallation()
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                ToggleSettingsRow(
                    key: SettingsDefaults.showAgentLiveActivity,
                    title: "在刘海两侧显示进度",
                    help: "Claude Code 工作中、等你授权或刚完成时，在收起的灵动岛两侧显示状态和进度"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.agentSoundsEnabled,
                    title: "提示音",
                    help: "Claude 需要你授权、完成或出错时播放系统提示音"
                )
            }
        }
    }

    private func toggleInstallation() {
        let installer = ClaudeHookInstaller.standard
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
