import XCTest
import AVFoundation
@testable import MacPlaza

final class CustomMusicTests: XCTestCase {
    @MainActor func testChoosingMusicDoesNotApplyUntilConfirmedAndCancelPreservesSavedTrack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Listen first.wav")
        let invalid = root.appendingPathComponent("Invalid.wav")
        try PlazaAudio.loop().write(to: source)
        try Data("Not audio".utf8).write(to: invalid)
        let library = PlazaMusicLibrary(directory: root.appendingPathComponent("Music"))
        try library.install(source, for: .plaza)
        let saved = library.url(for: .plaza)
        let manifest = library.directory.appendingPathComponent("music.json")
        let original = try Data(contentsOf: manifest)
        try library.stage(source, for: .plaza)
        try library.stage(source, for: .maker)
        try library.stage(source, for: .friends)
        try library.stage(source, for: .settings)
        try library.stage(source, for: .writing)
        let pendingFriends = try XCTUnwrap(library.previewURL(for: .friends))
        let pending = try XCTUnwrap(library.previewURL(for: .maker))
        XCTAssertEqual(try Data(contentsOf: manifest), original)
        XCTAssertEqual(library.url(for: .plaza), saved)
        XCTAssertNil(library.url(for: .maker))
        XCTAssertThrowsError(try library.stage(invalid, for: .maker))
        XCTAssertEqual(library.previewURL(for: .maker), pending)
        try FileManager.default.removeItem(at: source)
        library.applySelection(for: .maker)
        XCTAssertEqual(library.title(for: .maker), "Listen first.wav")
        XCTAssertNotNil(library.url(for: .maker))
        XCTAssertNil(library.selections[PlazaAudio.Track.maker.rawValue])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        library.discardSelections()
        XCTAssertTrue(library.selections.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingFriends.path))
        XCTAssertEqual(library.url(for: .plaza), saved)
        XCTAssertEqual(PlazaMusicLibrary(directory: library.directory).url(for: .maker), library.url(for: .maker))
    }
    @MainActor func testPreviewPausesBackgroundSwitchesTracksAndRespectsPlaybackEligibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Preview.wav")
        try PlazaAudio.loop().write(to: source)
        let audio = PlazaAudio()
        defer { audio.update(enabled: false, allowPreview: false) }
        audio.update(enabled: true, volume: 0, customURL: source)
        XCTAssertTrue(audio.isBackgroundPlaying)
        try audio.preview(source, track: .plaza, volume: 0)
        XCTAssertEqual(audio.previewTrack, .plaza)
        XCTAssertFalse(audio.isBackgroundPlaying)
        try audio.preview(source, track: .maker, volume: 0)
        XCTAssertEqual(audio.previewTrack, .maker)
        XCTAssertFalse(audio.isBackgroundPlaying)
        // A background update must not interrupt the explicit preview.
        audio.update(enabled: true, volume: 0, customURL: source)
        XCTAssertEqual(audio.previewTrack, .maker)
        XCTAssertFalse(audio.isBackgroundPlaying)
        audio.stopPreview()
        XCTAssertNil(audio.previewTrack)
        XCTAssertTrue(audio.isBackgroundPlaying)
        try audio.preview(source, track: .plaza, volume: 0)
        // Hiding/sleep/safe mode must stop explicit Settings previews.
        audio.update(enabled: false, allowPreview: false)
        XCTAssertNil(audio.previewTrack)
        XCTAssertFalse(audio.isBackgroundPlaying)
    }
    @MainActor func testFinishedPreviewClearsStopButtonAutomatically() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Short.wav")
        var wave = Data(PlazaAudio.loop().prefix(44 + 2205 * 2))
        for (offset, size) in [(4, wave.count - 8), (40, wave.count - 44)] {
            var size = UInt32(size).littleEndian
            withUnsafeBytes(of: &size) { wave.replaceSubrange(offset..<offset+4, with: $0) }
        }
        try wave.write(to: source)
        let audio = PlazaAudio()
        audio.update(enabled: false)
        try audio.preview(source, track: .plaza, volume: 0)
        for _ in 0..<40 {
            if audio.previewTrack == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(audio.previewTrack)
        XCTAssertFalse(audio.isBackgroundPlaying)
    }
    @MainActor func testImportedTracksAreIndependentPersistentCopiesAndDefaultsCanBeRestored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("My quiet music.wav")
        try PlazaAudio.loop().write(to: source)
        let library = PlazaMusicLibrary(directory: root.appendingPathComponent("Music"))
        var updates = 0
        library.onChange = { updates += 1 }
        try library.install(source, for: .plaza)
        try library.install(source, for: .maker)
        try library.install(source, for: .friends)
        let plaza = try XCTUnwrap(library.url(for: .plaza))
        let maker = try XCTUnwrap(library.url(for: .maker))
        let friends = try XCTUnwrap(library.url(for: .friends))
        XCTAssertNotEqual(friends, maker)
        XCTAssertNotEqual(plaza, maker)
        XCTAssertNotEqual(plaza, source)
        try FileManager.default.removeItem(at: source)
        let reloaded = PlazaMusicLibrary(directory: library.directory)
        XCTAssertEqual(reloaded.url(for: .plaza), plaza)
        XCTAssertEqual(reloaded.url(for: .friends), friends)
        XCTAssertEqual(reloaded.title(for: .maker), "My quiet music.wav")
        XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: plaza).duration, 1)
        library.restoreDefault(for: .maker)
        XCTAssertNil(library.url(for: .maker))
        XCTAssertFalse(FileManager.default.fileExists(atPath: maker.path))
        XCTAssertEqual(library.url(for: .plaza), plaza)
        XCTAssertEqual(library.url(for: .friends), friends)
        XCTAssertEqual(updates, 4)
        XCTAssertNil(PlazaMusicLibrary(directory: library.directory).url(for: .maker))
    }
    @MainActor func testUnplayableImportsPreserveWorkingTrackAndLeaveNoCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = root.appendingPathComponent("valid.wav"), bad = root.appendingPathComponent("broken.mp3")
        try PlazaAudio.loop().write(to: valid)
        try Data("This is not audio".utf8).write(to: bad)
        let library = PlazaMusicLibrary(directory: root.appendingPathComponent("Music"))
        try library.install(valid, for: .plaza)
        let installed = library.url(for: .plaza)
        XCTAssertThrowsError(try library.install(bad, for: .plaza))
        XCTAssertThrowsError(try library.install(root, for: .plaza))
        XCTAssertEqual(library.url(for: .plaza), installed)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.directory.path).count, 2)
        try Data().write(to: bad)
        XCTAssertThrowsError(try library.install(bad, for: .maker))
        let large = root.appendingPathComponent("large.wav")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(PlazaMusicLibrary.maximumFileSize + 1)); try handle.close()
        XCTAssertThrowsError(try library.install(large, for: .maker))
    }
    @MainActor func testMissingOrInvalidSavedReferencesUseDefaultMusic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = [PlazaAudio.Track.plaza.rawValue: PlazaMusicLibrary.Recording(file: "../outside.wav", name: "Outside"),
                       PlazaAudio.Track.maker.rawValue: PlazaMusicLibrary.Recording(file: UUID().uuidString + ".wav", name: "Missing")]
        try JSONEncoder().encode(entries).write(to: root.appendingPathComponent("music.json"))
        let library = PlazaMusicLibrary(directory: root)
        XCTAssertNil(library.recordings[PlazaAudio.Track.plaza.rawValue])
        XCTAssertNil(library.url(for: .maker))
        XCTAssertEqual(library.title(for: .maker), "Mii Maker")
    }
}
