import XCTest
@testable import PlazaCore

final class SteamShortcutTests: XCTestCase {
    func testSteamIdentityPersistsWithoutExportingLocalReferencesAndLegacyStillDecodes() throws {
        var doc = PlazaDocument()
        var app = AppIsland(label: "Balatro", bundleID: "com.Balatro.localthunk", path: "/Library/Steam/Balatro.app", bookmark: Data([1]))
        app.steamAppID = 2379780
        doc.apps = [app]
        XCTAssertEqual(try DocumentStorage.decode(JSONEncoder().encode(doc)), doc)
        let portable = doc.portable()
        XCTAssertEqual(portable.apps[0].steamAppID, 2379780)
        XCTAssertNil(portable.apps[0].path)
        XCTAssertNil(portable.apps[0].bookmark)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
        var apps = try XCTUnwrap(legacy["apps"] as? [[String: Any]])
        apps[0].removeValue(forKey: "steamAppID"); legacy["apps"] = apps
        XCTAssertNil(try DocumentStorage.decode(JSONSerialization.data(withJSONObject: legacy)).apps[0].steamAppID)
        doc.apps[0].steamAppID = 0
        XCTAssertThrowsError(try doc.validated())
    }
}
