import Foundation

/// Select a balanced, bounded page; callers supply only validated local apps.
public enum HomeScreenRotation {
    public static func key(_ app: AppIsland) -> String {
        app.steamAppID.map { "steam:\($0)" } ?? "bundle:\(app.bundleID)"
    }

    public static func select<R: RandomNumberGenerator>(recent: [AppIsland], friendGames: [AppIsland],
        fallback: [AppIsland], previous: [String], using random: inout R) -> [AppIsland] {
        func unique(_ apps: [AppIsland]) -> [AppIsland] {
            var seen = Set<String>()
            return apps.filter { seen.insert(key($0)).inserted }
        }
        var recentPool = unique(Array(recent.prefix(24))).shuffled(using: &random)
        var gamesPool = unique(friendGames).shuffled(using: &random)
        var result: [AppIsland] = [], seen = Set<String>()
        func append(from pool: inout [AppIsland]) {
            while !pool.isEmpty {
                let app = pool.removeFirst()
                if seen.insert(key(app)).inserted { result.append(app); return }
            }
        }
        // Alternating reserves space for both sources; either can fill spare slots.
        while result.count < 12 && (!recentPool.isEmpty || !gamesPool.isEmpty) {
            if result.count < 12 { append(from: &recentPool) }
            if result.count < 12 { append(from: &gamesPool) }
        }
        var extras = unique(fallback).shuffled(using: &random)
        while result.count < 12 && !extras.isEmpty { append(from: &extras) }
        if result.count > 1 && result.map(key) == previous {
            result.append(result.removeFirst())
        }
        return result
    }

    public static func installedFriendGames(friends: [SharedMii], installed: [AppIsland],
                                           at date: Date = Date()) -> [AppIsland] {
        var result: [AppIsland] = [], seen = Set<String>()
        for friend in friends {
            for activity in friend.activities where activity.source == "discord" && activity.isRecent(at: date) &&
                (!activity.active || (friend.presence != .offline && friend.presence != .unknown)) {
                guard let id = FriendActivityMatcher.island(for: [activity], apps: installed, at: date),
                      let app = installed.first(where: { $0.id == id }), seen.insert(key(app)).inserted else { continue }
                result.append(app)
            }
        }
        return result
    }
}
