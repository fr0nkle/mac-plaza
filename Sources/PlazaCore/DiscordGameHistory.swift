import Foundation

/// One observed game per friend. This viewer-local memory never queries past
/// Discord activity or requires the friend to have a Plaza account.
public struct DiscordGameHistory: Codable, Equatable, Sendable {
    private var games: [String: DiscordGameRecord] = [:]
    public init() {}

    public func records(at date: Date = Date()) -> [DiscordGameRecord] {
        games.values.compactMap { saved in
            var game = saved
            let age = date.timeIntervalSince1970 - game.observedAt
            guard age >= -60 && age < 7200 else { return nil }
            // A lost connection must never turn a remembered game into a live claim.
            if age >= 90 { game.active = false }
            return game
        }.sorted { $0.discordID < $1.discordID }
    }

    public mutating func update(_ snapshot: DiscordGameSnapshot, friends: [DiscordFriendRecord], at date: Date = Date()) throws {
        _ = try snapshot.validated(friends: friends)
        retain(friendIDs: Set(friends.map(\.discordID)), at: date)
        guard snapshot.state == "ready" else { suspend(at: date); return }
        let covered = Set(snapshot.coveredDiscordIDs)
        games = games.filter { covered.contains($0.key) }
        let online = Set(friends.filter { $0.presence != .offline && $0.presence != .unknown }.map(\.discordID))
        let playing = Dictionary(uniqueKeysWithValues: snapshot.games.filter {
            $0.active && $0.activity.isRecent(at: date) && online.contains($0.discordID)
        }.map { ($0.discordID, $0) })
        for id in covered {
            if var current = playing[id] {
                current.observedAt = date.timeIntervalSince1970
                games[id] = current
            } else if var previous = games[id], previous.active {
                // Start the two hours once, at the first confirmed stop. After
                // a polling gap, use the last observation rather than inventing
                // a later stop time and extending the history.
                if date.timeIntervalSince1970 - previous.observedAt < 90 {
                    previous.observedAt = date.timeIntervalSince1970
                }
                previous.active = false
                games[id] = previous
            }
        }
        retain(friendIDs: covered, at: date)
    }

    public mutating func retain(friendIDs: Set<String>, at date: Date = Date()) {
        games = Dictionary(uniqueKeysWithValues: records(at: date).filter {
            friendIDs.contains($0.discordID)
        }.map { ($0.discordID, $0) })
    }

    public mutating func suspend(at date: Date = Date()) {
        games = Dictionary(uniqueKeysWithValues: records(at: date).map {
            var game = $0; game.active = false
            return (game.discordID, game)
        })
    }

    public mutating func restore(at date: Date = Date()) {
        guard games.count <= 1000 else { games = [:]; return }
        games = games.filter { id, game in
            id == game.discordID && UInt64(id).map { $0 > 0 } == true && (try? game.activity.validate()) != nil
        }
        suspend(at: date)
    }

    public mutating func forget(_ discordID: String) { games.removeValue(forKey: discordID) }
}

public struct FriendAppVisitor: Identifiable, Equatable, Sendable {
    public let friend: SharedMii
    public let activity: SharedAppActivity
    public var id: String { friend.id }

    public func detail(at date: Date = Date()) -> String {
        if activity.active { return activity.source == "discord" ? "Playing now" : "Using now" }
        let minutes = max(0, Int((date.timeIntervalSince1970 - activity.observedAt) / 60))
        let when = minutes == 0 ? "just now" : minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        return (activity.source == "discord" ? "Recently played" : "Recently used") + " · " + when
    }

    public static func gathered(around appID: UUID, apps: [AppIsland], friends: [SharedMii], rendered: Set<UUID>, at date: Date = Date()) -> [Self] {
        friends.compactMap { friend in
            guard rendered.contains(friend.avatar.id),
                  let match = FriendActivityMatcher.match(for: friend.activities, apps: apps, at: date),
                  match.appID == appID else { return nil }
            return Self(friend: friend, activity: match.activity)
        }.sorted {
            if $0.activity.active != $1.activity.active { return $0.activity.active }
            if $0.activity.observedAt != $1.activity.observedAt { return $0.activity.observedAt > $1.activity.observedAt }
            return $0.friend.displayName.localizedStandardCompare($1.friend.displayName) == .orderedAscending
        }
    }
}
