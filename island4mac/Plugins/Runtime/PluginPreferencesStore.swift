import Foundation
import Combine

/// The values you gave plugins' preferences (PluginPreference). Plain ones are in UserDefaults under
/// `pluginPreferences.<id>`, secure ones in the Keychain under `<bundle id>.plugin.<id>`. A preference you never
/// set has its plugin's default
@MainActor
final class PluginPreferencesStore: ObservableObject {
    static let shared = PluginPreferencesStore(defaults: .standard, secrets: KeychainService())

    /// A plugin's id, each time one of its values changes
    let changes = PassthroughSubject<String, Never>()

    private let defaults: UserDefaults
    private let secrets: SecretStorage

    init(defaults: UserDefaults, secrets: SecretStorage) {
        self.defaults = defaults
        self.secrets = secrets
    }

    func value(of preference: PluginPreference, for pluginID: String) -> PluginPreferenceValue {
        storedValue(of: preference, for: pluginID).flatMap(preference.accepted) ?? preference.fallback
    }

    /// Every preference of a plugin, by key, as it is sent to the plugin
    func values(for manifest: PluginManifest) -> [String: PluginPreferenceValue] {
        Dictionary(uniqueKeysWithValues: (manifest.preferences ?? []).map { ($0.key, value(of: $0, for: manifest.id)) })
    }

    /// Whether a required preference is still empty, so the plugin can't start yet
    func needsSetup(_ manifest: PluginManifest) -> Bool {
        (manifest.preferences ?? []).contains { $0.isMissing(value(of: $0, for: manifest.id)) }
    }

    func set(_ value: PluginPreferenceValue, of preference: PluginPreference, for pluginID: String) {
        guard let value = preference.accepted(value), value != self.value(of: preference, for: pluginID) else { return }
        objectWillChange.send()
        if preference.kind == .secure {
            guard case .string(let text) = value else { return }
            secrets.write(text.isEmpty ? nil : text, service: Self.service(for: pluginID), account: preference.key)
        } else {
            var stored = defaults.dictionary(forKey: Self.defaultsKey(for: pluginID)) ?? [:]
            stored[preference.key] = value.object
            defaults.set(stored, forKey: Self.defaultsKey(for: pluginID))
        }
        changes.send(pluginID)
    }

    /// Forgets a removed plugin's values, secrets included
    func removeAll(for pluginID: String) {
        objectWillChange.send()
        defaults.removeObject(forKey: Self.defaultsKey(for: pluginID))
        secrets.removeAll(service: Self.service(for: pluginID))
    }

    private func storedValue(of preference: PluginPreference, for pluginID: String) -> PluginPreferenceValue? {
        if preference.kind == .secure {
            return secrets.read(service: Self.service(for: pluginID), account: preference.key).map { .string($0) }
        }
        return defaults.dictionary(forKey: Self.defaultsKey(for: pluginID))?[preference.key].flatMap(PluginPreferenceValue.init(object:))
    }

    static func defaultsKey(for pluginID: String) -> String { "pluginPreferences.\(pluginID)" }

    static func service(for pluginID: String) -> String {
        "\(Bundle.main.bundleIdentifier ?? "com.nyaaorick.island4mac").plugin.\(pluginID)"
    }
}
