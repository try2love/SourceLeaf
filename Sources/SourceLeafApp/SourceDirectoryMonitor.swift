import Darwin
import Foundation

final class SourceDirectoryMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SourceLeaf.SourceDirectoryMonitor", qos: .utility)
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingCallback: DispatchWorkItem?

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    func watch(fileURL: URL) {
        stop()
        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_EVTONLY) } ?? -1
        }
        guard descriptor >= 0 else { return }
        let next = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        next.setEventHandler { [weak self] in
            guard let self else { return }
            pendingCallback?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            pendingCallback = work
            queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
        }
        next.setCancelHandler { close(descriptor) }
        source = next
        next.resume()
    }

    func stop() {
        pendingCallback?.cancel()
        pendingCallback = nil
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
