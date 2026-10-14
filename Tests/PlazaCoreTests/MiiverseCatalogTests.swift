import XCTest
@testable import PlazaCore

final class MiiverseCatalogTests: XCTestCase {
    func testAllNotesPreservesUnknownAppTopicsAndDeduplicatesOwnSyncedNotes() {
        let account = UUID().uuidString, friend = UUID().uuidString
        let author = Avatar(name: "You"), visitor = Avatar(name: "Friend")
        var game = AppIsland(label: "Bloons TD6", bundleID: "steam.launcher"); game.steamAppID = 960090
        let renamed = AppIsland(label: "My browser", bundleID: "com.example.browser")
        var own = LocalNote(authorID: author.id, author: author.name, appID: game.id, text: "My game note")
        own.created = Date(timeIntervalSince1970: 10)
        var privateNote = LocalNote(authorID: author.id, author: author.name, appID: nil, text: "Private reminder")
        privateNote.shared = false
        var synced = SharedJournalNote(note: own, author: author, app: game)
        synced.sourceID = own.id; synced.id = UUID(); synced.ownerID = account; synced.likeCount = 8
        let missing = AppIsland(label: "Uninstalled game", bundleID: "com.example.missing")
        var other = SharedJournalNote(note: LocalNote(authorID: visitor.id, author: visitor.name, appID: missing.id, text: "Friend’s drawing", drawing: [InkStroke(points: [InkPoint(0.5, 0.5)])], drawingDescription: "A star"), author: visitor, app: missing)
        other.ownerID = friend; other.created = 20; other.likeCount = 3
        var elsewhere = other; elsewhere.id = UUID(); elsewhere.sourceID = UUID(); elsewhere.ownerID = account; elsewhere.text = "My note from another Mac"
        var browserNote = other; browserNote.id = UUID(); browserNote.topic = SharedNoteTopic(AppIsland(label: "Original browser name", bundleID: renamed.bundleID))
        let input = [own, privateNote]
        let catalog = MiiverseCatalog(notes: input, apps: [game, renamed], shared: [synced, other, elsewhere, browserNote], accountID: account)
        XCTAssertEqual(catalog.entries.count, 5, "The own note has one local copy, not a duplicate server copy")
        XCTAssertEqual(catalog.filtered(section: "mine", query: "", sort: .newest).count, 3)
        XCTAssertEqual(catalog.filtered(section: "friends", query: "", sort: .newest).count, 2)
        XCTAssertEqual(catalog.filtered(section: "plaza", query: "", sort: .newest).map(\.id), [privateNote.id])
        let missingSection = catalog.sections.first { $0.id == "bundle:com.example.missing" }
        XCTAssertEqual(missingSection?.label, missing.label)
        XCTAssertNil(missingSection?.appID)
        XCTAssertEqual(missingSection?.count, 2)
        XCTAssertEqual(catalog.filtered(section: "all", query: "star", sort: .newest).count, 3)
        XCTAssertEqual(catalog.filtered(section: "all", query: "my browser", sort: .newest).map(\.id), [browserNote.id])
        XCTAssertEqual(catalog.filtered(section: "all", query: "", sort: .liked).first?.id, own.id)
        XCTAssertEqual(catalog.filtered(section: "all", query: "", sort: .oldest).first?.id, own.id)
        XCTAssertEqual(input, [own, privateNote], "Browsing never mutates private content or visibility")
    }

    func testCommunitiesMatchSteamIdentityAndKeepRemovedAppsOutOfThePlaza() {
        let author = Avatar()
        var game = AppIsland(label: "Local game", bundleID: "launcher.a"); game.steamAppID = 7
        var remote = game; remote.id = UUID(); remote.label = "Renamed game"; remote.bundleID = "launcher.b"
        var shared = SharedJournalNote(note: LocalNote(authorID: author.id, author: author.name, appID: remote.id, text: "Hello"), author: author, app: remote)
        shared.ownerID = UUID().uuidString
        let orphan = LocalNote(authorID: author.id, author: author.name, appID: UUID(), text: "Removed shortcut note")
        let catalog = MiiverseCatalog(notes: [orphan], apps: [game], shared: [shared, shared], accountID: UUID().uuidString)
        XCTAssertEqual(catalog.sections.first { $0.id == "steam:7" }?.count, 1)
        XCTAssertEqual(catalog.sections.first { $0.id == "steam:7" }?.appID, game.id)
        XCTAssertEqual(catalog.filtered(section: "steam:7", query: "", sort: .newest).map(\.id), [shared.id])
        XCTAssertTrue(catalog.filtered(section: "plaza", query: "", sort: .newest).isEmpty)
        XCTAssertEqual(catalog.entries.first { $0.id == orphan.id }?.sectionLabel, "Removed app")
        XCTAssertTrue(catalog.filtered(section: "all", query: "no match", sort: .newest).isEmpty)
    }
}
