import AppKit
import Combine

/// Remembers the app you were using before the island: the frontmost app other than the island's own process
/// (`ignoring`: this app, or the app that runs a plugin). Pasting from the clipboard goes into it
@MainActor
final class FrontmostAppMonitor {
    private(set) var previousApp: NSRunningApplication?
    private var observer: AnyCancellable?

    init(ignoring ownPID: pid_t) {
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ownPID ? nil : $0 }
        observer = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { $0.processIdentifier != ownPID }
            .sink { [weak self] app in
                MainActor.assumeIsolated { self?.previousApp = app }
            }
    }
}
