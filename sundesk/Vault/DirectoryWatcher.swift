import CoreServices
import Foundation

/// FSEvents でディレクトリ以下の変更を監視する。
/// Finder や他のエディタ（Obsidian など）での編集をアプリに反映するために使う。
nonisolated final class DirectoryWatcher: @unchecked Sendable {
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue(label: "sundesk.directory-watcher")
    private var stream: FSEventStreamRef?

    init(url: URL, latency: TimeInterval = 0.4, handler: @escaping @Sendable () -> Void) {
        self.handler = handler

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
