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
class AppleScriptHelper {
    
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
    
    /// Execute AppleScript and return result as Int
    static func executeScriptReturningInt(_ script: String) -> Int? {
        guard let result = executeScript(script) else { return nil }
        return Int(result)
    }
    
    /// Execute AppleScript and return result as Double
    static func executeScriptReturningDouble(_ script: String) -> Double? {
        guard let result = executeScript(script) else { return nil }
        return Double(result)
    }
    
    /// Execute AppleScript and return result as Bool
    static func executeScriptReturningBool(_ script: String) -> Bool? {
        guard let result = executeScript(script) else { return nil }
        return result.lowercased() == "true" || result == "1"
    }
    
    /// Execute AppleScript without expecting a return value
    @discardableResult
    static func executeScriptVoid(_ script: String) -> Bool {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                return false
            }
            return true
        }
        return false
    }
    
    /// Execute AppleScript and return result as Data
    static func executeScriptReturningData(_ script: String) -> Data? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
                return nil
            }
            // Try to get data descriptor
            return output.data
        }
        return nil
    }
}
