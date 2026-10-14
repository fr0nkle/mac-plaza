import AppKit
import AuthenticationServices
import CryptoKit
import Security
import SwiftUI
import PlazaCore

private final class SocialRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum SocialKeychain {
    static func query(_ endpoint: URL, purpose: String = "session") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: purpose == "session" ? "local.macplaza.social" : "local.macplaza.social." + purpose,
         kSecAttrAccount as String: endpoint.absoluteString]
    }
    static func read(_ endpoint: URL, purpose: String = "session") -> String? {
        var q = query(endpoint, purpose: purpose); q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, endpoint: URL, purpose: String = "session") throws {
        let q = query(endpoint, purpose: purpose)
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            var item = q; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw PlazaError.invalid("Could not save the Plaza session in Keychain.")
            }
        } else if updated != errSecSuccess { throw PlazaError.invalid("Could not update the Plaza session in Keychain.") }
    }
    static func remove(_ endpoint: URL, purpose: String = "session") { SecItemDelete(query(endpoint, purpose: purpose) as CFDictionary) }
}

@MainActor
final class SocialController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var snapshot: SocialSnapshot?
    @Published private(set) var friends: [SharedMii] = []
    @Published private(set) var sharedJournal: [SharedJournalNote] = []
    var visibleSharedJournal: [SharedJournalNote] { sharedJournal.filter { !hiddenIDs.contains($0.ownerID ?? "") } }
    @Published private(set) var journalSyncMessage = "Public notes will sync when connected to Plaza."
    @Published private(set) var activity: [JournalActivity] = []
    @Published private(set) var unreadActivityCount = 0
    @Published private(set) var activityAlert: JournalActivity?
    @Published private(set) var activityMessage: String?
    @Published private(set) var markingActivityRead = false
    @Published private(set) var systemNotificationsEnabled = false
    var activityPreviewsAllowed = false { didSet { activityNotifications.previewsAllowed = activityPreviewsAllowed } }
    var onActivityChanged: (() -> Void)?
    var onActivitySelected: ((JournalActivity) -> Void)?
    private let activityNotifications = PlazaActivityNotifications()
    private var activityDelivery = JournalActivityDelivery()
    private var activityScope: String?
    private var activityFetchSequence = 0
    private var activityAppliedSequence = 0
    private var activityAlertTask: Task<Void, Never>?
    private var pendingActivityNotification: (Int, String)?
    @Published private(set) var interactingNotes = Set<UUID>()
    @Published private(set) var journalInteractionMessage: String?
    private var journalFetchSequence = 0
    private var journalAppliedSequence = 0
    private var localJournal: [SharedJournalNote] = []
    private var localJournalPrimary: Avatar?
    private var uploadedJournalPrimary: Avatar?
    private var journalReady = false
    private var uploadedJournal: [SharedJournalNote]?
    private var syncingJournal = false
    private var journalSyncTask: Task<Void, Never>?
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var previewing = false
    @Published private(set) var message = "Connect Discord to see your friends’ Miis and availability."
    @Published private(set) var discordFriendsMessage = "Load your Discord friends to see their Miis automatically."
    @Published private(set) var hasDiscordFriendsAuthorization = false
    @Published private(set) var discordSharingMessage = "Choose a Mii and enable sharing to link it to your Discord account."
    private var audienceRefreshedAt: Date?
    private var audienceRefreshing = false
    private var lastAudience: Set<String> = []
    private var discordCredentials: DiscordSDKCredentials?
    private var discordRecords: [DiscordFriendRecord] = []
    @Published private(set) var discordGamesMessage = "Custom statuses and games are available for friends in a shared bot server."
    @Published private(set) var showDiscordGames = true
    private var discordGames: [DiscordGameRecord] = []
    private var discordCustomStatuses: [DiscordCustomStatusRecord] = []
    private var discordReady = false
    private var gamesRefreshing = false
    private var gamesRefreshedAt: Date?
    private var discordRefreshing = false
    private let discordClient = DiscordFriendsClient()
    @Published private(set) var inviteCode = ""
    @Published private(set) var blocks: [FriendRequest] = []
    @Published var serverAddress: String
    var onRosterChanged: (() -> Void)?
    weak var window: NSWindow?
    private var endpoint: URL?
    private var token: String?
    private var auth: ASWebAuthenticationSession?
    private var polling: Task<Void, Never>?
    private var epoch = 0
    private var active = true
    private var activityEligible = true
    private var refreshedAt: Date?
    private var refreshing = false
    private var mutationRevision = 0
    private let isolated: Bool
    private let network: URLSession
    private var hiddenIDs = Set<String>()
    private var miiAssignments = FriendMiiAssignments()
    private let localMiiChoices: LocalFriendMiiChoices
    private let gameHistory: DiscordGameHistoryStore
    private var gameExpiryTimer: Timer?
    private var localMiis: [Avatar] = []
    private var hiddenKey: String { "social.hidden." + (endpoint?.absoluteString ?? "") }
    var contacts: [FriendRequest] { snapshot?.contacts ?? [] }
    var hasSession: Bool { token != nil }
    var account: SocialAccount? { snapshot?.account }
    var botInstallURL: URL? {
        guard let appID = discordCredentials?.applicationID else { return nil }
        return URL(string: "https://discord.com/oauth2/authorize?client_id=\(appID)&scope=bot&permissions=0&integration_type=0")
    }
    var linkedAvatarID: UUID? {
        guard !isolated, let account, let endpoint,
              let value = UserDefaults.standard.string(forKey: "social.avatar." + endpoint.absoluteString + account.id) else { return nil }
        return UUID(uuidString: value)
    }

    init(isolated: Bool = false) {
        self.isolated = isolated
        localMiiChoices = LocalFriendMiiChoices(defaults: isolated ? nil : .standard)
        gameHistory = DiscordGameHistoryStore(defaults: isolated ? nil : .standard)
        serverAddress = isolated ? "" : SocialEndpoint.initialAddress(
            saved: UserDefaults.standard.string(forKey: "social.service"),
            bundled: Bundle.main.object(forInfoDictionaryKey: "PlazaServiceURL") as? String,
            retired: Bundle.main.object(forInfoDictionaryKey: "PlazaRetiredServiceURLs") as? [String] ?? [])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        network = URLSession(configuration: config, delegate: SocialRedirectBlocker(), delegateQueue: nil)
        super.init()
        activityNotifications.onOpen = { [weak self] id, scope in
            guard let self else { return }
            self.pendingActivityNotification = (id, scope)
            Task { await self.refreshActivity() }
        }
        Task { [weak self] in
            guard let self else { return }
            self.systemNotificationsEnabled = await self.activityNotifications.isEnabled()
        }
        if !isolated {
            gameExpiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.expireRememberedGames() }
            }
        }
        discordClient.onUpdate = { [weak self] records, status, ready in
            guard let self, self.hasDiscordFriendsAuthorization else { return }
            self.discordRecords = records; self.discordFriendsMessage = status; self.discordReady = ready
            let ids = Set(records.map(\.discordID))
            if ready { self.gameHistory.retain(friendIDs: ids) }
            self.discordGames = self.showDiscordGames ? (ready ? self.gameHistory.records() : self.gameHistory.suspend()) : []
            self.discordCustomStatuses = ready ? self.discordCustomStatuses.filter { ids.contains($0.discordID) } : []
            self.rebuildFriends()
            if ready { Task { await self.syncDiscordRecipients(); await self.refreshDiscordGames() } }
        }
        if !serverAddress.isEmpty { configure() }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? NSApp.keyWindow ?? ASPresentationAnchor()
    }

    func changeService() {
        reset(); endpoint = nil
        message = "Enter the new service address, then connect Discord."
    }

    func configure() {
        do {
            let url = try SocialEndpoint.validated(serverAddress)
            reset()
            endpoint = url; serverAddress = url.absoluteString
            showDiscordGames = isolated ? true : UserDefaults.standard.object(forKey: "social.discord-games." + url.absoluteString) as? Bool ?? true
            if !isolated { UserDefaults.standard.set(serverAddress, forKey: "social.service") }
            hiddenIDs = isolated ? [] : Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
            token = isolated ? nil : SocialKeychain.read(url)
            if !isolated { PlazaUpdater.shared.configure(endpoint: url, token: token) }
            message = token == nil ? "Service ready. Connect Discord to continue." : "Reconnecting to Plaza…"
            if token != nil {
                if !isolated, let stored = SocialKeychain.read(url, purpose: "discord-friends"),
                   let data = stored.data(using: .utf8), let credentials = try? JSONDecoder().decode(DiscordSDKCredentials.self, from: data).validated() {
                    discordCredentials = credentials; hasDiscordFriendsAuthorization = true
                    localMiiChoices.useAccount(credentials.discordID)
                    gameHistory.useAccount(credentials.discordID, service: url.absoluteString)
                    if !showDiscordGames { gameHistory.clear() }
                    if credentials.expiresAt > Date().timeIntervalSince1970 + 120 { try discordClient.start(credentials) }
                }
                startPolling()
            }
        } catch { message = error.localizedDescription }
    }

    private func reset() {
        epoch += 1; auth?.cancel(); auth = nil; polling?.cancel(); polling = nil
        discordClient.stop(); discordCredentials = nil; discordRecords = []; hasDiscordFriendsAuthorization = false
        discordReady = false; discordGames = []; gamesRefreshing = false; gamesRefreshedAt = nil
        discordCustomStatuses = []
        discordGamesMessage = "Custom statuses and games are available for friends in a shared bot server."
        discordRefreshing = false; discordFriendsMessage = "Load your Discord friends to see their Miis automatically."
        token = nil; connected = false; snapshot = nil; friends = []; blocks = []
        sharedJournal = []; uploadedJournal = nil; journalSyncTask?.cancel(); journalSyncTask = nil
        uploadedJournalPrimary = nil
        interactingNotes = []; journalInteractionMessage = nil; journalFetchSequence = 0; journalAppliedSequence = 0
        activity = []; unreadActivityCount = 0; activityAlert = nil; activityAlertTask?.cancel()
        activityScope = nil; activityDelivery = JournalActivityDelivery(); activityFetchSequence = 0; activityAppliedSequence = 0
        activityMessage = nil; markingActivityRead = false
        if !isolated { activityNotifications.setState(unreadIDs: [], scope: nil, count: 0); Task { await activityNotifications.reconcile() } }
        onActivityChanged?()
        audienceRefreshedAt = nil; audienceRefreshing = false; lastAudience = []
        if !isolated { PlazaUpdater.shared.configure(endpoint: nil, token: nil) }
        miiAssignments.reset()
        localMiiChoices.useAccount(nil)
        gameHistory.useAccount(nil, service: nil)
        previewing = false; busy = false; refreshing = false; inviteCode = ""; refreshedAt = nil
        onRosterChanged?()
    }

    private func request(_ method: String, _ path: String, body: Any? = nil, authenticated: Bool = true) async throws -> Data {
        guard let endpoint else { throw PlazaError.invalid("Set the Plaza service address first.") }
        var req = URLRequest(url: endpoint.appendingPathComponent(path))
        req.httpMethod = method; req.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let token else { throw PlazaError.invalid("Connect Discord first.") }
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        }
        let generation = epoch
        let (data, response) = try await network.data(for: req)
        guard generation == epoch, !Task.isCancelled else { throw CancellationError() }
        guard data.count <= 4_000_000, let http = response as? HTTPURLResponse else {
            throw PlazaError.invalid("Invalid Plaza service response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if http.statusCode == 401 && authenticated {
                SocialKeychain.remove(endpoint); SocialKeychain.remove(endpoint, purpose: "discord-friends"); reset()
            }
            throw PlazaError.invalid(String((object?["error"] as? String ?? "The Plaza service is unavailable.").prefix(300)))
        }
        return data
    }

    func connect() {
        guard !busy else { return }
        do {
            let desired = try SocialEndpoint.validated(serverAddress)
            if endpoint != desired { configure() }
        } catch { message = error.localizedDescription; return }
        guard endpoint != nil else { return }
        busy = true; let generation = epoch
        Task {
            do {
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                    throw PlazaError.invalid("Could not create a secure sign-in request.")
                }
                let verifier = Self.base64url(Data(bytes))
                let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
                struct Start: Decodable { var state: String; var authorizeURL: URL }
                let start = try JSONDecoder().decode(Start.self, from: await request("POST", "v1/auth/start", body: ["challenge": challenge, "friendDiscovery": true], authenticated: false))
                guard start.authorizeURL.scheme == "https", start.authorizeURL.host == "discord.com",
                      start.authorizeURL.path == "/oauth2/authorize" else { throw PlazaError.invalid("Invalid Discord sign-in URL.") }
                let callback = try await authorize(start.authorizeURL)
                guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                      parts.scheme == "macplaza", parts.host == "discord-linked",
                      parts.queryItems?.filter({ $0.name == "state" }).count == 1,
                      parts.queryItems?.first(where: { $0.name == "state" })?.value == start.state else {
                    throw PlazaError.invalid("Discord sign-in could not be verified.")
                }
                struct Finish: Decodable { var token: String; var discordSDK: DiscordSDKCredentials? }
                let result = try JSONDecoder().decode(Finish.self, from: await request("POST", "v1/auth/finish", body: ["state": start.state, "verifier": verifier], authenticated: false))
                guard generation == epoch, let endpoint, result.token.count <= 128 else { throw CancellationError() }
                if !isolated { try SocialKeychain.save(result.token, endpoint: endpoint) }
                discordClient.stop(); discordRecords = []; discordCredentials = nil; hasDiscordFriendsAuthorization = false
                miiAssignments.reset()
                token = result.token; previewing = false
                if !isolated { PlazaUpdater.shared.configure(endpoint: endpoint, token: token) }
                if let credentials = result.discordSDK { try activateDiscord(credentials) }
                else { discordFriendsMessage = "Update the Plaza service to enable automatic Discord friends." }
                busy = false; startPolling()
            } catch is CancellationError { }
            catch { if generation == epoch { message = error.localizedDescription } }
            if generation == epoch { busy = false; auth = nil }
        }
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func authorize(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "macplaza") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? PlazaError.invalid("Discord sign-in was cancelled.")) }
            }
            auth = session; session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() { auth = nil; continuation.resume(throwing: PlazaError.invalid("Could not open Discord sign-in.")) }
        }
    }

    private func apply(_ data: Data) throws {
        let next = try JSONDecoder().decode(SocialSnapshot.self, from: data).validated()
        snapshot = next; connected = true; refreshedAt = Date()
        message = "Connected as \(next.account.displayName)"
        rebuildFriends()
    }

    private func activateDiscord(_ credentials: DiscordSDKCredentials) throws {
        let credentials = try credentials.validated()
        if !isolated, let endpoint {
            let data = try JSONEncoder().encode(credentials)
            try SocialKeychain.save(String(decoding: data, as: UTF8.self), endpoint: endpoint, purpose: "discord-friends")
        }
        discordCredentials = credentials; hasDiscordFriendsAuthorization = true
        localMiiChoices.useAccount(credentials.discordID)
        gameHistory.useAccount(credentials.discordID, service: endpoint?.absoluteString)
        if !showDiscordGames { gameHistory.clear() }
        try discordClient.start(credentials)
    }

    private func refreshDiscordAuthorization() async {
        guard !discordRefreshing, let credentials = discordCredentials,
              credentials.expiresAt < Date().timeIntervalSince1970 + 120 else { return }
        discordRefreshing = true; let generation = epoch
        defer { if generation == epoch { discordRefreshing = false } }
        do {
            let data = try await request("POST", "v1/discord/refresh", body: ["refreshToken": credentials.refreshToken])
            let renewed = try JSONDecoder().decode(DiscordSDKCredentials.self, from: data).validated()
            guard renewed.discordID == credentials.discordID, renewed.applicationID == credentials.applicationID else {
                throw PlazaError.invalid("Discord friends authorization does not match your account.")
            }
            try activateDiscord(renewed)
        } catch {
            guard generation == epoch else { return }
            discordClient.stop(); discordRecords = discordRecords.map { var f = $0; f.presence = .unknown; return f }
            discordFriendsMessage = "Reconnect Discord to renew friends access."
            rebuildFriends()
        }
    }

    func setDiscordGamesEnabled(_ enabled: Bool) {
        showDiscordGames = enabled
        if !enabled { gameHistory.clear() }
        if !isolated, let endpoint { UserDefaults.standard.set(enabled, forKey: "social.discord-games." + endpoint.absoluteString) }
        discordGames = []; discordCustomStatuses = []; gamesRefreshedAt = nil; rebuildFriends()
        if enabled { Task { await refreshDiscordGames() } }
        else { discordGamesMessage = "Discord custom statuses and game activity are hidden on this Mac." }
    }

    private func syncDiscordRecipients() async {
        guard discordReady, hasDiscordFriendsAuthorization,
              (!localJournal.isEmpty || (account?.sharing == true && account?.shareDiscordFriends == true)),
              !audienceRefreshing, !busy else { return }
        let recipients = Set(discordRecords.map(\.discordID))
        if recipients == lastAudience, let date = audienceRefreshedAt, Date().timeIntervalSince(date) < 300 { return }
        audienceRefreshing = true; let generation = epoch
        defer { if epoch == generation { audienceRefreshing = false } }
        do {
            _ = try await request("PUT", "v1/discord/recipients", body: ["discordIDs": Array(recipients)])
            guard generation == epoch else { return }
            lastAudience = recipients; audienceRefreshedAt = Date()
            discordSharingMessage = "Your public notes and enabled profile sharing use \(recipients.count) authorized Discord friends. No Plaza invitations needed."
        } catch {
            guard generation == epoch else { return }
            discordSharingMessage = "Mii sharing could not sync. Check the service connection and try Refresh."
        }
    }

    private func refreshDiscordGames() async {
        guard showDiscordGames, discordReady, hasDiscordFriendsAuthorization, token != nil,
              !gamesRefreshing, !previewing, !busy else { return }
        if let date = gamesRefreshedAt, Date().timeIntervalSince(date) < 5 { return }
        let records = gameFriendRecords
        let ids = Set(records.map(\.discordID))
        guard !ids.isEmpty else { gameHistory.clear(); discordGames = []; discordCustomStatuses = []; return }
        gamesRefreshing = true; let generation = epoch
        defer { if epoch == generation { gamesRefreshing = false } }
        do {
            let data = try await request("POST", "v1/discord/games", body: ["discordIDs": records.map(\.discordID)])
            let result = try JSONDecoder().decode(DiscordGameSnapshot.self, from: data).validated(friends: records)
            guard generation == epoch, showDiscordGames, ids == Set(gameFriendRecords.map(\.discordID)) else { return }
            discordGames = try gameHistory.update(result, friends: records); gamesRefreshedAt = Date()
            discordCustomStatuses = result.customStatuses
            if result.state == "ready" {
                let playing = discordGames.filter(\.active).count
                let recent = discordGames.count - playing
                discordGamesMessage = "\(result.customStatuses.count) custom statuses · \(playing) playing · \(recent) recently played · \(result.coveredDiscordIDs.count) friends visible in shared bot servers."
            } else {
                discordGamesMessage = result.state == "not-configured" ? "Install the Plaza bot in a shared server to see custom statuses and games." : "The Discord presence bot is offline; remembered games remain for up to two hours."
            }
            rebuildFriends()
        } catch {
            guard generation == epoch else { return }
            discordGames = showDiscordGames ? gameHistory.suspend() : []; discordCustomStatuses = []; gamesRefreshedAt = Date()
            discordGamesMessage = "Live Discord activity is unavailable. Remembered games remain for up to two hours."
            rebuildFriends()
        }
    }

    private var gameFriendRecords: [DiscordFriendRecord] {
        discordRecords.filter { record in
            let fallbackID = try? record.plazaProfile().id
            let sharedID = snapshot?.friends.first { $0.discordID == record.discordID }?.id
            let unlinkedID = snapshot?.unlinkedFriends?.first { $0.discordID == record.discordID }?.id
            return ![fallbackID, sharedID, unlinkedID].compactMap { $0 }.contains { hiddenIDs.contains($0) }
        }
    }

    private func expireRememberedGames() {
        guard showDiscordGames, hasDiscordFriendsAuthorization, !previewing else { return }
        let recent = gameHistory.records()
        guard recent != discordGames else { return }
        discordGames = recent
        rebuildFriends()
    }

    func setJournal(notes: [LocalNote], apps: [AppIsland], primary: Avatar) {
        var primary = primary
        primary.features.creator = ""; primary.features.birthDay = 0; primary.features.birthMonth = 0
        let next = SharedJournalNote.publishing(notes: notes, apps: apps, primary: primary)
        guard next != localJournal || primary != localJournalPrimary || !journalReady else { return }
        localJournalPrimary = primary
        journalReady = true; localJournal = next
        journalSyncMessage = "Public notes are queued for sync."
        journalSyncTask?.cancel()
        journalSyncTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            await self?.syncJournal()
        }
    }

    private func syncJournal() async {
        guard journalReady, connected, token != nil, !previewing, !syncingJournal else { return }
        syncingJournal = true
        let generation = epoch
        defer { syncingJournal = false }
        do {
            // Serialize replacements so a late response cannot restore a deleted
            // note. Changes made during an upload are sent in the same loop.
            while uploadedJournal != localJournal || uploadedJournalPrimary != localJournalPrimary {
                let notes = localJournal
                let primary = localJournalPrimary
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(notes))
                var body: [String: Any] = ["notes": object]
                if let primary { body["primaryAvatar"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(primary)) }
                _ = try await request("PUT", "v1/notes", body: body)
                guard generation == epoch else { return }
                uploadedJournal = notes
                uploadedJournalPrimary = primary
            }
            await syncDiscordRecipients()
            try await reloadJournal()
            journalSyncMessage = "Public notes are shared with your Plaza friends."
        } catch {
            guard generation == epoch else { return }
            sharedJournal = []
            journalSyncMessage = "Notes are saved on this Mac; sharing is pending. " + error.localizedDescription
            onRosterChanged?()
        }
    }

    private func reloadJournal() async throws {
        journalFetchSequence += 1
        let sequence = journalFetchSequence, generation = epoch
        let data = try await request("GET", "v1/notes/threads")
        let next = try JSONDecoder().decode(SharedJournalSnapshot.self, from: data).validated().notes
        guard generation == epoch, sequence >= journalAppliedSequence else { return }
        journalAppliedSequence = sequence
        if sharedJournal != next { sharedJournal = next; rebuildFriends(notify: false); onRosterChanged?() }
    }

    private func interact(noteID: UUID, method: String, action: String, body: Any? = nil) async -> Bool {
        guard connected, token != nil, !previewing else {
            journalInteractionMessage = "Connect to Plaza to share a reply or like."; return false
        }
        guard interactingNotes.insert(noteID).inserted else { return false }
        let generation = epoch
        journalInteractionMessage = nil
        defer { if generation == epoch { interactingNotes.remove(noteID) } }
        do {
            _ = try await request(method, "v1/notes/" + noteID.uuidString + "/" + action, body: body)
            // A committed mutation is successful even if the subsequent read
            // fails. Do not encourage duplicate replies after a lost refresh.
            do { try await reloadJournal() }
            catch { journalSyncMessage = "Your interaction was saved. Refreshing the thread is pending." }
            return generation == epoch
        } catch {
            if generation == epoch { journalInteractionMessage = error.localizedDescription }
            return false
        }
    }

    func like(noteID: UUID, liked: Bool) async -> Bool {
        await interact(noteID: noteID, method: "PUT", action: "like", body: ["liked": liked])
    }
    func reply(noteID: UUID, replyID: UUID, author: Avatar, text: String) async -> Bool {
        do {
            _ = try author.validated()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 280 else {
                throw PlazaError.invalid("Write a reply of up to 280 characters.")
            }
            var appearance = author
            appearance.features.creator = ""; appearance.features.birthDay = 0; appearance.features.birthMonth = 0
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance))
            return await interact(noteID: noteID, method: "PUT", action: "replies/" + replyID.uuidString,
                                  body: ["author": object, "text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
        } catch { journalInteractionMessage = error.localizedDescription; return false }
    }
    func deleteReply(noteID: UUID, replyID: UUID) async -> Bool {
        await interact(noteID: noteID, method: "DELETE", action: "replies/" + replyID.uuidString)
    }

    private var currentActivityScope: String? {
        guard let endpoint, let account else { return nil }
        return SHA256.hash(data: Data((endpoint.absoluteString + "|" + account.id).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func applyActivity(_ data: Data, sequence: Int) throws {
        let snapshot = try JSONDecoder().decode(JournalActivitySnapshot.self, from: data).validated()
        guard sequence >= activityAppliedSequence, let scope = currentActivityScope else { return }
        activityAppliedSequence = sequence
        if activityScope != scope {
            activityScope = scope
            let value = isolated ? nil : UserDefaults.standard.object(forKey: "activity.delivered." + scope) as? Int
            activityDelivery = JournalActivityDelivery(deliveredThrough: value)
        }
        let fresh = activityDelivery.newUnread(in: snapshot)
        if !isolated, let cursor = activityDelivery.deliveredThrough { UserDefaults.standard.set(cursor, forKey: "activity.delivered." + scope) }
        activity = snapshot.activities; unreadActivityCount = snapshot.unreadCount
        if !isolated { activityNotifications.setState(unreadIDs: Set(activity.filter { !$0.read }.map(\.id)), scope: scope, count: unreadActivityCount) }
        activityMessage = nil
        if let alert = activityAlert, !activity.contains(where: { $0.id == alert.id && !$0.read }) { dismissActivityAlert() }
        if let latest = fresh.last {
            activityAlertTask?.cancel(); activityAlert = latest
            activityAlertTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                self?.dismissActivityAlert()
            }
            if !isolated { Task { await activityNotifications.deliver(latest, scope: scope, additional: fresh.count - 1) } }
        }
        if !isolated {
            Task { await activityNotifications.reconcile() }
        }
        onActivityChanged?()
        if let pending = pendingActivityNotification {
            pendingActivityNotification = nil
            if pending.1 == scope, let entry = activity.first(where: { $0.id == pending.0 }) { openActivity(entry) }
        }
    }
    func refreshActivity() async {
        guard token != nil, !previewing else { return }
        activityFetchSequence += 1
        let sequence = activityFetchSequence, generation = epoch
        do {
            let data = try await request("GET", "v1/notes/activity")
            guard generation == epoch else { return }
            try applyActivity(data, sequence: sequence)
        } catch {
            guard generation == epoch else { return }
            activityMessage = "Activity will refresh when the Plaza service is available."
            onActivityChanged?()
        }
    }
    func markActivityRead(_ ids: [Int]) async {
        guard token != nil, !markingActivityRead, !ids.isEmpty else { return }
        markingActivityRead = true
        let generation = epoch
        defer { if generation == epoch { markingActivityRead = false } }
        do {
            let data = try await request("PUT", "v1/notes/activity/read", body: ["ids": ids])
            guard generation == epoch else { return }
            activityFetchSequence += 1
            try applyActivity(data, sequence: activityFetchSequence)
        } catch {
            if generation == epoch { activityMessage = "Could not mark activity read. Try again when connected."; onActivityChanged?() }
        }
    }
    func openActivity(_ entry: JournalActivity) {
        dismissActivityAlert()
        onActivitySelected?(entry)
        Task { await markActivityRead([entry.id]) }
    }
    func dismissActivityAlert() { activityAlertTask?.cancel(); activityAlertTask = nil; activityAlert = nil; onActivityChanged?() }
    func enableActivityNotifications() async {
        systemNotificationsEnabled = await activityNotifications.requestPermission()
        if !systemNotificationsEnabled { activityMessage = "macOS notifications are off. You can enable Mac Plaza in System Settings → Notifications." }
        onActivityChanged?()
    }

    func setLocalMiis(_ avatars: [Avatar]) {
        guard localMiis != avatars else { return }
        localMiis = avatars
        rebuildFriends(notify: false)
    }

    func assignedMiiID(for friend: SharedMii) -> UUID? {
        guard friend.temporaryAvatar == true, let discordID = friend.discordID,
              let id = localMiiChoices.choices[discordID], localMiis.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func assignMii(_ avatarID: UUID?, to friendID: String) {
        guard let friend = friends.first(where: { $0.id == friendID }), friend.temporaryAvatar == true,
              let discordID = friend.discordID,
              avatarID == nil || localMiis.contains(where: { $0.id == avatarID }) else { return }
        localMiiChoices.set(avatarID, for: discordID)
        rebuildFriends()
    }

    private func rebuildFriends(notify: Bool = true) {
        // Discord availability is independent of the sharing service. If that
        // service fails, stop displaying its cached private profiles and Plaza
        // activity. Viewer-local Discord history remains explicitly recent.
        let shared = connected ? snapshot?.friends ?? [] : []
        let unlinked = connected ? snapshot?.unlinkedFriends ?? [] : []
        let appearances = localMiiChoices.choices.compactMapValues { id in localMiis.first { $0.id == id } }
        if previewing {
            // Preview uses the same assignment path without account persistence.
            let chosen = friends.filter { $0.temporaryAvatar != true }
            let fallback = friends.filter { $0.temporaryAvatar == true }.map { friend in
                var profile = UnlinkedFriend(id: friend.id, displayName: friend.displayName, presence: friend.presence,
                    plazaOnline: friend.plazaOnline, activities: friend.activities)
                profile.discordID = friend.discordID; profile.customStatus = friend.customStatus
                return profile
            }
            friends = miiAssignments.resolve(shared: chosen, unlinked: fallback, localAppearances: appearances)
        } else if hasDiscordFriendsAuthorization {
            do {
                let roster = try DiscordFriendRoster.profiles(discordRecords, shared: shared, unlinked: unlinked, games: discordGames, customStatuses: discordCustomStatuses)
                friends = miiAssignments.resolve(shared: roster.shared, unlinked: roster.unlinked, localAppearances: appearances)
                    .filter { !hiddenIDs.contains($0.id) }
            } catch { friends = []; discordFriendsMessage = error.localizedDescription }
        } else {
            friends = miiAssignments.resolve(shared: shared, unlinked: unlinked, localAppearances: appearances).filter { !hiddenIDs.contains($0.id) }
        }
        if connected {
            friends = PublicNoteIdentity.applying(notes: visibleSharedJournal, to: friends)
        }
        if notify { onRosterChanged?() }
    }

    private func startPolling() {
        polling?.cancel()
        let generation = epoch
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.epoch == generation, self.token != nil else { return }
                if self.active || (self.activityEligible && self.account?.shareActivity == true) { await self.refresh() }
                else if self.activityEligible { await self.refreshActivity() }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard token != nil, !previewing, !refreshing, !busy else { return }
        refreshing = true
        let generation = epoch
        let revision = mutationRevision
        defer { if generation == epoch { refreshing = false } }
        do {
            await refreshDiscordAuthorization()
            _ = try await request("POST", "v1/heartbeat", body: heartbeat())
            let data = try await request("GET", "v1/snapshot")
            if revision == mutationRevision { try apply(data) }
            await syncDiscordRecipients()
            await refreshDiscordGames()
            await syncJournal()
            await refreshActivity()
        } catch is CancellationError { }
        catch {
            guard generation == epoch, revision == mutationRevision else { return }
            connected = false; message = error.localizedDescription
            sharedJournal = []
            discordGames = showDiscordGames ? gameHistory.suspend() : []
            discordCustomStatuses = []
            discordGamesMessage = "Live Discord activity is unavailable. Remembered games remain for up to two hours."
            // Never present an old observation as live availability after a failure.
            if hasDiscordFriendsAuthorization { rebuildFriends() }
            else { friends = friends.map {
                var f = $0; f.presence = .unknown; f.plazaOnline = false
                f.activities = f.activities.filter { $0.isRecent() }.map { var a = $0; a.active = false; return a }
                return f
            }
            if let refreshedAt, Date().timeIntervalSince(refreshedAt) > 75 { friends = [] }
            }
            onRosterChanged?()
        }
    }

    func setActive(_ value: Bool) {
        guard value != active else { return }; active = value
        guard token != nil else { return }
        Task { if value { await refresh() } else { _ = try? await request("POST", "v1/heartbeat", body: heartbeat()) } }
    }

    func setActivityEligible(_ value: Bool) { activityEligible = value }
    private func heartbeat() -> [String: Any] {
        var body: [String: Any] = ["active": active]
        if account?.shareActivity == true, activityEligible, let app = NSWorkspace.shared.frontmostApplication,
           let bundle = app.bundleIdentifier, bundle != Bundle.main.bundleIdentifier,
           let name = app.localizedName {
            body["application"] = ["name": String(name.prefix(100)), "bundleID": String(bundle.prefix(250))]
        }
        return body
    }

    func publish(avatar: Avatar, note: String, sharing: Bool, sharePresence: Bool, shareActivity: Bool, shareDiscordFriends: Bool = false) {
        do {
            _ = try avatar.validated()
            guard note.count <= 280 else { throw PlazaError.invalid("Plaza notes support up to 280 characters.") }
            var appearance = avatar
            appearance.features.creator = ""; appearance.features.birthDay = 0; appearance.features.birthMonth = 0
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance))
            mutate("PUT", "v1/profile", body: ["avatar": object, "note": note, "sharing": sharing, "sharePresence": sharePresence, "shareActivity": shareActivity, "shareDiscordFriends": shareDiscordFriends]) { _ in
                if !self.isolated, let endpoint = self.endpoint, let account = self.account {
                    UserDefaults.standard.set(avatar.id.uuidString, forKey: "social.avatar." + endpoint.absoluteString + account.id)
                }
                self.audienceRefreshedAt = nil
                Task { await self.syncDiscordRecipients() }
            }
        } catch { message = error.localizedDescription }
    }

    func createInvite() {
        mutate("POST", "v1/invites", snapshotResponse: false) { data in
            struct Invite: Decodable { var code: String }
            self.inviteCode = try JSONDecoder().decode(Invite.self, from: data).code
            self.message = "Invitation created. It expires in 24 hours and can be used once."
        }
    }
    func requestFriend(_ code: String) { mutate("POST", "v1/friends/request", body: ["code": code.trimmingCharacters(in: .whitespacesAndNewlines)]) }
    func accept(_ id: String) { mutate("POST", "v1/friends/accept", body: ["id": id]) }
    func remove(_ id: String, block: Bool = false) {
        let discordID = friends.first(where: { $0.id == id })?.discordID
        mutate("POST", block ? "v1/friends/block" : "v1/friends/remove", body: ["id": id]) { _ in
            if let discordID {
                self.gameHistory.forget(discordID)
                self.discordGames.removeAll { $0.discordID == discordID }
                self.rebuildFriends()
            }
        }
    }
    func loadBlocks() {
        mutate("GET", "v1/blocks", snapshotResponse: false) { data in
            struct Result: Decodable { var blocks: [FriendRequest] }
            self.blocks = try JSONDecoder().decode(Result.self, from: data).blocks
        }
    }
    func unblock(_ id: String) {
        mutate("POST", "v1/friends/unblock", body: ["id": id], snapshotResponse: false) { _ in self.blocks.removeAll { $0.id == id } }
    }
    func hide(_ id: String) {
        if let discordID = friends.first(where: { $0.id == id })?.discordID {
            gameHistory.forget(discordID)
            discordGames.removeAll { $0.discordID == discordID }
        }
        hiddenIDs.insert(id); friends.removeAll { $0.id == id }
        if !isolated { UserDefaults.standard.set(Array(hiddenIDs), forKey: hiddenKey) }
        onRosterChanged?()
    }
    func showAll() {
        hiddenIDs = []; if !isolated { UserDefaults.standard.removeObject(forKey: hiddenKey) }
        rebuildFriends()
    }
    func unlink() {
        mutate("DELETE", "v1/account", snapshotResponse: false) { _ in
            if let endpoint = self.endpoint { SocialKeychain.remove(endpoint); SocialKeychain.remove(endpoint, purpose: "discord-friends") }
            self.gameHistory.clear()
            self.reset(); self.message = "Discord unlinked. Your shared account and friendships were deleted."
        }
    }

    private func mutate(_ method: String, _ path: String, body: Any? = nil, snapshotResponse: Bool = true,
                        completion: ((Data) throws -> Void)? = nil) {
        guard !busy, !previewing else { return }
        mutationRevision += 1
        busy = true; let generation = epoch
        Task {
            defer { if epoch == generation { busy = false } }
            do {
                let data = try await request(method, path, body: body)
                if snapshotResponse { try apply(data) }
                try completion?(data)
            } catch is CancellationError { }
            catch { if epoch == generation { message = error.localizedDescription } }
        }
    }

    func preview() {
        guard token == nil else { return }
        reset(); previewing = true
        let names = ["Pip", "Cleo", "Jun"]
        friends = names.enumerated().map { i, name in
            var avatar = Avatar(name: name, outfit: [3, 6, 8][i]); avatar.hair = [12, 44, 33][i]
            avatar.id = UUID(uuidString: "A0000000-0000-0000-0000-00000000000\(i)")!
            avatar.skin = i; avatar.features.gender = i % 2
            var friend = SharedMii(id: "B0000000-0000-0000-0000-00000000000\(i)", displayName: name,
                             avatar: avatar, note: ["Making something nice today ☀️", "Taking a little plaza break.", "Anyone up for a game later?"][i],
                             presence: [.online, .idle, .dnd][i], plazaOnline: i == 0)
            friend.discordID = String(100 + i)
            friend.activities = [SharedAppActivity(name: ["Music", "Notes", "Discord"][i], bundleID: ["com.apple.Music", "com.apple.Notes", "com.hnc.Discord"][i],
                                                  source: "plaza", active: i != 1, observedAt: Date().timeIntervalSince1970 - Double(i * 60))]
            return friend
        }
        // Include a friend who has shared activity but hasn't published a Mii.
        let sample = friends.removeLast()
        var fallback = UnlinkedFriend(id: sample.id,
            displayName: sample.displayName, presence: sample.presence, plazaOnline: sample.plazaOnline,
            activities: sample.activities)
        fallback.discordID = sample.discordID
        friends = miiAssignments.resolve(shared: friends, unlinked: [fallback])
        message = "Preview only — sample friends and statuses. Nothing is uploaded."
        onRosterChanged?()
    }
    func endPreview() { reset(); message = "Connect Discord to see your friends’ Miis and availability." }
}
