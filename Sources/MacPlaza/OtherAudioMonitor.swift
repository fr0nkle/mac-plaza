import AppKit
import CoreAudio

/// Read activity flags only. This never records audio or opens an input stream.
enum AudioProcessActivity {
    struct ProcessState: Equatable {
        let pid: pid_t
        let output: Bool
        let input: Bool
    }

    static func hasOtherActivity(_ processes: [ProcessState], ownPID: pid_t) -> Bool {
        processes.contains { $0.pid > 0 && $0.pid != ownPID && ($0.output || $0.input) }
    }

    static func snapshot() -> [ProcessState]? {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size <= 4096 * MemoryLayout<AudioObjectID>.size else { return nil }
        guard size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return nil }
        return objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).compactMap { object in
            guard let pid = value(object, kAudioProcessPropertyPID), pid > 0 else { return nil }
            return ProcessState(pid: pid_t(bitPattern: pid),
                                output: value(object, kAudioProcessPropertyIsRunningOutput).map { $0 != 0 } ?? false,
                                input: value(object, kAudioProcessPropertyIsRunningInput).map { $0 != 0 } ?? false)
        }
    }

    private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
    private static func value(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = property(selector), size = UInt32(MemoryLayout<UInt32>.size), result: UInt32 = 0
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return nil }
        return result
    }
}

/// Keep music quiet across short playback gaps and pauses within a call.
struct AudioQuietPeriod {
    static let duration: TimeInterval = 1.5
    private(set) var suppressed = false
    private var quietSince: TimeInterval?

    mutating func update(active: Bool?, now: TimeInterval) -> Bool {
        guard let active else { quietSince = nil; return suppressed }
        if active { suppressed = true; quietSince = nil }
        else if suppressed {
            if let quietSince {
                if now - quietSince >= Self.duration { suppressed = false; self.quietSince = nil }
            } else { quietSince = now }
        }
        return suppressed
    }
}

@MainActor
final class OtherAudioMonitor {
    private var timer: Timer?
    private var sampleTask: Task<Void, Never>?
    private var quiet = AudioQuietPeriod()
    private var lastValue = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        // Polling also handles drivers which don't issue process notifications.
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    private func refresh() {
        guard sampleTask == nil else { return }
        let ownPID = ownPID
        sampleTask = Task { [weak self] in
            let active = await Task.detached(priority: .utility) {
                AudioProcessActivity.snapshot().map { AudioProcessActivity.hasOtherActivity($0, ownPID: ownPID) }
            }.value
            guard !Task.isCancelled, let self else { return }
            self.sampleTask = nil
            let muted = self.quiet.update(active: active, now: ProcessInfo.processInfo.systemUptime)
            guard muted != self.lastValue else { return }
            self.lastValue = muted
            self.onChange(muted)
        }
    }

    deinit { timer?.invalidate(); sampleTask?.cancel() }
}
