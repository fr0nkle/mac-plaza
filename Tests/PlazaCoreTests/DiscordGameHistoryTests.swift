import XCTest
@testable import PlazaCore

final class DiscordGameHistoryTests: XCTestCase {
    private let player = DiscordFriendRecord(discordID: "123", displayName: "Exotic_Panda", presence: .online)
    private func snapshot(_ name: String?, at date: Date, covered: [String] = ["123"]) -> DiscordGameSnapshot {
        DiscordGameSnapshot(state: "ready", coveredDiscordIDs: covered,
            games: name.map { [DiscordGameRecord(discordID: "123", name: $0, observedAt: date.timeIntervalSince1970)] } ?? [])
    }

    func testTwoHoursStartAtConfirmedStopAndRepeatedEmptyPollsDoNotExtendIt() throws {
        let start = Date(timeIntervalSince1970: 100_000)
        var history = DiscordGameHistory()
        // Playing for longer than two hours must not exhaust the retention window.
        for elapsed in stride(from: 0, through: 9000, by: 30) {
            let now = start.addingTimeInterval(Double(elapsed))
            try history.update(snapshot("Great Game", at: now), friends: [player], at: now)
        }
        let stop = start.addingTimeInterval(9015)
        try history.update(snapshot(nil, at: stop), friends: [player], at: stop)
        XCTAssertEqual(history.records(at: stop).first?.observedAt, stop.timeIntervalSince1970)
        XCTAssertEqual(history.records(at: stop).first?.active, false)
        for elapsed in [15.0, 3600, 7199] {
            let now = stop.addingTimeInterval(elapsed)
            try history.update(snapshot(nil, at: now), friends: [player], at: now)
            XCTAssertEqual(history.records(at: now).first?.observedAt, stop.timeIntervalSince1970)
        }
        XCTAssertTrue(history.records(at: stop.addingTimeInterval(7200)).isEmpty)
    }

    func testSwitchingGamesMovesAffinityAndOfflineAssignedMiisKeepRecentGame() throws {
        let now = Date()
        var history = DiscordGameHistory()
        try history.update(snapshot("First Game", at: now.addingTimeInterval(-15)), friends: [player], at: now.addingTimeInterval(-15))
        try history.update(snapshot("Great-Game", at: now), friends: [player], at: now)
        let stop = now.addingTimeInterval(10)
        var offline = player; offline.presence = .offline
        try history.update(snapshot(nil, at: stop), friends: [offline], at: stop)
        let roster = try DiscordFriendRoster.profiles([offline], shared: [], unlinked: [], games: history.records(at: stop))
        var assignments = FriendMiiAssignments()
        let mii = Avatar(name: "Custom Mii", outfit: 8)
        let friend = try XCTUnwrap(assignments.resolve(shared: [], unlinked: roster.unlinked, localAppearances: ["123": mii]).first)
        XCTAssertEqual(friend.locallyAssignedAvatar, true)
        XCTAssertFalse(friend.isPlayingDiscordGame)
        XCTAssertEqual(friend.overheadText, "Exotic_Panda was recently playing Great-Game")
        let game = AppIsland(label: "Great Game", bundleID: "test.game")
        let other = AppIsland(label: "First Game", bundleID: "test.other")
        XCTAssertEqual(FriendActivityMatcher.island(for: friend.activities, apps: [game, other], at: stop.addingTimeInterval(7199)), game.id)
        XCTAssertEqual(HomeScreenRotation.installedFriendGames(friends: [friend], installed: [game, other], at: stop.addingTimeInterval(7199)), [game])
        XCTAssertNil(FriendActivityMatcher.island(for: friend.activities, apps: [game, other], at: stop.addingTimeInterval(7200)))
        XCTAssertTrue(HomeScreenRotation.installedFriendGames(friends: [friend], installed: [game, other], at: stop.addingTimeInterval(7200)).isEmpty)
    }

