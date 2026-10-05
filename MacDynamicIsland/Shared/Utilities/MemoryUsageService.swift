import Combine
import Foundation
import AppKit
import os

/// Memory management and optimization utility
class MemoryUsageService {
    static let shared = MemoryUsageService()
    
    private init() {}
    
    // MARK: - Memory Info
    
    func currentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    func formattedMemoryUsage() -> String {
        let bytes = currentMemoryUsage()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func logMemoryUsage() {
        logInfo("Current memory usage: \(formattedMemoryUsage())")
    }
    
    private func logInfo(_ message: String) {
        let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "MemoryUsageService")
        logger.info("\(message, privacy: .public)")
    }
}
