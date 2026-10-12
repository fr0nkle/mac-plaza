import Foundation

public enum FriendPresence: String, Codable, Sendable, CaseIterable {
    case online, idle, dnd, offline, unknown
    public var label: String {
        switch self {
        case .online: return "Online on Discord"
        case .idle: return "Away on Discord"
        case .dnd: return "Do Not Disturb on Discord"
        case .offline: return "Offline on Discord"
        case .unknown: return "Discord status unavailable"
        }
    }
}

public struct SharedMii: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var avatar: Avatar
    public var note: String
    public var presence: FriendPresence
    public var plazaOnline: Bool
    public var activities: [SharedAppActivity] = []
    public var temporaryAvatar: Bool?
    public var locallyAssignedAvatar: Bool?
    public var discordID: String?
    public var customStatus: DiscordCustomStatusRecord?
    public var isPlayingDiscordGame: Bool { activities.contains { $0.source == "discord" && $0.active && $0.isRecent() } }
    public var overheadText: String {
        if let status = customStatus, status.isCurrent, presence != .offline, presence != .unknown { return status.text }
        if let game = activities.first(where: { $0.source == "discord" && $0.active && $0.isRecent() }) { return game.label }
        if !note.isEmpty { return note }
        if let activity = activities.filter({ $0.isRecent() }).sorted(by: {
            if $0.active != $1.active { return $0.active }
            return $0.observedAt > $1.observedAt
        }).first { return activity.label }
        return ""
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, !displayName.isEmpty, displayName.count <= 80,
              note.count <= 280, activities.count <= 2 else { throw PlazaError.invalid("A shared Mii profile is invalid.") }
        _ = try avatar.validated()
        for activity in activities { try activity.validate() }
        try customStatus?.validate()
    }
    public init(id: String, displayName: String, avatar: Avatar, note: String,
                presence: FriendPresence, plazaOnline: Bool) {
        self.id = id; self.displayName = displayName; self.avatar = avatar
        self.note = note; self.presence = presence; self.plazaOnline = plazaOnline
    }
}

public struct SocialAccount: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var avatar: Avatar?
    public var note: String
    public var sharing: Bool
    public var sharePresence: Bool
    public var shareActivity: Bool
    public var shareDiscordFriends: Bool?
}

public struct SharedAppActivity: Codable, Equatable, Sendable {
    public var name: String
    public var bundleID: String?
    public var source: String
    public var active: Bool
    public var observedAt: Double
    public init(name: String, bundleID: String?, source: String, active: Bool, observedAt: Double) {
        self.name = name; self.bundleID = bundleID; self.source = source; self.active = active; self.observedAt = observedAt
    }
    public func validate() throws {
        guard (1...100).contains(name.count), bundleID.map({ (1...250).contains($0.count) }) ?? true,
              ["plaza", "discord"].contains(source), observedAt.isFinite, observedAt >= 0 else {
            throw PlazaError.invalid("A shared application activity is invalid.")
        }
    }
    public var label: String { (active ? (source == "discord" ? "Playing " : "Using ") : (source == "discord" ? "Recently played " : "Recently used ")) + name }
    public func isRecent(at date: Date = Date()) -> Bool {
        let age = date.timeIntervalSince1970 - observedAt
        return age >= -60 && age < 1800
    }
}

public enum FriendActivityMatcher {
    public static func island(for activities: [SharedAppActivity], apps: [AppIsland], at date: Date = Date()) -> UUID? {
        let current = activities.filter { $0.isRecent(at: date) }.sorted {
            if $0.active != $1.active { return $0.active }
            return $0.observedAt > $1.observedAt
        }
        for activity in current {
            if let bundleID = activity.bundleID, let app = apps.first(where: { $0.bundleID == bundleID }) { return app.id }
            let matches = apps.filter { normalized($0.label) == normalized(activity.name) }
            if matches.count == 1 { return matches[0].id }
        }
        return nil
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

public struct FriendRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
}

/// Accepted friends without a published Mii. Availability and activity remain opt-in.
public struct UnlinkedFriend: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var presence: FriendPresence
    public var plazaOnline: Bool
    public var activities: [SharedAppActivity]
    public var discordID: String?
    public var customStatus: DiscordCustomStatusRecord?
    public init(id: String, displayName: String, presence: FriendPresence, plazaOnline: Bool,
                activities: [SharedAppActivity] = []) {
        self.id = id; self.displayName = displayName; self.presence = presence
        self.plazaOnline = plazaOnline; self.activities = activities
    }
}

