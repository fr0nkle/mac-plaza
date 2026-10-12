import XCTest
@testable import PlazaCore

final class PlazaCoreTests: XCTestCase {
    func testRoundTripPreservesNotesAndAvatarParameters() throws {
        var doc = PlazaDocument()
        doc.avatars[0].glasses = true
        doc.avatars[0].hair = 4
        doc.apps = [AppIsland(label: "Example", bundleID: "test.example", path: "/Applications/Example.app", bookmark: Data([1, 2]))]
        let drawing = [InkStroke(points: [InkPoint(0.2, 0.4), InkPoint(0.8, 0.9)])]
        doc.notes = [LocalNote(authorID: doc.avatars[0].id, author: "You", appID: doc.apps[0].id, text: "A sketch", drawing: drawing, drawingDescription: "A diagonal line")]
        let encoded = try JSONEncoder().encode(doc)
        XCTAssertEqual(try DocumentStorage.decode(encoded), doc)
    }
    func testPortableExportOmitsAllLaunchReferences() {
        var doc = PlazaDocument()
        doc.apps = [AppIsland(label: "Example", bundleID: "test.example", path: "/Applications/Example.app", bookmark: Data([0, 1]))]
        let portable = doc.portable()
        XCTAssertNil(portable.apps[0].path)
        XCTAssertNil(portable.apps[0].bookmark)
        XCTAssertEqual(portable.apps[0].id, doc.apps[0].id)
        XCTAssertNotNil(doc.apps[0].path)
    }
    func testRejectsUnknownSchemaWithoutMutatingDocument() {
        var doc = PlazaDocument(); doc.version = 3
        XCTAssertThrowsError(try doc.validated())
    }
    func testRejectsOutOfBoundsAvatarAndPopulation() {
        var doc = PlazaDocument(); doc.avatars[0].hair = 900
        XCTAssertThrowsError(try doc.validated())
        doc = PlazaDocument(); doc.avatars[0].eyeSpacing = .infinity
        XCTAssertThrowsError(try doc.validated())
        doc = PlazaDocument(); doc.preferences.population = 10000
        XCTAssertThrowsError(try doc.validated())
    }
    func testLargerPopulationPersistsAndRemainsBounded() throws {
        var doc=PlazaDocument()
        XCTAssertEqual(doc.preferences.population,160)
        doc.preferences.population=200
        XCTAssertEqual(try DocumentStorage.decode(JSONEncoder().encode(doc)).preferences.population,200)
        XCTAssertEqual(CrowdSimulation(population:200,localCount:1).walkers.count,200)
        XCTAssertEqual(CrowdSimulation(population:10000,localCount:1).walkers.count,200)
        doc.preferences.population=201
        XCTAssertThrowsError(try doc.validated())
    }
    func testRejectsDuplicateIDsAndEmptyAvatarCatalog() {
        var doc = PlazaDocument(); doc.avatars.append(doc.avatars[0])
        XCTAssertThrowsError(try doc.validated())
        doc.avatars = []
        XCTAssertThrowsError(try doc.validated())
    }
    func testTextLimitCountsUserPerceivedCharacters() throws {
        var doc = PlazaDocument()
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 280)
        doc.notes = [LocalNote(authorID: doc.avatars[0].id, author: "You", appID: nil, text: text)]
        XCTAssertNoThrow(try doc.validated())
        doc.notes[0].text += "!"
        XCTAssertThrowsError(try doc.validated())
    }
    func testRejectsExcessiveOrUnboundedDrawingData() {
        var doc = PlazaDocument()
        doc.notes = [LocalNote(authorID: doc.avatars[0].id, author: "You", appID: nil, text: "", drawing: [InkStroke(points: [InkPoint(2, 0)])], drawingDescription: "A line")]
        XCTAssertThrowsError(try doc.validated())
        doc.notes[0].drawing = [InkStroke(points: [InkPoint(0.2, 0.3)])]
        doc.notes[0].drawingDescription = ""
        XCTAssertThrowsError(try doc.validated())
        doc.notes[0].drawingDescription = "A dot"
        doc.notes[0].drawing = [InkStroke(points: Array(repeating: InkPoint(0.2, 0.3), count: 20001))]
        XCTAssertThrowsError(try doc.validated())
    }
    func testRejectsExecutableNonApplicationPaths() {
        var doc = PlazaDocument()
        doc.apps = [AppIsland(label: "Bad", bundleID: "bad", path: "/bin/sh")]
        XCTAssertThrowsError(try doc.validated())
    }
    func testDeterministicSimulationRandomness() {
        var first = SeededRandom(seed: 42), second = SeededRandom(seed: 42), different = SeededRandom(seed: 43)
        let a = (0..<100).map { _ in first.next() }
        XCTAssertEqual(a, (0..<100).map { _ in second.next() })
        XCTAssertNotEqual(a, (0..<100).map { _ in different.next() })
    }
    func testStorageKeepsBackupAndDiscardsOutOfOrderSaves() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = DocumentStorage(url: dir.appendingPathComponent("plaza.json"))
        let first = PlazaDocument()
        try await storage.save(first, revision: 1)
        var second = first; second.avatars[0].name = "Pip"
        try await storage.save(second, revision: 3)
        try await storage.save(first, revision: 2)
        let loaded = try await storage.load(), backup = try await storage.recoverBackup()
        XCTAssertEqual(loaded, second)
        XCTAssertEqual(backup, first)
    }
    func testCorruptionDoesNotGetOverwrittenAndBackupCanRecover() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plaza.json")
        let storage = DocumentStorage(url: url)
        let first = PlazaDocument()
        try await storage.save(first, revision: 1)
        try await storage.save(first, revision: 2)
        try Data("broken".utf8).write(to: url)
        do { _ = try await storage.load(); XCTFail("Corrupt store must fail closed") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
        let backup = try await storage.recoverBackup()
        XCTAssertEqual(backup, first)
    }
    func testOversizedImportIsRejected() {
        XCTAssertThrowsError(try DocumentStorage.decode(Data(repeating: 0, count: 12_000_001)))
    }
    func testJournalHasAnAggregateDrawingBudget() {
        var doc = PlazaDocument()
        for _ in 0..<4 {
            doc.notes.append(LocalNote(authorID: doc.avatars[0].id, author: "You", appID: nil, text: "", drawing: [InkStroke(points: Array(repeating: InkPoint(0.1234567890123456, 0.9876543210987654), count: 20000))], drawingDescription: "A dense drawing"))
        }
        XCTAssertThrowsError(try doc.validated())
        doc.notes.removeLast()
        XCTAssertNoThrow(try doc.validated())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        XCTAssertNoThrow(try DocumentStorage.decode(encoder.encode(doc)))
    }
}
