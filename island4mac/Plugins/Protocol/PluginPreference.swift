import Foundation

/// A setting a plugin declares in its plugin.json (protocol 2). The island draws it under Settings > Plugins in
/// its own style, keeps its value (secure ones in the Keychain) and sends the values to the plugin
/// (PluginEvent.preferences):
///
///     {"key":"apiKey","title":"API key","kind":"secure","required":true}
///     {"key":"minutes","title":"Refresh every","kind":"choice","default":5,
///      "options":[{"title":"1 min","value":1},{"title":"5 min","value":5}]}
struct PluginPreference: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        /// A line of text; `secure` hides it and keeps it in the Keychain
        case text, secure
        case toggle
        /// A number, within `minimum`...`maximum` when given
        case number
        /// One of `options`
        case choice
    }

    struct Option: Decodable, Equatable, Hashable {
        let title: String
        let value: PluginPreferenceValue
    }

    let key: String
    let title: String
    let kind: Kind
    var `default`: PluginPreferenceValue?
    var options: [Option]?
    var minimum: Double?
    var maximum: Double?
    /// The plugin doesn't start until it is filled in
    var required: Bool?
    var placeholder: String?

    var id: String { key }

    /// A plugin declares at most this many
    static let maxCount = 20

    /// Its value before you set one
    var fallback: PluginPreferenceValue {
        if let value = `default`.flatMap(accepted) { return value }
        switch kind {
        case .text, .secure: return .string("")
        case .toggle: return .bool(false)
        case .number: return .number(minimum ?? 0)
        case .choice: return options?.first?.value ?? .string("")
        }
    }

    /// Only a required text left empty is missing: the other kinds always have a value
    func isMissing(_ value: PluginPreferenceValue) -> Bool {
        guard required == true else { return false }
        if case .string(let text) = value { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    /// `value` made to fit this preference (a number kept in range), or nil if it can't
    func accepted(_ value: PluginPreferenceValue) -> PluginPreferenceValue? {
        switch (kind, value) {
        case (.text, .string), (.secure, .string), (.toggle, .bool): return value
        case (.number, .number(let number)):
            return .number(min(max(number, minimum ?? -.greatestFiniteMagnitude), maximum ?? .greatestFiniteMagnitude))
        case (.choice, _): return options?.contains { $0.value == value } == true ? value : nil
        default: return nil
        }
    }

    /// Why a plugin.json's preferences can't be used, if they can't
    static func problem(in preferences: [PluginPreference]) -> String? {
        guard preferences.count <= maxCount else { return "more than \(maxCount) preferences" }
        var keys = Set<String>()
        for preference in preferences {
            guard !preference.key.isEmpty else { return "a preference has no key" }
            guard keys.insert(preference.key).inserted else { return "preference \"\(preference.key)\" is declared twice" }
            if preference.kind == .choice, preference.options?.isEmpty ?? true {
                return "preference \"\(preference.key)\" is a choice without options"
            }
        }
        return nil
    }
}

/// A preference's value: what JSON can say of it
enum PluginPreferenceValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string): try container.encode(string)
        case .number(let number): try container.encode(number)
        case .bool(let bool): try container.encode(bool)
        }
    }

    /// For JSONSerialization and UserDefaults
    var object: Any {
        switch self {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        }
    }

    /// From what JSONSerialization or UserDefaults hold
    init?(object: Any) {
        if let number = object as? NSNumber {
            // NSNumber is also how booleans come back; tell them apart by their type
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        } else if let string = object as? String {
            self = .string(string)
        } else {
            return nil
        }
    }
}