/// Read-only Discord relationships, fetched directly by the official SDK on this Mac.
public struct DiscordFriendRecord: Codable, Equatable, Sendable {
    public var discordID: String
    public var displayName: String
    public var presence: FriendPresence
    public init(discordID: String, displayName: String, presence: FriendPresence) {
        self.discordID = discordID; self.displayName = displayName; self.presence = presence
    }
    public func plazaProfile() throws -> UnlinkedFriend {
        guard let number = UInt64(discordID), number > 0, (1...80).contains(displayName.count) else {
            throw PlazaError.invalid("Discord returned an invalid friend profile.")
        }
        let hex = String(format: "%016llx", number)
        var profile = UnlinkedFriend(id: "D15C0AD0-0000-4000-\(hex.prefix(4))-\(hex.suffix(12))",
                                     displayName: displayName, presence: presence, plazaOnline: false)
        profile.discordID = discordID
        return profile
    }
}

public struct DiscordGameRecord: Codable, Equatable, Sendable {
    public var discordID: String
    public var name: String
    public var observedAt: Double
    public init(discordID: String, name: String, observedAt: Double) {
        self.discordID = discordID; self.name = name; self.observedAt = observedAt
    }
    public var activity: SharedAppActivity {
        SharedAppActivity(name: name, bundleID: nil, source: "discord", active: true, observedAt: observedAt)
    }
}

public struct DiscordCustomStatusRecord: Codable, Equatable, Sendable {
    public var discordID: String
    public var text: String
    public var observedAt: Double
    public init(discordID: String, text: String, observedAt: Double) {
        self.discordID = discordID; self.text = text; self.observedAt = observedAt
    }
    public var isCurrent: Bool {
        let age = Date().timeIntervalSince1970 - observedAt
        return age >= -60 && age < 90
    }
    public func validate() throws {
        guard let id = UInt64(discordID), id > 0, (1...280).contains(text.count),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              observedAt.isFinite, observedAt >= 0 else {
            throw PlazaError.invalid("Invalid Discord custom status.")
        }
    }
}

public struct DiscordGameSnapshot: Codable, Sendable {
    public var state: String
    public var coveredDiscordIDs: [String]
    public var games: [DiscordGameRecord]
    public var customStatuses: [DiscordCustomStatusRecord]
    public init(state: String, coveredDiscordIDs: [String], games: [DiscordGameRecord], customStatuses: [DiscordCustomStatusRecord] = []) {
        self.state = state; self.coveredDiscordIDs = coveredDiscordIDs; self.games = games; self.customStatuses = customStatuses
    }
    enum CodingKeys: String, CodingKey { case state, coveredDiscordIDs, games, customStatuses }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        state = try values.decode(String.self, forKey: .state)
        coveredDiscordIDs = try values.decode([String].self, forKey: .coveredDiscordIDs)
        games = try values.decode([DiscordGameRecord].self, forKey: .games)
        customStatuses = try values.decodeIfPresent([DiscordCustomStatusRecord].self, forKey: .customStatuses) ?? []
    }
    public func validated(friends: [DiscordFriendRecord]) throws -> Self {
        let allowed = Set(friends.map(\.discordID)), covered = Set(coveredDiscordIDs)
        guard ["ready", "not-configured", "unavailable"].contains(state),
              coveredDiscordIDs.count <= 1000, covered.count == coveredDiscordIDs.count,
              covered.isSubset(of: allowed), games.count <= covered.count,
              Set(games.map(\.discordID)).count == games.count,
              games.allSatisfy({ covered.contains($0.discordID) }),
              customStatuses.count <= covered.count,
              Set(customStatuses.map(\.discordID)).count == customStatuses.count,
              customStatuses.allSatisfy({ covered.contains($0.discordID) }),
              state == "ready" || (games.isEmpty && covered.isEmpty && customStatuses.isEmpty) else {
            throw PlazaError.invalid("Invalid Discord game activity response.")
        }
        for game in games { try game.activity.validate() }
        for status in customStatuses { try status.validate() }
        return self
    }
}

