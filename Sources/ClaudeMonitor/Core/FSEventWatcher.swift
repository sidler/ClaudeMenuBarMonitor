import CoreServices
import Foundation

/// Beobachtet Ordnerbäume über FSEvents — inklusive Änderungen an Dateiinhalten,
/// die ein reiner Verzeichniswächter nicht meldet.
final class FSEventWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "local.ClaudeMonitor.fsevents", qos: .utility)
    private let onChange: @Sendable () -> Void

    init?(paths: [String], latency: TimeInterval = 0.25, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        guard !paths.isEmpty else { return nil }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit { stop() }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func fire() { onChange() }
}

private let fsEventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue().fire()
}
