//
//  ClipboardSettingsWindow.swift
//  MacDynamicIsland
//
//  Clipboard Hub Settings Panel
//  Based on the requested Clipboard Hub configurations
//

import SwiftUI


struct ClipboardSettingsWindow: View {
    @ObservedObject var hubStore: ClipboardHubStore
    
    // Tab State
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(hubStore: hubStore)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            SecuritySettingsTab(hubStore: hubStore)
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
                .tag(1)
            
            StorageSettingsTab(hubStore: hubStore)
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
                .tag(2)
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject var hubStore: ClipboardHubStore
    
    var body: some View {
        Form {
            Section(header: Text("Layout")) {
                Picker("Default View", selection: $hubStore.displayMode) {
                    Text("Grid View").tag(ClipboardHubStore.DisplayMode.grid)
                    Text("Reel View (Horizontal)").tag(ClipboardHubStore.DisplayMode.reel)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("History")) {
                Picker("Max Items", selection: $hubStore.maxItems) {
                    Text("10").tag(10)
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .onChange(of: hubStore.maxItems) { _, newValue in
                    hubStore.updateSettings(maxItems: newValue)
                }
                
                Picker("Keep History For", selection: $hubStore.ttlHours) {
                    Text("24 Hours").tag(24)
                    Text("3 Days").tag(72)
                    Text("1 Week").tag(168)
                    Text("Forever").tag(0)
                }
                .onChange(of: hubStore.ttlHours) { _, newValue in
                     hubStore.updateSettings(ttlHours: newValue)
                }
            }
            
            Section(header: Text("Actions")) {
                Button("Clear All History") {
                    hubStore.clearAll()
                }
                .foregroundStyle(.red)
                
                 Button("Clear Unpinned Only") {
                    hubStore.clearUnpinned()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Security Tab

struct SecuritySettingsTab: View {
    @ObservedObject var hubStore: ClipboardHubStore
    
    var body: some View {
        Form {
            Section(header: Text("Privacy")) {
                Toggle("Enable Encryption", isOn: $hubStore.encryptionEnabled)
                    .onChange(of: hubStore.encryptionEnabled) { _, newValue in
                        hubStore.updateSettings(encryptionEnabled: newValue)
                    }
                
                Text("Encrypts clipboard history on disk using AES-256 GCM.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Access Control")) {
                Toggle("Require Touch ID / Password", isOn: $hubStore.touchIDEnabled)
                     .onChange(of: hubStore.touchIDEnabled) { _, newValue in
                        hubStore.updateSettings(touchIDEnabled: newValue)
                    }
                
                if hubStore.touchIDEnabled {
                    Picker("Auto-Lock After", selection: $hubStore.sessionTimeoutMinutes) {
                        Text("Immediately").tag(0)
                        Text("1 Minute").tag(1)
                        Text("5 Minutes").tag(5)
                        Text("15 Minutes").tag(15)
                        Text("1 Hour").tag(60)
                    }
                     .onChange(of: hubStore.sessionTimeoutMinutes) { _, newValue in
                        hubStore.updateSettings(sessionTimeout: newValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage Tab

struct StorageSettingsTab: View {
    @ObservedObject var hubStore: ClipboardHubStore
    
    var body: some View {
        Form {
            Section(header: Text("Statistics")) {
                HStack {
                    Text("Total Items")
                    Spacer()
                    Text("\(hubStore.totalItemCount)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Images")
                    Spacer()
                    Text("\(hubStore.imageItemCount)")
                        .foregroundColor(.secondary)
                }
                
                 HStack {
                    Text("Files")
                    Spacer()
                    Text("\(hubStore.fileItemCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Maintenance")) {
                Button("Prune Expired Items Now") {
                    hubStore.pruneExpiredItems()
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ClipboardSettingsWindow(hubStore: ClipboardHubStore())
}