    func testCoverageAndFriendRemovalPurgeHistoryButOutagesDoNotInventLiveActivity() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var history = DiscordGameHistory()
        try history.update(snapshot("Great Game", at: now), friends: [player], at: now)
        let unavailable = DiscordGameSnapshot(state: "unavailable", coveredDiscordIDs: [], games: [])
        try history.update(unavailable, friends: [player], at: now.addingTimeInterval(30))
        XCTAssertEqual(history.records(at: now.addingTimeInterval(30)).first?.active, false)
        XCTAssertEqual(history.records(at: now.addingTimeInterval(30)).first?.observedAt, now.timeIntervalSince1970)
        try history.update(unavailable, friends: [player], at: now.addingTimeInterval(7199))
        XCTAssertTrue(history.records(at: now.addingTimeInterval(7200)).isEmpty)
        try history.update(snapshot("Great Game", at: now), friends: [player], at: now)
        try history.update(snapshot(nil, at: now, covered: []), friends: [player], at: now)
        XCTAssertTrue(history.records(at: now).isEmpty)
        try history.update(snapshot("Great Game", at: now), friends: [player], at: now)
        history.retain(friendIDs: [], at: now)
        XCTAssertTrue(history.records(at: now).isEmpty)
    }

    func testRelaunchAndLongPollingGapsNeverRenewTheExpiry() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        var original = DiscordGameHistory()
        try original.update(snapshot("Great Game", at: now), friends: [player], at: now)
        var restored = try JSONDecoder().decode(DiscordGameHistory.self, from: JSONEncoder().encode(original))
        restored.restore(at: now.addingTimeInterval(3600))
        XCTAssertEqual(restored.records(at: now.addingTimeInterval(3600)).first?.active, false)
        XCTAssertEqual(restored.records(at: now.addingTimeInterval(3600)).first?.observedAt, now.timeIntervalSince1970)
        XCTAssertTrue(restored.records(at: now.addingTimeInterval(7200)).isEmpty)
        try original.update(snapshot(nil, at: now.addingTimeInterval(3600)), friends: [player], at: now.addingTimeInterval(3600))
        XCTAssertTrue(original.records(at: now.addingTimeInterval(7200)).isEmpty)
    }

    func testLegacyWireGamesStayActiveAndOnlyRecentDiscordGamesGetTwoHours() throws {
        let legacy = Data("{\"discordID\":\"123\",\"name\":\"Game\",\"observedAt\":100000}".utf8)
        var game = try JSONDecoder().decode(DiscordGameRecord.self, from: legacy)
        XCTAssertTrue(game.active)
        let later = Date(timeIntervalSince1970: 103600)
        XCTAssertFalse(game.activity.isRecent(at: later))
        game.active = false
        XCTAssertTrue(game.activity.isRecent(at: later))
        let plaza = SharedAppActivity(name: "Notes", bundleID: nil, source: "plaza", active: false, observedAt: 100000)
        XCTAssertFalse(plaza.isRecent(at: later))
        XCTAssertFalse(game.activity.isRecent(at: Date(timeIntervalSince1970: 107200)))
    }

    func testAppVisitorsAgreeWithGatheringAndExcludeOffSceneAmbiguousAndExpiredFriends() throws {
        let now = Date()
        let game = AppIsland(label: "Great Game", bundleID: "test.game")
        let notes = AppIsland(label: "Notes", bundleID: "com.apple.Notes")
        var recent = SharedMii(id: UUID().uuidString, displayName: "Exotic_Panda", avatar: Avatar(), note: "", presence: .offline, plazaOnline: false)
        recent.activities = [DiscordGameRecord(discordID: "123", name: "Great-Game", observedAt: now.timeIntervalSince1970 - 600, active: false).activity]
        var active = SharedMii(id: UUID().uuidString, displayName: "Active", avatar: Avatar(), note: "", presence: .online, plazaOnline: true)
        active.activities = [SharedAppActivity(name: "Notes", bundleID: notes.bundleID, source: "plaza", active: true, observedAt: now.timeIntervalSince1970)] + recent.activities
        let rendered = Set([recent.avatar.id, active.avatar.id])
        let visitors = FriendAppVisitor.gathered(around: game.id, apps: [game, notes], friends: [recent, active], rendered: rendered, at: now)
        XCTAssertEqual(visitors.map(\.friend.id), [recent.id])
        XCTAssertEqual(visitors.first?.detail(at: now), "Recently played · 10 minutes ago")
        XCTAssertEqual(FriendAppVisitor.gathered(around: notes.id, apps: [game, notes], friends: [recent, active], rendered: rendered, at: now).first?.detail(at: now), "Using now")
        XCTAssertTrue(FriendAppVisitor.gathered(around: game.id, apps: [game], friends: [recent], rendered: [], at: now).isEmpty)
        let duplicate = AppIsland(label: "Great Game", bundleID: "test.duplicate")
        XCTAssertTrue(FriendAppVisitor.gathered(around: game.id, apps: [game, duplicate], friends: [recent], rendered: rendered, at: now).isEmpty)
        XCTAssertTrue(FriendAppVisitor.gathered(around: game.id, apps: [game], friends: [recent], rendered: rendered, at: now.addingTimeInterval(6600)).isEmpty)
    }
}
