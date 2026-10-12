import Foundation

/// Local library references, scoped to the signed-in Discord account. No Mii
/// appearance or friend status is stored here or sent to the sharing service.
@MainActor
final class LocalFriendMiiChoices {
    private let defaults: UserDefaults?
    private var account: String?
    private(set) var choices: [String: UUID] = [:]
    init(defaults: UserDefaults?) { self.defaults = defaults }
    private var key: String? { account.map { "social.friend-miis." + $0 } }

    func useAccount(_ discordID: String?) {
        guard account != discordID else { if discordID == nil { choices = [:] }; return }
        account = discordID; choices = [:]
        guard let key, let stored = defaults?.dictionary(forKey: key), stored.count <= 1000 else { return }
        for (friend, value) in stored {
            guard let number = UInt64(friend), number > 0,
                  let value = value as? String, let id = UUID(uuidString: value) else { continue }
            choices[friend] = id
        }
    }

    func set(_ avatarID: UUID?, for discordID: String) {
        guard let number = UInt64(discordID), number > 0,
              choices[discordID] != nil || choices.count < 1000 else { return }
        choices[discordID] = avatarID
        guard let key else { return } // Sample preview stays in memory.
        defaults?.set(choices.mapValues(\.uuidString), forKey: key)
    }
}
