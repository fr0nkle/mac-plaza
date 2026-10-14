import XCTest
import AppKit
import AVFoundation
import PlazaCore
@testable import MacPlaza

final class NoteWritingTests: XCTestCase {
    @MainActor
    func testPostLinksOpenMiiverseWithPrivateContentPreserved() async throws {
        _ = NSApplication.shared
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=PlazaModel(directory:directory)
        defer { model.scene.setMoving(false);model.audio.update(enabled:false);try? FileManager.default.removeItem(at:directory) }
        for _ in 0..<200 where !model.loaded {try await Task.sleep(for:.milliseconds(10))}
        let avatar=model.document.primaryAvatar
        var note=LocalNote(authorID:avatar.id,author:avatar.name,appID:nil,text:"Private Miiverse post")
        note.shared=false
        XCTAssertTrue(model.mutate {$0.notes=[note]})
        model.openMiiverse(note:note.id)
        XCTAssertEqual(model.sheet?.id,"miiverse");XCTAssertTrue(model.sheet?.isFloatingMenu == true)
        XCTAssertEqual(model.selectedNoteID,note.id);XCTAssertEqual(model.musicTrack,.miiverse)
        XCTAssertEqual(model.document.notes.first?.shared,false)
        XCTAssertTrue(model.document.notes.first?.read == true)
        XCTAssertEqual(model.miiverseCatalog.filtered(section:"mine",query:"",sort:.newest).map(\.id),[note.id])
        model.openMiiverse();XCTAssertNil(model.selectedNoteID)
        await model.flush();try await model.storage.endSession()
    }
    @MainActor
    func testStartupCleansAnOfflineSaveWithoutChangingOtherPlazaData() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var document = PlazaDocument()
        let avatar = document.primaryAvatar
        var old = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Expired private note")
        old.shared = false; old.created = Date().addingTimeInterval(-8 * 86400)
        let fresh = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Keep this")
        document.notes = [old, fresh]
        var draft = NoteDraft(); draft.text = "Keep my draft"; document.draft = draft
        document.apps = [AppIsland(label: "Game", bundleID: "example.game")]
        let storage = DocumentStorage(url: directory.appendingPathComponent("plaza.json"))
        try await storage.save(document, revision: 1)
        let model = PlazaModel(directory: directory)
        defer { model.scene.setMoving(false); model.audio.update(enabled: false); try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        var expected = document; expected.notes = [fresh]
        XCTAssertEqual(model.document, expected)
        await model.flush()
        let stored = try await model.storage.load()
        XCTAssertEqual(stored, expected)
        try await model.storage.endSession()
    }
    @MainActor
    func testExpiryPersistsAndCannotBeUndoneIntoTheJournal() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer { model.scene.setMoving(false); model.audio.update(enabled: false); try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let avatar = model.document.primaryAvatar
        var note = LocalNote(authorID: avatar.id, author: avatar.name, appID: nil, text: "Expires")
        note.created = Date().addingTimeInterval(-NoteRetention.duration + 30)
        XCTAssertTrue(model.mutate { $0.notes = [note] })
        let before = model.document
        model.expireNotes(now: Date().addingTimeInterval(31))
        var expected = before; expected.notes = []
        XCTAssertEqual(model.document, expected)
        XCTAssertNil(model.journalNote(note.id))
        var expired = note; expired.created = Date().addingTimeInterval(-NoteRetention.duration - 1)
        XCTAssertTrue(model.mutate { $0.notes.insert(expired, at: 0) })
        XCTAssertTrue(model.document.notes.isEmpty)
        await model.flush()
        let stored = try await model.storage.load()
        XCTAssertEqual(stored, expected)
        try await model.storage.endSession()
    }

