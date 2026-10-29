import Foundation

/// A dotted version ("1.10.2", or "v1.10.2"), compared number by number: 1.10 is newer than 1.9, and 1.2 is 1.2.0.
/// Anything that isn't numbers and dots isn't a version
struct Version: Comparable, Equatable, CustomStringConvertible {
    let numbers: [Int]

    init?(_ text: String) {
        let parts = (text.hasPrefix("v") ? String(text.dropFirst()) : text).split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        numbers = parts.compactMap { $0 }
    }

    var description: String { numbers.map(String.init).joined(separator: ".") }

    static func < (lhs: Version, rhs: Version) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let x = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let y = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (lhs: Version, rhs: Version) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    /// Whether `version` is newer than `other`; false when either isn't a version, so nothing is ever offered as
    /// an update by mistake
    static func isVersion(_ version: String, newerThan other: String) -> Bool {
        guard let a = Version(version), let b = Version(other) else { return false }
        return b < a
    }
}
