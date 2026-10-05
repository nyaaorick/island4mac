import Foundation
import ServiceManagement

public struct LaunchAtLogin {
    public static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                // Fallback for older macOS or if strictly needed
                // This is a simplified check; reliable legacy support requires a helper app.
                return false
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled { return }
                        try SMAppService.mainApp.register()
                    } else {
                        if SMAppService.mainApp.status == .notRegistered { return }
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Example App: Failed to update launch at login status: \(error)")
                }
            } else {
                // Fallback for older macOS
                print("Launch at login is only supported on macOS 13+ in this version.")
            }
        }
    }
}
