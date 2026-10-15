import Foundation
import PlazaCore

extension PlazaModel {
    var miiversePopularity: [String: Int] {
        var scores: [String: Int] = [:]
        for entry in recentApps.entries where Date().timeIntervalSince(entry.launched) < 90 * 86400 {
            scores[HomeScreenRotation.key(entry.app), default: 0] += 1
        }
        for friend in social.friends {
            for app in HomeScreenRotation.installedFriendGames(friends: [friend], installed: topicApps) {
                scores[HomeScreenRotation.key(app), default: 0] += 4
            }
        }
        return scores
    }
}
