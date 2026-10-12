import Foundation
import DiscordSocialBridge
import PlazaCore

struct DiscordSDKCredentials: Codable {
    var applicationID: String
    var discordID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    func validated() throws -> Self {
        guard let app = UInt64(applicationID), app > 0, let user = UInt64(discordID), user > 0,
              (1...4096).contains(accessToken.count), (1...4096).contains(refreshToken.count),
              expiresAt.isFinite, expiresAt > 0 else { throw PlazaError.invalid("Invalid Discord friends authorization.") }
        return self
    }
}

@MainActor
final class DiscordFriendsClient {
    var onUpdate: (([DiscordFriendRecord], String, Bool) -> Void)?
    private var timer: Timer?
    private var lastRoster: [DiscordFriendRecord] = []
    private var previous: Data?
    func start(_ credentials: DiscordSDKCredentials) throws {
        let credentials = try credentials.validated()
        stop()
        MPDiscordConfigure(UInt64(credentials.applicationID)!, UInt64(credentials.discordID)!, credentials.accessToken)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pump() }
        }
        pump()
    }
    private func pump() {
        MPDiscordPump()
        guard let pointer = MPDiscordCopySnapshot() else { return }
        let data = Data(String(cString: pointer).utf8); MPDiscordFreeString(pointer)
        guard data != previous, data.count < 1_000_000 else { return }; previous = data
        struct Snapshot: Decodable { var state: String; var friends: [DiscordFriendRecord] }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            let ready = snapshot.state == "ready"
            if ready {
                _ = try DiscordFriendRoster.profiles(snapshot.friends, shared: [], unlinked: [])
                lastRoster = snapshot.friends.sorted {
                    if ($0.presence == .offline) != ($1.presence == .offline) { return $1.presence == .offline }
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
            } else {
                lastRoster = lastRoster.map { var friend = $0; friend.presence = .unknown; return friend }
            }
            let message = ready ? "\(lastRoster.count) Discord friends loaded automatically." :
                snapshot.state == "connecting" ? "Connecting to Discord friends…" : "Authorize Discord friends again to reconnect."
            onUpdate?(lastRoster, message, ready)
        } catch {
            onUpdate?([], "Discord friends could not be read. Please reconnect.", false)
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil; previous = nil; lastRoster = []
        MPDiscordDisconnect()
    }
    deinit { timer?.invalidate() }
}
