import AppKit

/// Brings the terminal tab (or the app) an agent session runs in to the front
enum TerminalFocuser {
    private static let terminalID = "com.apple.Terminal"
    private static let iTermID = "com.googlecode.iterm2"

    static func focus(_ terminal: AgentTerminal) {
        guard let bundleID = terminal.appBundleID ?? bundleID(forTermProgram: terminal.termProgram) else { return }

        // Terminal and iTerm2 can select the exact tab; anything else (an editor, the Claude, Codex or ZCode app) is just activated
        if let tty = terminal.tty, isDeviceName(tty), let script = selectTabScript(bundleID: bundleID, tty: "/dev/\(tty)") {
            Task {
                if await AppleScriptHelper.execute(script) == nil {
                    activate(bundleID)
                }
            }
        } else {
            activate(bundleID)
        }
    }

    private static func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private static func bundleID(forTermProgram program: String?) -> String? {
        switch program {
        case "Apple_Terminal": return terminalID
        case "iTerm.app": return iTermID
        default: return nil
        }
    }

    /// Only ever put a plain device name like "ttys003" into a script
    private static func isDeviceName(_ tty: String) -> Bool {
        !tty.isEmpty && tty.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func selectTabScript(bundleID: String, tty: String) -> String? {
        switch bundleID {
        case terminalID:
            return """
                tell application id "\(terminalID)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(tty)" then
                                set selected tab of w to t
                                set index of w to 1
                            end if
                        end repeat
                    end repeat
                    activate
                end tell
                return "ok"
                """
        case iTermID:
            return """
                tell application id "\(iTermID)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(tty)" then
                                    select w
                                    select t
                                    select s
                                end if
                            end repeat
                        end repeat
                    end repeat
                    activate
                end tell
                return "ok"
                """
        default:
            return nil
        }
    }
}
