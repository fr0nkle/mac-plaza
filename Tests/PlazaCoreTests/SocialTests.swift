import XCTest
@testable import PlazaCore

final class SocialTests: XCTestCase {
    func testRetiredServiceMigrationPreservesCustomOriginsAndRequiresHTTPS() {
        let old = "https://expired.trycloudflare.com"
        let stable = "https://plaza.example.ts.net"
        XCTAssertEqual(SocialEndpoint.initialAddress(saved: nil, bundled: stable, retired: [old]), stable)
        XCTAssertEqual(SocialEndpoint.initialAddress(saved: old + "/", bundled: stable, retired: [old]), stable)
        for custom in ["https://my-service.example", old + ".evil.example", old + "/other", old + ":8443", ""] {
            XCTAssertEqual(SocialEndpoint.initialAddress(saved: custom, bundled: stable, retired: [old]), custom)
        }
        XCTAssertEqual(SocialEndpoint.initialAddress(saved: old, bundled: nil, retired: [old]), old)
        XCTAssertEqual(SocialEndpoint.initialAddress(saved: old, bundled: "http://127.0.0.1:8787", retired: [old]), old)
        XCTAssertEqual(SocialEndpoint.initialAddress(saved: old, bundled: stable, retired: []), old)
    }

    func testAssignedFriendsGetLimitedPlazaSlotsBeforeRandomFriends() {
        var friends = (0..<224).map { index in
            var friend = SharedMii(id: UUID().uuidString, displayName: "Friend \(index)", avatar: Avatar(),
                                   note: "Hello \(index)", presence: index == 223 ? .offline : .online, plazaOnline: false)
            friend.temporaryAvatar = true
            return friend
        }
        friends[160].locallyAssignedAvatar = true
        friends[223].locallyAssignedAvatar = true
        let original = friends
        let selected = FriendMiiAssignments.plazaFriends(friends, capacity: 5)
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(Array(friends.reversed()),capacity:5,retaining:selected.map(\.avatar.id)),selected,
                       "Presence sorting must not rotate the visible crowd or change its order")
        XCTAssertEqual(selected, [friends[160], friends[223], friends[0], friends[1], friends[2]],
                       "Assigned friends beyond the crowd cutoff must be admitted, including offline friends.")
        XCTAssertEqual(friends, original, "Priority must not mutate the underlying roster.")
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(friends, capacity: 1), [friends[160]])
        XCTAssertTrue(FriendMiiAssignments.plazaFriends(friends, capacity: 0).isEmpty)
        XCTAssertTrue(FriendMiiAssignments.plazaFriends(friends, capacity: -1).isEmpty)
        let all = FriendMiiAssignments.plazaFriends(friends, capacity: 300)
        XCTAssertEqual(all.count, friends.count)
        XCTAssertEqual(Set(all.map(\.avatar.id)).count, friends.count)
        XCTAssertEqual(Array(all.dropFirst(2)), Array(friends[..<160]) + Array(friends[161..<223]))
        friends[160].locallyAssignedAvatar = false
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(friends, capacity: 1), [friends[223]])
        friends[223].locallyAssignedAvatar = false
        XCTAssertEqual(FriendMiiAssignments.plazaFriends(friends, capacity: 1), [friends[0]])
    }

    func testLocalMiiChoicesKeepDistinctWalkersAndYieldToLinkedMiis() throws {
        let records = [DiscordFriendRecord(discordID: "123", displayName: "First", presence: .online),
                       DiscordFriendRecord(discordID: "456", displayName: "Second", presence: .idle)]
        let now = Date().timeIntervalSince1970
        let roster = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [],
            games: [DiscordGameRecord(discordID: "123", name: "Great Game", observedAt: now)],
            customStatuses: [DiscordCustomStatusRecord(discordID: "123", text: "Hello!", observedAt: now)])
        var assignments = FriendMiiAssignments()
        let random = assignments.resolve(shared: [], unlinked: roster.unlinked)
        var custom = Avatar(name: "My custom Mii", outfit: 8); custom.hair = 44
        let chosen = assignments.resolve(shared: [], unlinked: roster.unlinked, localAppearances: ["123": custom, "456": custom])
        XCTAssertEqual(chosen.map(\.avatar.id), random.map(\.avatar.id))
        XCTAssertNotEqual(chosen[0].avatar.id, chosen[1].avatar.id)
        XCTAssertFalse(chosen.contains { $0.avatar.id == custom.id })
        XCTAssertTrue(chosen.allSatisfy { $0.locallyAssignedAvatar == true && $0.avatar.hair == custom.hair })
        XCTAssertEqual(chosen[0].avatar.name, "First")
        XCTAssertEqual(chosen[0].overheadText, "Hello!")
        XCTAssertEqual(chosen[0].activities, random[0].activities)
        XCTAssertEqual(chosen[1].presence, .idle)
        custom.hair = 12
        XCTAssertEqual(assignments.resolve(shared: [], unlinked: roster.unlinked, localAppearances: ["123": custom])[0].avatar.hair, 12)
        XCTAssertEqual(assignments.resolve(shared: [], unlinked: roster.unlinked).map(\.avatar), random.map(\.avatar))
        var published = chosen[0]; published.temporaryAvatar = nil; published.locallyAssignedAvatar = nil
        published.avatar = Avatar(name: "Their linked Mii")
        XCTAssertEqual(assignments.resolve(shared: [published], unlinked: [roster.unlinked[1]], localAppearances: ["123": custom])[0], published)
    }

    func testCustomStatusesReplaceAvailabilityWithoutChangingGameGathering() throws {
        let now = Date().timeIntervalSince1970
        var records = [DiscordFriendRecord(discordID: "123", displayName: "Friend", presence: .dnd)]
        let status = DiscordCustomStatusRecord(discordID: "123", text: "☀️ Making something nice", observedAt: now)
        let game = DiscordGameRecord(discordID: "123", name: "Great Game", observedAt: now)
        var assignments = FriendMiiAssignments()
        let roster = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], games: [game], customStatuses: [status])
        let friend = try XCTUnwrap(assignments.resolve(shared: [], unlinked: roster.unlinked).first)
        XCTAssertEqual(friend.overheadText, status.text)
        XCTAssertTrue(friend.temporaryAvatar == true)
        let island = AppIsland(label: "Great Game", bundleID: "test.game")
        XCTAssertEqual(FriendActivityMatcher.island(for: friend.activities, apps: [island]), island.id)
        let cleared = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [])
        let next = try XCTUnwrap(assignments.resolve(shared: [], unlinked: cleared.unlinked).first)
        XCTAssertEqual(friend.avatar.id, next.avatar.id)
        XCTAssertEqual(next.overheadText, "")
        records[0].presence = .offline
        XCTAssertNil(try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], customStatuses: [status]).unlinked[0].customStatus)
        var chosen = friend; chosen.note = "Shared note"
        records[0].presence = .online
        XCTAssertEqual(try DiscordFriendRoster.profiles(records, shared: [chosen], unlinked: [], customStatuses: [status]).shared[0].overheadText, status.text)
        for presence in FriendPresence.allCases {
            var noStatus = next; noStatus.presence = presence; noStatus.plazaOnline = true
            XCTAssertEqual(noStatus.overheadText, "", "Availability must not create a text bubble.")
        }
    }

    func testCustomStatusValidationExpiryAndOldServiceCompatibility() throws {
        let records = [DiscordFriendRecord(discordID: "123", displayName: "Friend", presence: .online)]
        var status = DiscordCustomStatusRecord(discordID: "123", text: "Hello", observedAt: Date().timeIntervalSince1970)
        func snapshot(_ value: DiscordCustomStatusRecord) -> DiscordGameSnapshot {
            DiscordGameSnapshot(state: "ready", coveredDiscordIDs: ["123"], games: [], customStatuses: [value])
        }
        XCTAssertNoThrow(try snapshot(status).validated(friends: records))
        status.discordID = "999"
        XCTAssertThrowsError(try snapshot(status).validated(friends: records))
        status.discordID = "123"; status.text = String(repeating: "x", count: 281)
        XCTAssertThrowsError(try snapshot(status).validated(friends: records))
        status.text = " "; XCTAssertThrowsError(try status.validate())
        status.text = "Hello"; status.observedAt = .nan; XCTAssertThrowsError(try status.validate())
        status.observedAt = Date().timeIntervalSince1970 - 91
        XCTAssertNil(try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], customStatuses: [status]).unlinked[0].customStatus)
        XCTAssertThrowsError(try DiscordGameSnapshot(state: "ready", coveredDiscordIDs: ["123"], games: [], customStatuses: [status, status]).validated(friends: records))
        XCTAssertThrowsError(try DiscordGameSnapshot(state: "unavailable", coveredDiscordIDs: ["123"], games: [], customStatuses: [status]).validated(friends: records))
        let old = Data(#"{"state":"ready","coveredDiscordIDs":["123"],"games":[]}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(DiscordGameSnapshot.self, from: old).validated(friends: records).customStatuses.isEmpty)
    }

    func testDiscordGamesAttachToTemporaryMiisAndRetargetMatchingAppCircles() throws {
        let now = Date().timeIntervalSince1970
        let records = [DiscordFriendRecord(discordID: "123", displayName: "Player", presence: .online)]
        let game = DiscordGameRecord(discordID: "123", name: "Great-Game", observedAt: now)
        var assignments = FriendMiiAssignments()
        let waiting = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [])
        let initial = try XCTUnwrap(assignments.resolve(shared: [], unlinked: waiting.unlinked).first)
        let playing = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], games: [game])
        var friend = try XCTUnwrap(assignments.resolve(shared: [], unlinked: playing.unlinked).first)
        XCTAssertEqual(friend.avatar.id, initial.avatar.id)
        XCTAssertTrue(friend.isPlayingDiscordGame)
        friend.note = "An authored note"
        XCTAssertEqual(friend.overheadText, "Playing Great-Game")
        let island = AppIsland(label: "Great Game", bundleID: "test.game")
        XCTAssertEqual(FriendActivityMatcher.island(for: friend.activities, apps: [island]), island.id)
        let stopped = try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], games: [])
        let refreshed = try XCTUnwrap(assignments.resolve(shared: [], unlinked: stopped.unlinked).first)
        XCTAssertEqual(refreshed.avatar.id, initial.avatar.id)
        XCTAssertTrue(refreshed.activities.isEmpty)
        XCTAssertNil(FriendActivityMatcher.island(for: refreshed.activities, apps: [island]))
        var offline = records[0]; offline.presence = .offline
        XCTAssertTrue(try DiscordFriendRoster.profiles([offline], shared: [], unlinked: [], games: [game]).unlinked[0].activities.isEmpty)
    }

    func testDiscordGameResponsesCannotAttachUnknownFriendsOrStaleActivity() throws {
        let records = [DiscordFriendRecord(discordID: "123", displayName: "Player", presence: .online)]
        var game = DiscordGameRecord(discordID: "999", name: "Private", observedAt: Date().timeIntervalSince1970)
        XCTAssertThrowsError(try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], games: [game]))
        game.discordID = "123"
        XCTAssertThrowsError(try DiscordGameSnapshot(state: "ready", coveredDiscordIDs: [], games: [game]).validated(friends: records))
        XCTAssertThrowsError(try DiscordGameSnapshot(state: "unavailable", coveredDiscordIDs: ["123"], games: [game]).validated(friends: records))
        XCTAssertThrowsError(try DiscordGameSnapshot(state: "ready", coveredDiscordIDs: ["123"], games: [game, game]).validated(friends: records))
        game.observedAt -= 1801
        XCTAssertTrue(try DiscordFriendRoster.profiles(records, shared: [], unlinked: [], games: [game]).unlinked[0].activities.isEmpty)
    }

    func testDiscordFriendsAppearWithoutPlazaInvitationsAndKeepSessionMiis() throws {
        let record = DiscordFriendRecord(discordID: "123456789012345678", displayName: "Discord friend", presence: .online)
        let roster = try DiscordFriendRoster.profiles([record], shared: [], unlinked: [])
        XCTAssertTrue(roster.shared.isEmpty)
        XCTAssertEqual(roster.unlinked.count, 1)
        XCTAssertNotNil(UUID(uuidString: roster.unlinked[0].id))
        XCTAssertEqual(try record.plazaProfile().id, roster.unlinked[0].id)
        var assignments = FriendMiiAssignments()
        let initial = try XCTUnwrap(assignments.resolve(shared: [], unlinked: roster.unlinked).first)
        XCTAssertEqual(initial.temporaryAvatar, true)
        XCTAssertEqual(initial.overheadText, "")
        var changed = record; changed.presence = .dnd
        let refreshed = try DiscordFriendRoster.profiles([changed], shared: [], unlinked: [])
        let next = try XCTUnwrap(assignments.resolve(shared: [], unlinked: refreshed.unlinked).first)
        XCTAssertEqual(next.avatar.id, initial.avatar.id)
        XCTAssertEqual(next.overheadText, "")
    }

    func testDiscordMembershipRestrictsSharedProfilesAndUsesLiveAvailability() throws {
        let record = DiscordFriendRecord(discordID: "123", displayName: "Friend", presence: .idle)
        var chosen = SharedMii(id: UUID().uuidString, displayName: "Friend", avatar: Avatar(name: "Chosen"), note: "Hello", presence: .offline, plazaOnline: false)
        chosen.discordID = "123"
        var stranger = chosen; stranger.id = UUID().uuidString; stranger.discordID = "456"
        let roster = try DiscordFriendRoster.profiles([record], shared: [chosen, stranger], unlinked: [])
        XCTAssertEqual(roster.shared.count, 1)
        XCTAssertEqual(roster.shared.first?.avatar, chosen.avatar)
        XCTAssertEqual(roster.shared.first?.presence, .idle)
        XCTAssertTrue(roster.unlinked.isEmpty)
        XCTAssertTrue(try DiscordFriendRoster.profiles([], shared: [chosen], unlinked: []).shared.isEmpty)
        XCTAssertThrowsError(try DiscordFriendRoster.profiles([record, record], shared: [], unlinked: []))
        XCTAssertThrowsError(try DiscordFriendRecord(discordID: "invalid", displayName: "Friend", presence: .online).plazaProfile())
    }

    func testTemporaryFriendMiisSurviveRefreshAndYieldToPublishedAppearance() throws {
        let id = UUID().uuidString
        var profile = UnlinkedFriend(id: id, displayName: String(repeating: "F", count: 80), presence: .online, plazaOnline: false,
                                     activities: [SharedAppActivity(name: "Music", bundleID: "com.apple.Music", source: "plaza", active: true, observedAt: Date().timeIntervalSince1970)])
        var assignments = FriendMiiAssignments()
        let first = try XCTUnwrap(assignments.resolve(shared: [], unlinked: [profile]).first)
        XCTAssertNoThrow(try first.validate())
        XCTAssertEqual(first.avatar.name.count, 24)
        XCTAssertEqual(first.temporaryAvatar, true)
        XCTAssertEqual(first.overheadText, "Using Music")
        let music = AppIsland(label: "Music", bundleID: "com.apple.Music")
        XCTAssertEqual(FriendActivityMatcher.island(for: first.activities, apps: [music]), music.id)
        profile.presence = .idle; profile.displayName = "Renamed friend"
        let refreshed = try XCTUnwrap(assignments.resolve(shared: [], unlinked: [profile]).first)
        XCTAssertEqual(first.avatar.id, refreshed.avatar.id)
        XCTAssertEqual(first.avatar.hair, refreshed.avatar.hair)
        XCTAssertEqual(refreshed.avatar.name, profile.displayName)
        XCTAssertEqual(refreshed.presence, .idle)
        let published = SharedMii(id: id, displayName: profile.displayName, avatar: Avatar(name: "Chosen"), note: "Hello", presence: .online, plazaOnline: true)
        XCTAssertEqual(assignments.resolve(shared: [published], unlinked: []), [published])
        XCTAssertEqual(assignments.resolve(shared: [], unlinked: [profile]).first?.avatar.id, first.avatar.id)
        assignments.reset()
        XCTAssertNotEqual(assignments.resolve(shared: [], unlinked: [profile]).first?.avatar.id, first.avatar.id)
        let renewed = assignments.resolve(shared: [], unlinked: [profile]).first?.avatar.id
        _ = assignments.resolve(shared: [], unlinked: [])
        XCTAssertEqual(assignments.resolve(shared: [], unlinked: [profile]).first?.avatar.id, renewed,
                       "A temporary service gap must not generate a different Mii")
    }

    func testUnlinkedRosterValidationAndOldSnapshotCompatibility() throws {
        let account = SocialAccount(id: UUID().uuidString, displayName: "You", avatar: nil, note: "", sharing: false, sharePresence: false, shareActivity: false)
        let friend = SharedMii(id: UUID().uuidString, displayName: "Friend", avatar: Avatar(), note: "", presence: .online, plazaOnline: false)
        var snapshot = SocialSnapshot(account: account, friends: [friend], contacts: [], incoming: [], outgoing: [])
        XCTAssertNoThrow(try JSONDecoder().decode(SocialSnapshot.self, from: JSONEncoder().encode(snapshot)).validated())
        snapshot.unlinkedFriends = [UnlinkedFriend(id: UUID().uuidString, displayName: "Unlinked", presence: .unknown, plazaOnline: false)]
        XCTAssertNoThrow(try snapshot.validated())
        snapshot.unlinkedFriends?[0].id = friend.id
        XCTAssertThrowsError(try snapshot.validated())
        snapshot.unlinkedFriends?[0].id = "invalid"
        XCTAssertThrowsError(try snapshot.validated())
        snapshot.unlinkedFriends = (0..<100).map { _ in UnlinkedFriend(id: UUID().uuidString, displayName: "Friend", presence: .unknown, plazaOnline: false) }
        // Automatic Discord profiles coexist with the 100 legacy Plaza contacts.
        XCTAssertNoThrow(try snapshot.validated())
        snapshot.unlinkedFriends?.append(UnlinkedFriend(id: UUID().uuidString, displayName: "One too many", presence: .unknown, plazaOnline: false))
        XCTAssertThrowsError(try snapshot.validated())
    }

    func testOverheadTextUsesOnlyAvailableSharedObservations() {
        var friend = SharedMii(id: UUID().uuidString, displayName: "Friend", avatar: Avatar(), note: "", presence: .unknown, plazaOnline: false)
        XCTAssertEqual(friend.overheadText, "")
        friend.presence = .idle
        XCTAssertEqual(friend.overheadText, "")
        friend.plazaOnline = true
        XCTAssertEqual(friend.overheadText, "")
        friend.activities = [SharedAppActivity(name: "Music", bundleID: nil, source: "plaza", active: false, observedAt: Date().timeIntervalSince1970)]
        XCTAssertEqual(friend.overheadText, "Recently used Music")
        friend.note = "Authored note"
        XCTAssertEqual(friend.overheadText, "Authored note")
        friend.note = ""; friend.activities[0].observedAt -= 1801
        XCTAssertEqual(friend.overheadText, "")
    }
    func testCurrentAndRecentActivityMatchOnlyVisibleUnambiguousApps() {
        let now = Date(timeIntervalSince1970: 10000)
        let music = AppIsland(label: "My Tunes", bundleID: "com.apple.Music")
        let game = AppIsland(label: "Great Game", bundleID: "test.game")
        let recent = SharedAppActivity(name: "Music", bundleID: "com.apple.Music", source: "plaza", active: false, observedAt: 9900)
        let current = SharedAppActivity(name: "great-game", bundleID: nil, source: "discord", active: true, observedAt: 9950)
        XCTAssertEqual(FriendActivityMatcher.island(for: [recent, current], apps: [music, game], at: now), game.id)
        XCTAssertEqual(FriendActivityMatcher.island(for: [recent, current], apps: [music], at: now), music.id)
        var stale = recent; stale.observedAt = 8000
        XCTAssertNil(FriendActivityMatcher.island(for: [stale], apps: [music], at: now))
        let duplicate = AppIsland(label: "Great Game", bundleID: "test.other")
        XCTAssertNil(FriendActivityMatcher.island(for: [current], apps: [game, duplicate], at: now))
    }
    func testActivityGroupingRetargetsWithoutTeleporting() {
        var crowd = CrowdSimulation(population: 20, localCount: 1)
        crowd.groupsBelowIslands = true; crowd.minimumSpacing = 0.025
        crowd.islandHalfWidth = 0.06; crowd.islandTopClearance = 0.05; crowd.islandBottomClearance = 0.16
        crowd.islands = [CrowdPoint(0.25, 0.20), CrowdPoint(0.75, 0.20)]
        let start = crowd.walkers[2].position
        crowd.setGatheringIslands([2: 1])
        XCTAssertEqual(crowd.walkers[2].position, start)
        XCTAssertEqual(crowd.gatheringIslands[2], 1)
        XCTAssertLessThan(abs(crowd.walkers[2].target.x - 0.75), 0.1)
        XCTAssertGreaterThan(crowd.walkers[2].target.y, 0.36)
        crowd.setGatheringIslands([:])
        XCTAssertTrue(crowd.gatheringIslands.isEmpty)
        XCTAssertEqual(crowd.walkers[2].position, start)
    }
    func testRemoteEndpointsRequireHTTPSAndCannotContainCredentials() throws {
        for address in ["https://plaza.example.com", "http://127.0.0.1:8787", "http://localhost:8787"] {
            XCTAssertNoThrow(try SocialEndpoint.validated(address))
        }
        for address in ["http://plaza.example.com", "https://user:secret@plaza.example.com", "file:///tmp/service",
                        "https://plaza.example.com?token=secret", "https://plaza.example.com/api", "https://plaza.example.com#fragment"] {
            XCTAssertThrowsError(try SocialEndpoint.validated(address), address)
        }
    }
    func testRemoteProfilesAreBoundedAndCannotDuplicateAvatarIdentity() throws {
        let account = SocialAccount(id: UUID().uuidString, displayName: "You", avatar: nil, note: "", sharing: false, sharePresence: false, shareActivity: false)
        let friend = SharedMii(id: UUID().uuidString, displayName: "Friend", avatar: Avatar(), note: "Hello", presence: .online, plazaOnline: true)
        var snapshot = SocialSnapshot(account: account, friends: [friend], contacts: [], incoming: [], outgoing: [])
        XCTAssertNoThrow(try snapshot.validated())
        var other = friend; other.id = UUID().uuidString
        snapshot.friends.append(other)
        XCTAssertThrowsError(try snapshot.validated())
        snapshot.friends = [friend]; snapshot.friends[0].note = String(repeating: "x", count: 281)
        XCTAssertThrowsError(try snapshot.validated())
        snapshot.friends = [friend]; snapshot.friends[0].avatar.height = .nan
        XCTAssertThrowsError(try snapshot.validated())
    }
    func testSocialIdentityAndCredentialsStayOutsidePortablePlaza() throws {
        let document = PlazaDocument().portable()
        let data = try JSONEncoder().encode(document)
        let json = String(decoding: data, as: UTF8.self)
        for key in ["token", "friends", "discord", "presence", "serverAddress"] { XCTAssertFalse(json.contains(key)) }
        XCTAssertEqual(try DocumentStorage.decode(data), document)
    }
}
