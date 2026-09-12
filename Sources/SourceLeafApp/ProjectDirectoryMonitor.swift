import Foundation

/// Watches directory membership independently of the current editor file.
@MainActor
final class ProjectDirectoryMonitor {
    private var root: URL?
    private var monitors: [URL: SourceDirectoryMonitor] = [:]
    private var refreshTask: Task<Void, Never>?
    private let onChange: @MainActor () -> Void

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func watch(root: URL) {
        stop()
        self.root = root
        synchronizeDirectories()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        for monitor in monitors.values { monitor.stop() }
        monitors.removeAll()
        root = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard let self, root != nil else { return }
            synchronizeDirectories()
            onChange()
        }
    }

    private func synchronizeDirectories() {
        guard let root else { return }
        var directories: Set<URL> = [root]
        let excluded: Set<String> = [".git", ".build", "build", "DerivedData", "临时文件"]
        if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in entries {
                if excluded.contains(url.lastPathComponent) {
                    entries.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true { directories.insert(url) }
            }
        }
        for url in Set(monitors.keys).subtracting(directories) {
            monitors.removeValue(forKey: url)?.stop()
        }
        for url in directories.subtracting(monitors.keys) {
            let monitor = SourceDirectoryMonitor { [weak self] in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
            monitors[url] = monitor
            monitor.watch(fileURL: url.appendingPathComponent(".directory-watch"))
        }
    }
}
