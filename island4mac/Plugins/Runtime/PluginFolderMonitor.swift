import Foundation

/// Watches the plugins folder and each plugin's folder, and reports (once things settle) when anything in them
/// was added, removed or replaced: an install from Settings, or `island-plugin dev` swapping in a new build
@MainActor
final class PluginFolderMonitor {
    private let folder: URL
    private let onChange: () -> Void
    private let delay: TimeInterval
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pending: DispatchWorkItem?

    init(folder: URL, delay: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        self.folder = folder
        self.delay = delay
        self.onChange = onChange
    }

    func start() {
        rearm()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }

    /// Watches the folder and the folders in it now; called again after each change, since folders come and go
    private func rearm() {
        let subfolders = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        let wanted = Set([folder.path] + subfolders.map(\.path))
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in wanted where sources[path] == nil {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main
            )
            source.setEventHandler { MainActor.assumeIsolated { [weak self] in self?.changed() } }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources[path] = source
        }
    }

    /// Several events arrive for one install; report once they stop
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rearm()
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
