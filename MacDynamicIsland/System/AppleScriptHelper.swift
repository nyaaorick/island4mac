//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-08-20.
//

import Foundation
import AppKit

/// Helper for executing AppleScript commands
/// Note: AppleScript automation is not allowed in sandboxed App Store apps
nonisolated final class AppleScriptHelper {

    /// Scripts run one at a time here rather than on the main thread: an Apple Event round trip
    /// can take hundreds of milliseconds (or wait on a permission prompt) and would stall the UI
    private static let queue = DispatchQueue(label: "com.maclingdonggao.applescript", qos: .userInitiated)

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
                print("AppleScript error: \(error)")
                return nil
            }
            return output.stringValue
        }
        return nil
    }
}
