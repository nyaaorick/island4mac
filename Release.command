#!/usr/bin/env swift
// Builds a release: the Release configuration, signed with the self-signed "island4mac Release" certificate, as
// build/Release/island4mac.dmg. With --publish it also publishes the DMG as the GitHub release v<version>, with the
// version's CHANGELOG.md section as its notes; installed copies find it there when they launch (UpdateClient).
// The whole process and where the certificate lives: CLAUDE.md, "Releasing". Swift, so the repo stays Swift-only.
import Foundation

let identity = "island4mac Release"
/// SHA-1 of that certificate. Installed copies only take an update signed with it, and macOS keeps their permissions
/// only for it, so a release signed with any other certificate is refused here
let certificateHash = "0549e796d95b726aaf3976ba02629b29b8367590"
let bundleID = "com.macdynamicisland.app"

let publish = CommandLine.arguments.contains("--publish")
let root = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
let output = root.appendingPathComponent("build/Release")
let archive = output.appendingPathComponent("MacDynamicIsland.xcarchive")
let app = archive.appendingPathComponent("Products/Applications/MacDynamicIsland.app")
let dmg = output.appendingPathComponent("island4mac.dmg")

@discardableResult
func run(_ tool: String, _ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.currentDirectoryURL = root
    do { try process.run() } catch { return 127 }
    process.waitUntilExit()
    return process.terminationStatus
}

/// The tool's output, trimmed, or nil when it fails
func capture(_ tool: String, _ args: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.currentDirectoryURL = root
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func fail(_ message: String) -> Never {
    print("\n\(message)")
    print("Press Return to close.")
    _ = readLine()
    exit(1)
}

/// What CHANGELOG.md says under "## <version>", up to the next "## "
func changelog(for version: String) -> String? {
    guard let text = try? String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8) else { return nil }
    var section: [Substring]?
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("## ") {
            if section != nil { break }
            if line.dropFirst(3).split(separator: " ").first == Substring(version) { section = [] }
        } else {
            section?.append(line)
        }
    }
    let notes = section?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return notes.isEmpty ? nil : notes
}

// 1. The certificate, and the version (MARKETING_VERSION)
guard capture("/usr/bin/security", ["find-identity", "-p", "codesigning"])?.contains("\"\(identity)\"") == true else {
    fail("No \"\(identity)\" certificate in the keychain. Import its .p12 backup (CLAUDE.md, \"Releasing\").")
}
let settings = capture("/usr/bin/xcodebuild", ["-project", "MacDynamicIsland.xcodeproj", "-target", "MacDynamicIsland",
                                               "-configuration", "Release", "-showBuildSettings"]) ?? ""
guard let version = settings.split(separator: "\n")
    .map({ $0.trimmingCharacters(in: .whitespaces) })
    .first(where: { $0.hasPrefix("MARKETING_VERSION = ") })?
    .dropFirst("MARKETING_VERSION = ".count) else { fail("Couldn't read MARKETING_VERSION.") }
let tag = "v\(version)"
let notes = changelog(for: String(version))

// 2. Publishing needs a clean, pushed commit, a CHANGELOG.md section and a version not yet released
if publish {
    guard capture("/usr/bin/git", ["status", "--porcelain"]) == "" else {
        fail("Commit your changes first: a release is built from a commit.")
    }
    guard let remotes = capture("/usr/bin/git", ["branch", "-r", "--contains", "HEAD"]), !remotes.isEmpty else {
        fail("Push this commit first.")
    }
    guard notes != nil else { fail("CHANGELOG.md has no section \"## \(version)\". Add one: it becomes the release notes.") }
    guard capture("/usr/bin/env", ["gh", "release", "view", tag]) == nil else {
        fail("\(tag) is already released. Raise MARKETING_VERSION.")
    }
} else if notes == nil {
    print("Note: CHANGELOG.md has no section \"## \(version)\" yet; --publish will need one.")
}

// 3. Build and sign
try? FileManager.default.removeItem(at: output)
print("Building \(version)...")
let build = run("/usr/bin/xcodebuild", [
    "-project", "MacDynamicIsland.xcodeproj",
    "-scheme", "MacDynamicIsland",
    "-configuration", "Release",
    "-destination", "generic/platform=macOS",
    "-derivedDataPath", root.appendingPathComponent("build").path,
    "-archivePath", archive.path,
    "-quiet",
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=\(identity)",
    "DEVELOPMENT_TEAM=",
    "archive",
])
guard build == 0 else { fail("Build failed (xcodebuild exit \(build)). Check the output above.") }

// 4. Check what users will run: a valid signature, the release certificate and bundle id, the version
guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
    fail("The app's signature doesn't verify.")
}
let requirement = capture("/usr/bin/codesign", ["-d", "-r-", app.path]) ?? ""
guard requirement.contains("identifier \"\(bundleID)\""), requirement.contains("certificate leaf = H\"\(certificateHash)\"") else {
    fail("The app isn't signed with the release certificate: \(requirement)")
}
let built = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
guard built == String(version) else { fail("The app says version \(built ?? "?"), not \(version).") }

// 5. The DMG: the app beside a link to Applications, to drag it onto
print("Making \(dmg.lastPathComponent)...")
let staging = output.appendingPathComponent("dmg")
try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
guard run("/usr/bin/ditto", [app.path, staging.appendingPathComponent(app.lastPathComponent).path]) == 0,
      (try? FileManager.default.createSymbolicLink(atPath: staging.appendingPathComponent("Applications").path,
                                                   withDestinationPath: "/Applications")) != nil,
      run("/usr/bin/hdiutil", ["create", "-volname", "island4mac", "-srcfolder", staging.path, "-format", "ULFO",
                               "-ov", "-quiet", dmg.path]) == 0 else { fail("Couldn't make the DMG.") }
try? FileManager.default.removeItem(at: staging)

// 6. Publish
guard publish, let notes else {
    print("\nBuilt \(dmg.path)")
    print("Publish it as \(tag) with: ./Release.command --publish")
    exit(0)
}
let notesFile = output.appendingPathComponent("notes.md")
try? notes.write(to: notesFile, atomically: true, encoding: .utf8)
let commit = capture("/usr/bin/git", ["rev-parse", "HEAD"]) ?? "HEAD"
guard run("/usr/bin/env", ["gh", "release", "create", tag, dmg.path, "--target", commit,
                           "--title", "island4mac \(version)", "--notes-file", notesFile.path]) == 0 else {
    fail("gh couldn't create the release.")
}
print("\nPublished \(tag). Installed copies offer it the next time they launch.")
