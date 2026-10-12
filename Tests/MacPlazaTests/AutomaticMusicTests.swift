import XCTest
import AppKit
@testable import MacPlaza

final class AutomaticMusicTests: XCTestCase {
    func testProcessActivityExcludesOurMusicAndRecognizesPlaybackAndCalls() {
        typealias State = AudioProcessActivity.ProcessState
        XCTAssertFalse(AudioProcessActivity.hasOtherActivity([State(pid: 10, output: true, input: false)], ownPID: 10))
        XCTAssertTrue(AudioProcessActivity.hasOtherActivity([State(pid: 20, output: true, input: false)], ownPID: 10))
        XCTAssertTrue(AudioProcessActivity.hasOtherActivity([State(pid: 20, output: false, input: true)], ownPID: 10))
        XCTAssertFalse(AudioProcessActivity.hasOtherActivity([State(pid: 20, output: false, input: false), State(pid: 0, output: true, input: true)], ownPID: 10))
    }

    func testQuietPeriodPreventsBriefGapsAndUnknownSamplesFromResumingMusic() {
        var quiet = AudioQuietPeriod()
        XCTAssertFalse(quiet.update(active: false, now: 0))
        XCTAssertTrue(quiet.update(active: true, now: 1))
        XCTAssertTrue(quiet.update(active: false, now: 2))
        XCTAssertTrue(quiet.update(active: false, now: 3))
        XCTAssertTrue(quiet.update(active: true, now: 3.2))
        XCTAssertTrue(quiet.update(active: false, now: 4))
        XCTAssertTrue(quiet.update(active: nil, now: 10), "Core Audio errors must not unmute an ongoing call")
        XCTAssertTrue(quiet.update(active: false, now: 11))
        XCTAssertTrue(quiet.update(active: false, now: 12))
        XCTAssertFalse(quiet.update(active: false, now: 12.6))
    }

    @MainActor func testMaximizedWindowBlocksThePlazaButSmallOrOffscreenWindowsDoNot() {
        let usable = CGRect(x: -1920, y: 38, width: 1920, height: 980)
        XCTAssertTrue(FullScreenAudioMonitor.coversMostOfPlaza(window: usable, usableArea: usable))
        XCTAssertTrue(FullScreenAudioMonitor.coversMostOfPlaza(window: usable.insetBy(dx: 12, dy: 12), usableArea: usable))
        XCTAssertFalse(FullScreenAudioMonitor.coversMostOfPlaza(window: CGRect(x: -1900, y: 100, width: 800, height: 600), usableArea: usable))
        XCTAssertFalse(FullScreenAudioMonitor.coversMostOfPlaza(window: CGRect(x: 0, y: 38, width: 1920, height: 980), usableArea: usable))
        XCTAssertFalse(FullScreenAudioMonitor.coversMostOfPlaza(window: usable, usableArea: .zero))
    }

    @MainActor func testIndependentSuppressionReasonsRespectSavedMuteAndStopPreviews() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: root)
        defer { model.audio.update(enabled: false, allowPreview: false); try? FileManager.default.removeItem(at: root) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        model.document.preferences.musicVolume = 0
        model.document.preferences.makerMusicVolume = 0
        model.document.preferences.ambientSound = true
        model.wallpaperEnabled = true
        model.windowVisible = false
        model.updateAudio()
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.otherAudioActive = true
        XCTAssertFalse(model.audio.isBackgroundPlaying)
        model.otherAppCoversPlaza = true
        model.otherAudioActive = false
        XCTAssertFalse(model.audio.isBackgroundPlaying, "Ending audio must not resume behind a blocking window")
        model.otherAppCoversPlaza = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        XCTAssertEqual(model.document.preferences.ambientSound, true, "Automatic muting never changes the saved switch")
        model.document.preferences.ambientSound = false
        model.otherAudioActive = true
        model.otherAudioActive = false
        XCTAssertFalse(model.audio.isBackgroundPlaying, "Saved mute must survive automatic resume")
        model.document.preferences.ambientSound = true
        model.sheet = .characters
        model.desktopMakerVisible = true
        model.updateAudio()
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.otherAudioActive = true
        XCTAssertFalse(model.audio.backgroundPlayback.contains { $0.playing }, "An interruption stops both crossfade players")
        model.otherAudioActive = false
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        model.windowVisible = true
        try model.audio.preview(try XCTUnwrap(PlazaAudio.soundtrackURL), track: .plaza, volume: 0)
        XCTAssertNotNil(model.audio.previewTrack)
        model.otherAudioActive = true
        XCTAssertNil(model.audio.previewTrack)
        model.otherAudioActive = false
        XCTAssertNil(model.audio.previewTrack, "An interrupted audition must not restart by itself")
        XCTAssertTrue(model.audio.isBackgroundPlaying)
        await model.flush()
        try await model.storage.endSession()
    }

    @MainActor func testRealExternalPlayerIsDetectedThenBecomesInactiveAfterStopping() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Silent.wav")
        var wave = PlazaAudio.loop()
        wave.replaceSubrange(44..<wave.count, with: Data(repeating: 0, count: wave.count - 44))
        try wave.write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = ["-v", "0", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        defer { if process.isRunning { process.terminate() }; try? FileManager.default.removeItem(at: root) }
        try process.run()
        let pid = process.processIdentifier
        var detected = false
        for _ in 0..<60 {
            if AudioProcessActivity.snapshot()?.contains(where: { $0.pid == pid && $0.output }) == true { detected = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(detected, "Core Audio must detect an actual external output stream")
        process.terminate()
        var stopped = false
        for _ in 0..<60 {
            if AudioProcessActivity.snapshot()?.contains(where: { $0.pid == pid && ($0.output || $0.input) }) == false { stopped = true; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(stopped)
    }
}
