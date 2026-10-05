import Foundation
import AppKit
import UniformTypeIdentifiers

/// What you dropped on the island, ready for the tab that takes it: files and folders, text saved as a file,
/// and links (PluginEvent.drop)
struct IslandDrop: Equatable {
    var paths: [String] = []
    var urls: [String] = []

    var isEmpty: Bool { paths.isEmpty && urls.isEmpty }

    /// The kinds a drop can bring
    static let types: [UTType] = [.fileURL, .url, .item, .data]

    /// Reads what a SwiftUI drop brought. Text becomes a `.txt` file in `textFolder`, kept until the tab's owner
    /// removes it
    static func read(_ providers: [NSItemProvider], savingTextIn textFolder: URL) async -> IslandDrop {
        var drop = IslandDrop()
        for provider in providers {
            if let file = await provider.extractFileURL() {
                drop.paths.append(file.path)
            } else if let url = await provider.extractURL() {
                drop.urls.append(url.absoluteString)
            } else if let text = await provider.extractText(), let file = save(text, in: textFolder) {
                drop.paths.append(file.path)
            }
        }
        return drop
    }

    /// The files the drag monitor saw released over the island (when SwiftUI's drop doesn't fire)
    static func files(_ urls: [URL]) -> IslandDrop {
        IslandDrop(paths: urls.filter(\.isFileURL).map(\.path), urls: urls.filter { !$0.isFileURL }.map(\.absoluteString))
    }

    private static func save(_ text: String, in folder: URL) -> URL? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        var file = folder.appendingPathComponent("Note \(stamp).txt")
        var counter = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("Note \(stamp) \(counter).txt")
            counter += 1
        }
        return (try? text.write(to: file, atomically: true, encoding: .utf8)) == nil ? nil : file
    }
}
