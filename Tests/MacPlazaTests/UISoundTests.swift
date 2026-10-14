import XCTest
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class UISoundTests: XCTestCase {
    @MainActor func testOriginalShortRecordingsAndBackRouting() throws {
        for cue in PlazaUISounds.Cue.allCases {
            let url = try XCTUnwrap(PlazaUISounds.recordingURL(cue))
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            XCTAssertTrue((0.05...0.15).contains(duration))
            XCTAssertEqual(file.processingFormat.sampleRate, 32000)
        }
        for title in ["Cancel", "Close", "Back to plaza", "Categories", "Return to Desktop · Esc", "Keep Draft & Close"] {
            XCTAssertEqual(PlazaUISounds.cue(for: title), .back)
        }
        XCTAssertEqual(PlazaUISounds.cue(for: "Save Note"), .click)
    }
    @MainActor func testEffectsLeaveMusicAndPreviewUntouchedAndUseIndependentVolume() async throws {
        let music = PlazaAudio(), effects = PlazaUISounds()
        defer { effects.stop(); music.update(enabled: false, allowPreview: false) }
        music.update(enabled: true, volume: 0.000001)
        let before = try XCTUnwrap(music.backgroundPlayback.first)
        effects.configure(enabled: true, volume: 0.000001)
        effects.play(.click); effects.play(.back)
        XCTAssertEqual(effects.playedCount, 2)
        XCTAssertTrue(effects.playback.contains { $0.playing })
        try await Task.sleep(for: .milliseconds(40))
        let after = try XCTUnwrap(music.backgroundPlayback.first)
        XCTAssertEqual(after.track, before.track)
        XCTAssertEqual(after.source, before.source)
        XCTAssertTrue(after.playing)
        XCTAssertGreaterThan(after.time, before.time, "The music playhead keeps moving")
        XCTAssertEqual(music.backgroundPlayback.count, 1, "Effects must not start a music crossfade")
        let url = try XCTUnwrap(PlazaAudio.soundtrackURL(for: .miiverse))
        try music.preview(url, track: .miiverse, volume: 0.000001)
        effects.play(.click)
        XCTAssertEqual(music.previewTrack, .miiverse)
        XCTAssertEqual(music.previewURL, url)
        music.stopPreview(); music.update(enabled: false)
        let count = effects.playedCount
        effects.play(.back)
        XCTAssertEqual(effects.playedCount, count + 1, "Music mute does not mute UI effects")
        effects.configure(enabled: false, volume: 0.18)
        effects.play(.click)
        XCTAssertEqual(effects.playedCount, count + 1)
        XCTAssertFalse(effects.playback.contains { $0.playing })
        effects.configure(enabled: true, volume: 0)
        effects.play(.click)
        XCTAssertEqual(effects.playedCount, count + 1)
    }
    @MainActor func testRapidClicksAreBoundedAndMissingFilesDoNotTrap() {
        let effects = PlazaUISounds()
        defer { effects.stop() }
        effects.configure(enabled: true, volume: 0.000001)
        for _ in 0..<30 { effects.play(.click); effects.play(.back) }
        XCTAssertLessThanOrEqual(effects.playback.count, 6)
        XCTAssertEqual(effects.playedCount, 60)
        let absent = PlazaUISounds(roots: [URL(fileURLWithPath: "/nonexistent/plaza-ui-sounds")])
        absent.play(.click); absent.play(.back)
        XCTAssertEqual(absent.playedCount, 0)
        XCTAssertTrue(absent.playback.isEmpty)
    }
    func testIndependentSettingsAreBackwardCompatibleAndValidated() throws {
        var document = PlazaDocument()
        XCTAssertNil(document.preferences.uiSoundEffects)
        document.preferences.ambientSound = false
        document.preferences.uiSoundEffects = true
        document.preferences.uiSoundVolume = 0.4
        let decoded = try JSONDecoder().decode(PlazaDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(try decoded.validated(), document)
        document.preferences.uiSoundVolume = .nan
        XCTAssertThrowsError(try document.validated())
        document.preferences.uiSoundVolume = 1.01
        XCTAssertThrowsError(try document.validated())
    }
}