public enum DiscordFriendRoster {
    /// The actual Discord friend list controls membership. Published Plaza data can
    /// improve a friend's appearance only when the service already authorizes it.
    public static func profiles(_ records: [DiscordFriendRecord], shared: [SharedMii], unlinked: [UnlinkedFriend], games: [DiscordGameRecord] = [], customStatuses: [DiscordCustomStatusRecord] = []) throws -> (shared: [SharedMii], unlinked: [UnlinkedFriend]) {
        guard records.count <= 1000, Set(records.map(\.discordID)).count == records.count else {
            throw PlazaError.invalid("Discord returned an excessive or duplicate friend list.")
        }
        _ = try DiscordGameSnapshot(state: "ready", coveredDiscordIDs: Array(Set(games.map(\.discordID) + customStatuses.map(\.discordID))), games: games, customStatuses: customStatuses).validated(friends: records)
        let currentGames = Dictionary(uniqueKeysWithValues: games.filter { $0.activity.isRecent() }.map { ($0.discordID, $0.activity) })
        let statuses = Dictionary(uniqueKeysWithValues: customStatuses.filter(\.isCurrent).map { ($0.discordID, $0) })
        func status(for record: DiscordFriendRecord) -> DiscordCustomStatusRecord? {
            record.presence == .offline || record.presence == .unknown ? nil : statuses[record.discordID]
        }
        func activities(_ existing: [SharedAppActivity], for record: DiscordFriendRecord) -> [SharedAppActivity] {
            guard record.presence != .offline, record.presence != .unknown,
                  let game = currentGames[record.discordID] else { return existing }
            return [game] + existing.filter { $0.source != "discord" }.prefix(1)
        }
        var chosen: [SharedMii] = [], temporary: [UnlinkedFriend] = []
        for record in records {
            let fallback = try record.plazaProfile()
            if var mii = shared.first(where: { $0.discordID == record.discordID }) {
                mii.presence = record.presence
                mii.activities = activities(mii.activities, for: record)
                mii.customStatus = status(for: record)
                chosen.append(mii)
            } else {
                var profile = unlinked.first(where: { $0.discordID == record.discordID }) ?? fallback
                profile.presence = record.presence
                profile.activities = activities(profile.activities, for: record)
                profile.customStatus = status(for: record)
                temporary.append(profile)
            }
        }
        return (chosen, temporary)
    }
}

