#!/usr/bin/env swift
// Double-click to build MacDynamicIsland and launch it. Written in Swift so the repo stays Swift-only.
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
let derivedData = root.appendingPathComponent("build").path
let appPath = "\(derivedData)/Build/Products/Debug/MacDynamicIsland.app"

var environment = ProcessInfo.processInfo.environment

@discardableResult
func run(_ tool: String, _ args: [String], quiet: Bool = false) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.currentDirectoryURL = root
    process.environment = environment
    if quiet {
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    do { try process.run() } catch { return 127 }
    process.waitUntilExit()
    return process.terminationStatus
}

func fail(_ message: String) -> Never {
    print("\n\(message)")
    print("Press Return to close.")
    _ = readLine()
    exit(1)
}

// The only requirement is Xcode itself. If xcode-select points at the Command Line Tools
// (or nowhere), use an installed Xcode directly instead of asking the user to switch it.
if run("/usr/bin/xcodebuild", ["-version"], quiet: true) != 0 {
    let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
    let developerDirs = apps.filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }.sorted().reversed()
        .map { "/Applications/\($0)/Contents/Developer" }
    guard let dir = developerDirs.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        fail("Xcode is required to build the app. Install it from the App Store, open it once, then run this again.")
    }
    environment["DEVELOPER_DIR"] = dir
    if run("/usr/bin/xcodebuild", ["-version"], quiet: true) != 0 {
        fail("Xcode is installed but not ready. Open it once and accept the license, then run this again.")
    }
}

#if arch(arm64)
let arch = "arm64"
#else
let arch = "x86_64"
#endif

// The project signs with the maintainer's team, whose certificate other machines don't have.
// Sign ad hoc instead: no certificate needed, and the app is not sandboxed. macOS may ask for
// Accessibility and Automation again after a rebuild because the ad-hoc signature changes.
print("Building MacDynamicIsland...")
let build = run("/usr/bin/xcodebuild", [
    "-project", "MacDynamicIsland.xcodeproj",
    "-scheme", "MacDynamicIsland",
    "-configuration", "Debug",
    "-destination", "platform=macOS,arch=\(arch)",
    "-derivedDataPath", derivedData,
    "-quiet",
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=-",
    "DEVELOPMENT_TEAM=",
    "build",
])
guard build == 0 else { fail("Build failed (xcodebuild exit \(build)). Check the output above.") }

// Quit a running copy so the fresh build is the one that shows up.
run("/usr/bin/pkill", ["-x", "MacDynamicIsland"])
guard run("/usr/bin/open", [appPath]) == 0 else { fail("Could not open \(appPath).") }
print("Launched.")
