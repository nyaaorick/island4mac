//
//  Mac灵动岛App.swift
//  Mac灵动岛
//
//  Created by apple密码1111 on 2026/1/20.
//

import SwiftUI

@main
struct Mac_Dynamic_IslandApp: App {
    
    // 🔥 核心关键：这就相当于把你的 AppDelegate "插" 进了程序里
    // 如果没有这一行，你的 AppDelegate 永远不会运行，窗口也就永远不会出来
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = OverlayWindowController.shared.getAppState()

    var body: some Scene {
        // 因为我们是做灵动岛（纯代码控制窗口），所以这里不要放 WindowGroup
        // 放一个空的 Settings 即可，避免系统自动创建一个空白的主窗口
        Settings {
            MainSettingsView()
                .environmentObject(appState)
        }
    }
}