/// Local, session-only appearances; never saved to the account or portable Plaza.
public struct FriendMiiAssignments {
    private var avatars: [String: Avatar] = [:]
    public init() {}
    public mutating func reset() { avatars = [:] }
    /// Reserve friend slots for explicit local Mii choices before filling the
    /// remaining crowd. Preserve roster order within each group across refreshes.
    public static func plazaFriends(_ friends: [SharedMii], capacity: Int) -> [SharedMii] {
        guard capacity > 0 else { return [] }
        return Array(prioritizedFriends(friends).prefix(capacity))
    }
    /// Use the same stable priority for full friend lists and the bounded crowd.
    public static func prioritizedFriends(_ friends: [SharedMii]) -> [SharedMii] {
        let prioritized = friends.filter { $0.locallyAssignedAvatar == true }
        let remaining = friends.filter { $0.locallyAssignedAvatar != true }
        return prioritized + remaining
    }
    public mutating func resolve(shared: [SharedMii], unlinked: [UnlinkedFriend], localAppearances: [String: Avatar] = [:]) -> [SharedMii] {
        let accepted = Set(shared.map(\.id) + unlinked.map(\.id))
        avatars = avatars.filter { accepted.contains($0.key) }
        return shared + unlinked.map { friend in
            let fallback = avatars[friend.id] ?? Self.randomAvatar()
            avatars[friend.id] = fallback
            let selected = friend.discordID.flatMap { localAppearances[$0] }
            var avatar = selected ?? fallback
            // A library Mii can represent several friends and still exist in the
            // local plaza. Each friend keeps their own stable walker identity.
            avatar.id = fallback.id
            let name = friend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            avatar.name = name.isEmpty ? "Friend" : String(name.prefix(24))
            var mii = SharedMii(id: friend.id, displayName: friend.displayName, avatar: avatar,
                                note: "", presence: friend.presence, plazaOnline: friend.plazaOnline)
            mii.activities = friend.activities; mii.temporaryAvatar = true
            mii.locallyAssignedAvatar = selected != nil
            mii.discordID = friend.discordID
            mii.customStatus = friend.customStatus
            return mii
        }
    }
    private static func randomAvatar() -> Avatar {
        var avatar = Avatar(outfit: Int.random(in: 0...11))
        avatar.skin = Int.random(in: 0...5); avatar.hair = Int.random(in: 0...131)
        avatar.hairColor = Int.random(in: 0...7); avatar.eyes = Int.random(in: 0...59)
        avatar.brows = Int.random(in: 0...23); avatar.nose = Int.random(in: 0...17)
        avatar.mouth = Int.random(in: 0...35); avatar.face = Int.random(in: 0...11)
        avatar.height = Double.random(in: 0.3...0.8); avatar.build = Double.random(in: 0.25...0.75)
        avatar.glasses = Int.random(in: 0..<5) == 0
        avatar.features.gender = Int.random(in: 0...1)
        avatar.features.browColor = avatar.hairColor
        avatar.features.eyeColor = Int.random(in: 0...5)
        return avatar
    }
}

public struct SocialSnapshot: Codable, Equatable, Sendable {
    public var account: SocialAccount
    public var friends: [SharedMii]
    public var contacts: [FriendRequest]
    public var incoming: [FriendRequest]
    public var outgoing: [FriendRequest]
    // Optional for compatibility with services and clients from the first release.
    public var unlinkedFriends: [UnlinkedFriend]?
    public func validated() throws -> SocialSnapshot {
        let unlinked = unlinkedFriends ?? []
        let ids = friends.map(\.id) + unlinked.map(\.id)
        guard UUID(uuidString: account.id) != nil, (1...80).contains(account.displayName.count),
              account.note.count <= 280, ids.count <= 1100, unlinked.count <= 100,
              contacts.count <= 100, incoming.count <= 100, outgoing.count <= 100,
              Set(ids).count == ids.count,
              Set(friends.map { $0.avatar.id }).count == friends.count,
              (contacts + incoming + outgoing).allSatisfy({ UUID(uuidString: $0.id) != nil && (1...80).contains($0.displayName.count) })
        else { throw PlazaError.invalid("The social service returned invalid or excessive records.") }
        if let avatar = account.avatar { _ = try avatar.validated() }
        for friend in friends { try friend.validate() }
        for friend in unlinked {
            guard UUID(uuidString: friend.id) != nil, (1...80).contains(friend.displayName.count),
                  friend.activities.count <= 2 else { throw PlazaError.invalid("An unlinked friend profile is invalid.") }
            for activity in friend.activities { try activity.validate() }
            try friend.customStatus?.validate()
        }
        return self
    }
}

public enum SocialEndpoint {
    /// Production must use TLS; plaintext is allowed only on the local development host.
    public static func validated(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)),
              let url = parts.url else {
            throw PlazaError.invalid("Use an HTTPS service address, or http://127.0.0.1:8787 for local development.")
        }
        return url
    }
}
