import SwiftUI

struct CalendarSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("日历与日程")) {
                ToggleSettingsRow(
                    key: SettingsDefaults.showCalendar,
                    title: "显示日历日程",
                    help: "在展开状态下显示即将到来的日程安排"
                )
                
                Button("请求日历访问权限") {
                    // Trigger permission request
                    CalendarManager.shared.requestAuthorization()
                }
                
                Picker("预测范围", selection: Binding(
                    get: { SettingsDefaults.shared.get(SettingsDefaults.upcomingEventLookAheadDuration) },
                    set: { SettingsDefaults.shared.set(SettingsDefaults.upcomingEventLookAheadDuration, value: $0) }
                )) {
                    Text("未来 12 小时").tag(12)
                    Text("未来 24 小时").tag(24)
                    Text("未来 48 小时").tag(48)
                }
                
                ToggleSettingsRow(
                    key: SettingsDefaults.showMeetingJoinButton,
                    title: "显示加入会议按钮",
                    help: "如果检测到在线会议链接，直接在灵动岛内显示加入按钮"
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
