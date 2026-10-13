import XCTest
import AppKit
@testable import MacPlaza

final class AudioTransitionTests: XCTestCase {
    // Silent PCM lets these checks exercise real player volumes without sound.
    @MainActor private func silentTrack(in root: URL) throws -> URL {
        var wave = PlazaAudio.loop()
        wave.replaceSubrange(44..<wave.count, with: Data(repeating: 0, count: wave.count - 44))
        let url = root.appendingPathComponent(UUID().uuidString + ".wav")
        try wave.write(to: url)
        return url
    }

    @MainActor func testTrackChangesCrossfadeBothDirectionsAndRapidReversalKeepsPlaybackPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plaza = try silentTrack(in: root), maker = try silentTrack(in: root)
        let audio = PlazaAudio()
        defer { audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        audio.update(enabled: true, volume: 0.12, track: .plaza, customURL: plaza)
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(try XCTUnwrap(audio.backgroundPlayback.first).volume, 0.12, accuracy: 0.01)
        let plazaTime = try XCTUnwrap(audio.backgroundPlayback.first).time
        audio.update(enabled: true, volume: 0.10, track: .maker, customURL: maker)
        // Duplicate updates from the two surfaces must not truncate the fade.
        audio.update(enabled: true, volume: 0.10, track: .maker, customURL: maker)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(audio.backgroundPlayback.count, 2)
        XCTAssertTrue(audio.backgroundPlayback.allSatisfy(\.playing))
        let outgoing = try XCTUnwrap(audio.backgroundPlayback.first { $0.track == .plaza })
        let incoming = try XCTUnwrap(audio.backgroundPlayback.first { $0.track == .maker })
        XCTAssertGreaterThan(outgoing.time, plazaTime)
        XCTAssertGreaterThan(incoming.time, 0)
        // AVAudioPlayer.volume reports the target immediately; its audio
        // thread performs the native ramp while both players keep advancing.
        XCTAssertEqual(outgoing.volume, 0)
        XCTAssertEqual(incoming.volume, 0.10, accuracy: 0.001)

        audio.update(enabled: true, volume: 0.12, track: .plaza, customURL: plaza)
        XCTAssertGreaterThan(try XCTUnwrap(audio.backgroundPlayback.first).time, plazaTime,
                             "Reversing a fade must reuse the ongoing plaza player")
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(audio.backgroundPlayback.count, 1)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .plaza)
        XCTAssertEqual(try XCTUnwrap(audio.backgroundPlayback.first).volume, 0.12, accuracy: 0.01)

        audio.update(enabled: true, volume: 0.10, track: .maker, customURL: maker)
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(audio.backgroundPlayback.count, 1)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .maker)
        audio.update(enabled: true, volume: 0.12, track: .plaza, customURL: plaza)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(audio.backgroundPlayback.count, 2)
        XCTAssertTrue(audio.backgroundPlayback.allSatisfy(\.playing))
        XCTAssertGreaterThan(try XCTUnwrap(audio.backgroundPlayback.first { $0.track == .maker }).time, 1)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(audio.backgroundPlayback.count, 1)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .plaza)
    }

    @MainActor func testMuteAndPreviewStopEverySideOfAnActiveCrossfade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try silentTrack(in: root)
        let audio = PlazaAudio()
        defer { audio.update(enabled: false, allowPreview: false); try? FileManager.default.removeItem(at: root) }
        audio.update(enabled: true, volume: 0, customURL: source)
        audio.update(enabled: true, volume: 0, track: .maker, customURL: source)
        XCTAssertEqual(audio.backgroundPlayback.filter(\.playing).count, 2)
        try audio.preview(source, track: .plaza, volume: 0)
        XCTAssertFalse(audio.backgroundPlayback.contains { $0.playing })
        audio.stopPreview()
        XCTAssertEqual(audio.backgroundPlayback.filter(\.playing).count, 1)
        audio.update(enabled: true, volume: 0, track: .plaza, customURL: source)
        XCTAssertEqual(audio.backgroundPlayback.filter(\.playing).count, 2)
        audio.update(enabled: false, allowPreview: false)
        XCTAssertFalse(audio.backgroundPlayback.contains { $0.playing })
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertFalse(audio.isBackgroundPlaying, "Old fade tasks must never restart muted audio")
        audio.update(enabled: true, volume: 0, track: .maker, customURL: source)
        XCTAssertTrue(audio.isBackgroundPlaying)
        XCTAssertEqual(audio.backgroundPlayback.filter(\.playing).count, 1)
    }

    @MainActor func testFriendsMusicCrossfadesToPlazaAndMakerWithIndependentVolumes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try silentTrack(in: root)
        let audio = PlazaAudio()
        defer { audio.update(enabled: false); try? FileManager.default.removeItem(at: root) }
        audio.update(enabled: true, volume: 0.12, track: .plaza, customURL: source)
        audio.update(enabled: true, volume: 0.07, track: .friends, customURL: source)
        XCTAssertEqual(audio.backgroundPlayback.filter(\.playing).count, 2)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .friends)
        XCTAssertEqual(try XCTUnwrap(audio.backgroundPlayback.first).volume, 0.07, accuracy: 0.001)
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(audio.backgroundPlayback.count, 1)
        audio.update(enabled: true, volume: 0.10, track: .maker, customURL: source)
        XCTAssertEqual(Set(audio.backgroundPlayback.map(\.track)), Set([.maker, .friends]))
        XCTAssertTrue(audio.backgroundPlayback.allSatisfy(\.playing))
        audio.update(enabled: true, volume: 0.07, track: .friends, customURL: source)
        XCTAssertGreaterThan(try XCTUnwrap(audio.backgroundPlayback.first).time, 1,
                             "Quickly returning to Friends must retain its playback position")
        audio.update(enabled: true, volume: 0.12, track: .plaza, customURL: source)
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(audio.backgroundPlayback.count, 1)
        XCTAssertEqual(audio.backgroundPlayback.first?.track, .plaza)
    }

    @MainActor func testFullScreenPolicyExcludesOwnMakerAndOrdinaryMaximizedWindows() {
        XCTAssertTrue(FullScreenAudioMonitor.shouldMute(frontmostPID: 42, ownPID: 7, coversDisplay: true))
        XCTAssertFalse(FullScreenAudioMonitor.shouldMute(frontmostPID: 7, ownPID: 7, coversDisplay: true))
        XCTAssertFalse(FullScreenAudioMonitor.shouldMute(frontmostPID: 42, ownPID: 7, coversDisplay: false))
        XCTAssertFalse(FullScreenAudioMonitor.shouldMute(frontmostPID: nil, ownPID: 7, coversDisplay: true))
        for display in [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: -1080, width: 1920, height: 1080)] {
            XCTAssertTrue(FullScreenAudioMonitor.coversDisplay(window: display, display: display))
            let notched = CGRect(x: display.minX, y: display.minY + 38, width: display.width, height: display.height - 38)
            XCTAssertTrue(FullScreenAudioMonitor.coversDisplay(window: notched, display: display, topInset: 38))
            let maximized = CGRect(x: display.minX, y: display.minY + 38, width: display.width, height: display.height - 110)
            XCTAssertFalse(FullScreenAudioMonitor.coversDisplay(window: maximized, display: display, topInset: 38))
            XCTAssertFalse(FullScreenAudioMonitor.coversDisplay(window: display.insetBy(dx: 100, dy: 100), display: display))
        }
    }
}
