//
//  SettingsViews.swift
//  MacDynamicIsland
//
//  Shared Settings Components
//

import SwiftUI

// MARK: - Helper Components
struct ToggleSettingsRow: View {
    let key: SettingsKey<Bool>
    let title: String
    let help: String
    
    @State private var isOn: Bool
    
    init(key: SettingsKey<Bool>, title: String, help: String) {
        self.key = key
        self.title = title
        self.help = help
        _isOn = State(initialValue: SettingsDefaults.shared.get(key))
    }
    
    var body: some View {
        Toggle(title, isOn: $isOn)
            .help(help)
            .onChange(of: isOn) { _, newValue in
                SettingsDefaults.shared.set(key, value: newValue)
            }
    }
}
