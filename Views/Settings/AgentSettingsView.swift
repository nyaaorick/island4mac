import SwiftUI

struct AgentSettingsView: View {
    var body: some View {
        Form {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                Section(header: Text(agent.displayName)) {
                    AgentConnectionRow(installer: .standard(agent))
                }
            }

            Section(header: Text("通用")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showAgentLiveActivity,
                    title: "在刘海旁显示进度",
                    help: "Agent 工作中、等你授权或刚完成时，在收起的灵动岛旁显示状态和进度"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.agentQuestionsOpenIsland,
                    title: "有问题时自动展开",
                    help: "Claude 让你回答问题或做选择时，自动展开灵动岛，可以直接在岛上作答（也仍可在终端里回答）"
                )

                ToggleSettingsRow(
                    key: SettingsDefaults.agentSoundsEnabled,
                    title: "提示音",
                    help: "Agent 需要你授权、完成或出错时播放系统提示音"
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
                Text(isInstalled ? "已接入" : "未接入")
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isInstalled ? "断开" : "接入 \(installer.agent.displayName)") {
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
        let base = "接入后会在 \(file) 里添加钩子（首次修改前会备份），已有的钩子不受影响"
        switch installer.agent {
        case .claude:
            return base
        case .codex:
            return base + "。Codex 要你信任新钩子后才会运行：接入后在 Codex 里输入 /hooks 确认"
        case .zcode:
            return base + "，并打开配置文件钩子（hooks.enabled）"
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
