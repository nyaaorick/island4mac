import Combine
import Foundation
import os

/// Administrator access for plugins: one password, saved in the Keychain under Settings > Plugins, and a switch per
/// plugin that declares `"needs": ["admin"]`. A plugin the user allowed can ask the island to run a command as an
/// administrator (PluginMessage.sudo); the island hands the password to sudo on its stdin, never to the plugin
@MainActor
final class AdminAccessStore: ObservableObject {
    static let shared = AdminAccessStore(defaults: .standard, secrets: KeychainService())

    struct Result: Equatable {
        let status: Int32
        let output: String
        let error: String

        static func refused(_ reason: String) -> Result { Result(status: -1, output: "", error: reason) }
    }

    /// Runs `command` as root with `password`; tests replace it
    typealias Runner = @Sendable (_ command: [String], _ input: String?, _ password: String, _ timeout: TimeInterval) async -> Result

    /// Whether a password is saved
    @Published private(set) var isConfigured: Bool
    /// The plugins allowed to use it
    @Published private(set) var allowed: Set<String>

    /// UserDefaults key: the ids of plugins allowed administrator access
    static let allowedKey = "adminAllowedPlugins"
    private static let account = "administrator"

    private let defaults: UserDefaults
    private let secrets: SecretStorage
    private let service: String
    var runner: Runner = AdminAccessStore.sudo
    private let logger = Logger(subsystem: Log.subsystem, category: "AdminAccess")

    init(defaults: UserDefaults, secrets: SecretStorage, service: String = "\(Bundle.main.bundleIdentifier ?? "com.nyaaorick.island4mac").admin") {
        self.defaults = defaults
        self.secrets = secrets
        self.service = service
        allowed = Set(defaults.stringArray(forKey: Self.allowedKey) ?? [])
        isConfigured = secrets.read(service: service, account: Self.account) != nil
    }

    func isAllowed(_ pluginID: String) -> Bool { allowed.contains(pluginID) }

    func setAllowed(_ pluginID: String, _ allow: Bool) {
        if allow { allowed.insert(pluginID) } else { allowed.remove(pluginID) }
        defaults.set(allowed.sorted(), forKey: Self.allowedKey)
    }

    /// Checks the password with sudo and saves it if it works. Nil when saved; else why not
    func save(password: String) async -> String? {
        let result = await runner(["/usr/bin/true"], nil, password, 15)
        guard result.status == 0 else { return result.error.isEmpty ? "sudo refused the password" : result.error }
        secrets.write(password, service: service, account: Self.account)
        isConfigured = true
        return nil
    }

    func forget() {
        secrets.write(nil, service: service, account: Self.account)
        isConfigured = false
    }

    /// Runs the command as an administrator for `pluginID`, or says why not
    func run(_ command: [String], input: String?, timeout: TimeInterval, for pluginID: String) async -> Result {
        guard isAllowed(pluginID) else { return .refused("administrator access is turned off for this plugin (Settings > Plugins)") }
        guard let password = secrets.read(service: service, account: Self.account) else {
            return .refused("no administrator password is saved (Settings > Plugins)")
        }
        guard let program = command.first, !program.isEmpty else { return .refused("empty command") }
        logger.notice("Plugin \(pluginID, privacy: .public) runs as administrator: \(program, privacy: .public)")
        return await runner(command, input, password, timeout)
    }

    /// `sudo -S -k -p '' -- command…`, the password (then `input`) on its stdin. sudo's own refusals are told apart from
    /// the program's failure so Settings can say "wrong password" rather than show a stack of stderr
    nonisolated static let sudo: Runner = { command, input, password, timeout in
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-S", "-k", "-p", "", "--"] + command
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return Result.refused("couldn't start sudo: \(error.localizedDescription)")
            }
            stdin.fileHandleForWriting.write(Data((password + "\n" + (input ?? "")).utf8))
            try? stdin.fileHandleForWriting.close()
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            let group = DispatchGroup()
            nonisolated(unsafe) var outData = Data()
            group.enter()
            DispatchQueue.global().async { outData = stdout.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.wait()
            process.waitUntilExit()
            let timedOut = deadline.isCancelled == false && !process.isRunning && process.terminationReason == .uncaughtSignal
            deadline.cancel()
            let error = String(decoding: errData, as: UTF8.self)
            if timedOut { return Result.refused("timed out after \(Int(timeout)) seconds") }
            if process.terminationStatus != 0 {
                if error.contains("incorrect password") || error.contains("Sorry, try again") || error.contains("no password was provided") {
                    return Result.refused("wrong administrator password (Settings > Plugins)")
                }
                if error.contains("not in the sudoers") || error.contains("is not allowed") {
                    return Result.refused("this account isn't an administrator")
                }
            }
            return Result(status: process.terminationStatus, output: String(decoding: outData, as: UTF8.self), error: error)
        }.value
    }
}
