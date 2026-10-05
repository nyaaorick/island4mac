import Foundation

/// Safe localization helper that prevents crashes on missing keys
struct Localization {
    /// Simple localization without arguments
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    
    /// Localization with string formatting arguments
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, arguments: args)
    }
}

/// Convenient shorthand: L("key") for localized strings
func L(_ key: String) -> String {
    Localization.string(key)
}

/// Convenient shorthand with format arguments: L("key", arg1, arg2)
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, arguments: args)
}
