import Foundation
import os

/// The app's loggers: `Logger(subsystem: Log.subsystem, category: "...")`, read with Console.app or `log stream`
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "island4mac"
}
