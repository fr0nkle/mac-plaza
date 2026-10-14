import AppKit
import CoreAudio
import OSLog

/// Read activity flags only. This never records audio or opens an input stream.
enum AudioProcessActivity {
    struct ProcessState: Equatable {
        let pid: pid_t
        let output: Bool
        let input: Bool
        var bundleID: String? = nil
    }

    static func hasOtherActivity(_ processes: [ProcessState], ownPID: pid_t) -> Bool {
        processes.contains {
            // CoreSpeech keeps silent input/output streams open for background
            // speech detection. Those streams are not app playback or a call.
            isOtherProcess($0, ownPID: ownPID) && ($0.input || ($0.output && !isNotificationOutput($0)))
        }
    }

    static func isOtherProcess(_ process: ProcessState, ownPID: pid_t) -> Bool {
        process.pid > 0 && process.pid != ownPID && process.bundleID != "com.apple.CoreSpeech"
    }

    static func isNotificationOutput(_ process: ProcessState) -> Bool {
        // Core Audio reports the system sound service as "systemsoundserverd"
        // (verified with a silent AudioServices system sound), not an app ID.
        process.bundleID == "systemsoundserverd" || process.bundleID == "com.apple.notificationcenterui"
    }

    static func snapshot() -> [ProcessState]? {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size <= 4096 * MemoryLayout<AudioObjectID>.size else { return nil }
        guard size > 0 else { return [] }
        let capacity = size
        guard size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = objects.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr, size <= capacity,
              size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { return nil }
        return processStates(Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)),
                             read: value, identity: bundleID)
    }

    static func processStates(_ objects: [AudioObjectID],
                              read: (AudioObjectID, AudioObjectPropertySelector) -> UInt32?,
                              identity: (AudioObjectID) -> String?) -> [ProcessState]? {
        var states: [ProcessState] = []
        for object in objects {
            // A process can disappear between the list and its property reads.
            // Unknown flags must not count as a quiet sample after a call ends.
            guard let pid = read(object, kAudioProcessPropertyPID),
                  let output = read(object, kAudioProcessPropertyIsRunningOutput),
                  let input = read(object, kAudioProcessPropertyIsRunningInput) else { return nil }
            guard pid_t(bitPattern: pid) > 0 else { continue }
            states.append(ProcessState(pid: pid_t(bitPattern: pid), output: output != 0,
                                       input: input != 0, bundleID: identity(object)))
        }
        return states
    }

    private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
    private static func bundleID(_ object: AudioObjectID) -> String? {
        var address = property(kAudioProcessPropertyBundleID)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr,
              let result else { return nil }
        // Core Audio transfers ownership of this property to the caller.
        return result.takeRetainedValue() as String
    }
    private static func value(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = property(selector), size = UInt32(MemoryLayout<UInt32>.size), result: UInt32 = 0
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr,
              size == MemoryLayout<UInt32>.size else { return nil }
        return result
    }
}

/// Short app chimes should mix over the music. Require continuous output from
/// the same process before yielding; microphone activity still yields at once.
struct SustainedAudioActivity {
    static let outputDelay: TimeInterval = 2
    private struct Output {
        var bundleID: String?
        var began: TimeInterval
        var confirmed: Bool
    }
    private var outputs: [pid_t: Output] = [:]

    mutating func update(processes: [AudioProcessActivity.ProcessState]?, ownPID: pid_t,
                         now: TimeInterval) -> Bool? {
        guard let processes else {
            // Unknown samples cannot prove a chime became sustained playback,
            // or forget output that already caused a genuine interruption.
            outputs = outputs.filter { $0.value.confirmed }
            return nil
        }
        let other = processes.filter { AudioProcessActivity.isOtherProcess($0, ownPID: ownPID) }
        let inputs = Set(other.filter(\.input).map(\.pid))
        let playing = other.filter { $0.output && !AudioProcessActivity.isNotificationOutput($0) }
        let pids = Set(playing.map(\.pid))
        outputs = outputs.filter { pids.contains($0.key) }
        for process in playing {
            var output = outputs[process.pid].flatMap { previous in
                // A temporarily unavailable bundle-ID property is not evidence
                // that a confirmed stream belongs to a different process.
                if let oldID = previous.bundleID, let newID = process.bundleID, oldID != newID { return nil }
                return previous
            }
                ?? Output(bundleID: process.bundleID, began: now, confirmed: false)
            if output.bundleID == nil { output.bundleID = process.bundleID }
            output.confirmed = output.confirmed || inputs.contains(process.pid) || now - output.began >= Self.outputDelay
            outputs[process.pid] = output
        }
        return !inputs.isEmpty || outputs.values.contains { $0.confirmed }
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
    private var activity = SustainedAudioActivity()
    private var lastValue = false
    private var lastSampleKnown: Bool?
    private let logger = Logger(subsystem: "local.macplaza.audio", category: "ProcessMonitor")
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
            let processes = await Task.detached(priority: .utility) { AudioProcessActivity.snapshot() }.value
            guard !Task.isCancelled, let self else { return }
            self.sampleTask = nil
            let now = ProcessInfo.processInfo.systemUptime
            let active = self.activity.update(processes: processes, ownPID: ownPID, now: now)
            let known = active != nil
            if known != self.lastSampleKnown {
                self.lastSampleKnown = known
                self.logger.notice("Audio process sample available: \(known, privacy: .public)")
            }
            let muted = self.quiet.update(active: active, now: now)
            guard muted != self.lastValue else { return }
            self.lastValue = muted
            self.logger.notice("Other-app audio suppression: \(muted, privacy: .public)")
            self.onChange(muted)
        }
    }

    deinit { timer?.invalidate(); sampleTask?.cancel() }
}
