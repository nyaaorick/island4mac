import Foundation
import os
import AppKit

/// Runs AppleScript commands against other apps
/// Needs the Apple Events entitlement and the user's Automation permission; the app isn't sandboxed
nonisolated final class AppleScriptClient {

    /// Scripts run one at a time here rather than on the main thread: an Apple Event round trip
    /// can take hundreds of milliseconds (or wait on a permission prompt) and would stall the UI
    private static let queue = DispatchQueue(label: "island4mac.applescript", qos: .userInitiated)

    /// Off-main-thread version of `executeScript(_:)`
    static func execute(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: executeScript(script)) }
        }
    }

    /// Execute AppleScript and return the result as String
    static func executeScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "island4mac", category: "AppleScript").error("\(String(describing: error), privacy: .public)")
                return nil
            }
            return output.stringValue
        }
        return nil
    }
}
