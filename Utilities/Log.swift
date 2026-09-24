import Foundation
import OSLog

/// App-wide logging helpers built on os.Logger.
/// Use `Log.subsystem` when creating a category-specific `os.Logger`.
struct Log {
    static let subsystem = "com.maclingdonggao.overlay"

    private static let appLogger = os.Logger(subsystem: subsystem, category: "app")

    // MARK: - App Lifecycle
    static func activityPosted(_ title: String, _ kind: String) {
        appLogger.info("📌 Activity: posted \(title) (\(kind))")
    }

    static func activityDismissed(_ title: String, _ kind: String) {
        appLogger.debug("✕ Activity: dismissed \(title)")
    }

    static func timerStarted(_ duration: TimeInterval) {
        appLogger.info("⏱️ Timer: started for \(Int(duration)) seconds")
    }

    static func timerStopped() {
        appLogger.info("⏹️ Timer: stopped")
    }
}