    @MainActor
    func testPublicPostsUsePrimaryWhilePrivatePostsKeepTheirSelectedMii() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer {
            model.scene.setMoving(false); model.audio.update(enabled: false)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let secondary = try XCTUnwrap(model.document.avatars.last)
        var publicNote = LocalNote(authorID: secondary.id, author: secondary.name, appID: nil, text: "Public")
        publicNote.created = Date().addingTimeInterval(-10)
        var privateNote = publicNote; privateNote.id = UUID(); privateNote.shared = false; privateNote.created = Date().addingTimeInterval(-20)
        XCTAssertTrue(model.mutate { $0.notes = [publicNote, privateNote] })
        let original = model.document
        XCTAssertEqual(model.noteAvatar(publicNote).id, model.document.primaryAvatar.id)
        XCTAssertEqual(model.noteAvatar(privateNote).id, secondary.id)
        model.bubbleSelections = [0, 1, 2]
        XCTAssertEqual(model.journalPost().speaker.id, model.document.primaryAvatar.id, "The speech post attaches to the primary Mii without changing stored authors")
        XCTAssertEqual(model.document, original)
        await model.flush(); try await model.storage.endSession()
    }
    @MainActor
    func testMiiverseHasItsOwnOfflineAdjustableMusicAndReturnsFromWriting() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer {
            model.scene.setMoving(false); model.audio.update(enabled: false)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        let original = model.document
        let recording = try AVAudioPlayer(contentsOf: XCTUnwrap(PlazaAudio.soundtrackURL(for: .miiverse)))
        XCTAssertGreaterThan(recording.duration, 100)
        XCTAssertLessThan(recording.duration, 115)
        model.sheet = .miiverse
        XCTAssertEqual(model.musicTrack, .miiverse)
        XCTAssertEqual(model.musicVolume, 0.10)
        XCTAssertTrue(model.audio.backgroundPlayback.contains { $0.track == .miiverse && $0.playing })
        model.beginWritingNote()
        XCTAssertEqual(model.musicTrack, .writing)
        model.endWritingNote()
        XCTAssertEqual(model.musicTrack, .miiverse)
        model.sheet = nil
        XCTAssertEqual(model.musicTrack, .plaza)
        XCTAssertEqual(model.document, original, "Browsing and soundtrack transitions do not alter a save")
        XCTAssertTrue(model.mutate { $0.preferences.miiverseMusicVolume = 0.21 })
        model.sheet = .miiverse
        XCTAssertEqual(model.musicVolume, 0.21)
        model.sheet = nil
        XCTAssertEqual(model.musicVolume, original.preferences.musicVolume ?? 0.12, "Miiverse volume is independent of the plaza")
        let decoded = try JSONDecoder().decode(PlazaDocument.self, from: JSONEncoder().encode(model.document))
        XCTAssertEqual(decoded.preferences.miiverseMusicVolume, 0.21)
        var invalid = decoded; invalid.preferences.miiverseMusicVolume = .infinity
        XCTAssertThrowsError(try invalid.validated())
        await model.flush(); try await model.storage.endSession()
    }
    @MainActor
    func testDraftPersistsEditsAndClearsWhenContentIsErased() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer {
            model.scene.setMoving(false); model.audio.update(enabled: false)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let original = model.document
        var draft = NoteDraft()
        draft.authorID = model.document.primaryAvatar.id
        model.storeDraft(draft)
        XCTAssertEqual(model.document, original, "Empty composer metadata does not alter the save")
        draft.text = "A draft to keep"
        model.storeDraft(draft)
        await model.flush()
        XCTAssertEqual(model.document.draft?.text, draft.text)
        draft.text = "  \n"
        model.storeDraft(draft)
        XCTAssertNil(model.document.draft, "Erasing a draft clears it")
        await model.flush(); try await model.storage.endSession()
    }
    @MainActor
    func testComposerAndNestedReplyUseOfflineSoundtrackAndReturnToPlazaWithoutSavingChanges() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = PlazaModel(directory: directory)
        defer {
            model.scene.setMoving(false); model.audio.update(enabled: false)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.loaded)
        let original = model.document
        let url = try XCTUnwrap(PlazaAudio.soundtrackURL(for: .writing))
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 140)
        XCTAssertLessThan(player.duration, 160)
        model.sheet = .compose(nil)
        XCTAssertEqual(model.musicTrack, .writing)
        XCTAssertTrue(model.audio.backgroundPlayback.contains { $0.track == .writing && $0.playing })
        model.beginWritingNote()
        model.sheet = .miiverse
        XCTAssertEqual(model.musicTrack, .writing, "Nested reply/edit sheets keep writing music")
        model.endWritingNote()
        XCTAssertEqual(model.musicTrack, .miiverse)
        XCTAssertTrue(model.audio.backgroundPlayback.contains { $0.track == .miiverse && $0.playing })
        XCTAssertEqual(model.document, original)
        await model.flush(); try await model.storage.endSession()
    }
}
