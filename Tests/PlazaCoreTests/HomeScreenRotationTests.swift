import XCTest
@testable import PlazaCore

final class HomeScreenRotationTests: XCTestCase {
    private struct Random: RandomNumberGenerator {
        var state: UInt64 = 5
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
    private func app(_ name: String) -> AppIsland { AppIsland(label: name, bundleID: "test.\(name)") }

    func testBalancesSourcesBoundsPageDeduplicatesAndAvoidsRepeatingPreviousOrder() {
        let recent = (0..<15).map { app("Recent\($0)") }
        let games = (0..<15).map { app("Game\($0)") }
        var random = Random()
        let mix = HomeScreenRotation.select(recent: recent, friendGames: games, fallback: [], previous: [], using: &random)
        XCTAssertEqual(mix.count, 12)
        XCTAssertEqual(mix.filter { $0.label.hasPrefix("Recent") }.count, 6)
        XCTAssertEqual(mix.filter { $0.label.hasPrefix("Game") }.count, 6)
        var again = Random()
        let next = HomeScreenRotation.select(recent: recent, friendGames: games, fallback: [],
            previous: mix.map(HomeScreenRotation.key), using: &again)
        XCTAssertNotEqual(next.map(HomeScreenRotation.key), mix.map(HomeScreenRotation.key))
        XCTAssertEqual(Set(next.map(HomeScreenRotation.key)), Set(mix.map(HomeScreenRotation.key)))
        let duplicate = HomeScreenRotation.select(recent: [recent[0], recent[0]], friendGames: [recent[0]],
            fallback: [recent[0], games[0]], previous: [], using: &random)
        XCTAssertEqual(duplicate.count, 2)
        let fallback = HomeScreenRotation.select(recent: [], friendGames: [], fallback: recent, previous: [], using: &random)
        XCTAssertEqual(fallback.count, 12)
        XCTAssertTrue(HomeScreenRotation.select(recent: [], friendGames: [], fallback: [], previous: [], using: &random).isEmpty)
    }

    func testOnlyCurrentVisibleDiscordGamesWithAnUnambiguousInstalledMatchAreUsed() {
        let now = Date(), installed = app("Stardew Valley")
        func friend(source: String = "discord", active: Bool = true, age: Double = 0,
                    name: String = "Stardew Valley", presence: FriendPresence = .online) -> SharedMii {
            var f = SharedMii(id: UUID().uuidString, displayName: "Friend", avatar: Avatar(), note: "",
                              presence: presence, plazaOnline: false)
            f.activities = [.init(name: name, bundleID: nil, source: source, active: active,
                                  observedAt: now.timeIntervalSince1970 - age)]
            return f
        }
        let friends = [friend(), friend(), friend(source: "plaza"), friend(active: false), friend(age: 2000),
                       friend(name: "Not Installed"), friend(presence: .offline), friend(presence: .unknown)]
        XCTAssertEqual(HomeScreenRotation.installedFriendGames(friends: friends, installed: [installed], at: now), [installed])
        let ambiguous = AppIsland(label: installed.label, bundleID: "other.game")
        XCTAssertTrue(HomeScreenRotation.installedFriendGames(friends: [friend()], installed: [installed, ambiguous], at: now).isEmpty)
        XCTAssertTrue(HomeScreenRotation.installedFriendGames(friends: [friend()], installed: [], at: now).isEmpty)
    }

    func testSteamGamesKeepSeparateIdentitiesWhenTheyShareAnExecutableBundle() {
        var first = app("First"), second = first
        first.steamAppID = 10; second.steamAppID = 20
        var random = Random()
        XCTAssertEqual(HomeScreenRotation.select(recent: [first], friendGames: [second], fallback: [],
                                                previous: [], using: &random).count, 2)
    }
}
