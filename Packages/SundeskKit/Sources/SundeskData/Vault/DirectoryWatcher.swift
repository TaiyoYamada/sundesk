//
//  DirectoryWatcher.swift
//  SundeskData
//
//  Created by 山田大陽 on 2026/09/29.
//

import CoreServices
import Foundation

/// FSEvents でフォルダ以下の変更を見張る。Finder や他のエディタでの変更を拾うため。
final class DirectoryWatcher: Sendable {
    // 初期化と破棄のときにしか触らないので、スレッドをまたいでも競合しない
    nonisolated(unsafe) private let stream: FSEventStreamRef?
    nonisolated(unsafe) private let context: UnsafeMutablePointer<FSEventStreamContext>
    private let queue = DispatchQueue(label: "com.taiyou.sundesk.directory-watcher")

    init(url: URL, latency: TimeInterval = 0.3, handler: @escaping @Sendable () -> Void) {
        let box = Unmanaged.passRetained(HandlerBox(handler))
        context = .allocate(capacity: 1)
        context.initialize(
            to: FSEventStreamContext(
                version: 0,
                info: box.toOpaque(),
                retain: nil,
                release: { info in info.map { Unmanaged<HandlerBox>.fromOpaque($0).release() } },
                copyDescription: nil
            )
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue().handler()
        }
        stream = FSEventStreamCreate(
            nil, callback, context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        } else if let info = context.pointee.info {
            Unmanaged<HandlerBox>.fromOpaque(info).release()
        }
        context.deinitialize(count: 1)
        context.deallocate()
    }

    private final class HandlerBox: Sendable {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }
}
