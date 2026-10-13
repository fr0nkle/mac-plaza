import Foundation
import PlazaCore

/// Bounded local history, scoped to the Discord account and Plaza service.
/// UserDefaults data is not included in portable plaza exports.
@MainActor
final class DiscordGameHistoryStore {
    private let defaults: UserDefaults?
    private var key: String?
    private var history = DiscordGameHistory()
    init(defaults: UserDefaults?) { self.defaults = defaults }

    func useAccount(_ discordID: String?, service: String?) {
        let next = discordID.flatMap { id in service.map { "social.last-games." + $0 + "." + id } }
        guard key != next else { return }
        key = next; history = DiscordGameHistory()
        guard let next, let data = defaults?.data(forKey: next), data.count < 512_000,
              var saved = try? JSONDecoder().decode(DiscordGameHistory.self, from: data) else { return }
        saved.restore(); history = saved; save()
    }

    func update(_ snapshot: DiscordGameSnapshot, friends: [DiscordFriendRecord], at date: Date = Date()) throws -> [DiscordGameRecord] {
        try history.update(snapshot, friends: friends, at: date); save()
        return history.records(at: date)
    }
    func retain(friendIDs: Set<String>, at date: Date = Date()) {
        history.retain(friendIDs: friendIDs, at: date); save()
    }
    func suspend(at date: Date = Date()) -> [DiscordGameRecord] {
        history.suspend(at: date); save(); return history.records(at: date)
    }
    func records(at date: Date = Date()) -> [DiscordGameRecord] {
        let before = history
        history.retain(friendIDs: Set(history.records(at: date).map(\.discordID)), at: date)
        if history != before { save() }
        return history.records(at: date)
    }
    func forget(_ discordID: String) { history.forget(discordID); save() }
    func clear() {
        history = DiscordGameHistory()
        if let key { defaults?.removeObject(forKey: key) }
    }
    private func save() {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard let key, let data = try? encoder.encode(history) else { return }
        guard defaults?.data(forKey: key) != data else { return }
        defaults?.set(data, forKey: key)
    }
}
