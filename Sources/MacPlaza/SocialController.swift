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

private struct SocialHTTPError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
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
    var visibleSharedJournal: [SharedJournalNote] { sharedJournal.filter { !hiddenIDs.contains($0.ownerID ?? "") && !NoteRetention.isExpired(Date(timeIntervalSince1970: $0.created)) } }
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
    @Published private(set) var pendingInteractionCount = 0
    @Published var discordApplicationID = ""
    @Published private(set) var connectingLocally = false
    var usesLocalDiscord: Bool { discordCredentials?.localAuthorization == true }
    private let localAuthorization = DiscordLocalAuthorization()
    private let localStore = LocalSocialStore()
    private var localState: LocalSocialState?
    private var flushingInteractions = false
    private var flushingProfile = false
    private var attachingService = false
    private let localDiscordEndpoint = URL(string: "https://discord.com")!
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
    var account: SocialAccount? {
        guard var account = snapshot?.account else { return nil }
        if let profile = localState?.pendingProfile {
            account.avatar = profile.avatar; account.note = profile.note; account.sharing = profile.sharing
            account.sharePresence = profile.sharePresence; account.shareActivity = profile.shareActivity
            account.shareDiscordFriends = profile.shareDiscordFriends
        }
        return account
    }
    var botInstallURL: URL? {
        guard let appID = discordCredentials?.applicationID else { return nil }
        return URL(string: "https://discord.com/oauth2/authorize?client_id=\(appID)&scope=bot&permissions=0&integration_type=0")
    }
    var linkedAvatarID: UUID? {
        guard !isolated, let account, let endpoint,
              let value = UserDefaults.standard.string(forKey: "social.avatar." + endpoint.absoluteString + account.id) else { return nil }
        return UUID(uuidString: value)
    }

    init(isolated: Bool = false, transport: URLSession? = nil,
         restoredSession: (endpoint: URL, token: String, state: LocalSocialState)? = nil) {
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
        network = transport ?? URLSession(configuration: config, delegate: SocialRedirectBlocker(), delegateQueue: nil)
        super.init()
        discordApplicationID = isolated ? "" : UserDefaults.standard.string(forKey: "social.discord-application")
            ?? Bundle.main.object(forInfoDictionaryKey: "PlazaDiscordApplicationID") as? String ?? ""
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
            self.discordGames = self.showDiscordGames ? (ready ? self.gameHistory.records() : self.gameHistory.suspend()).filter { ids.contains($0.discordID) } : []
            self.discordCustomStatuses = ready ? self.discordCustomStatuses.filter { ids.contains($0.discordID) } : []
            self.rebuildFriends()
            if ready { Task { await self.syncDiscordRecipients(); await self.refreshDiscordGames() } }
        }
        if let restoredSession {
            endpoint = restoredSession.endpoint; serverAddress = restoredSession.endpoint.absoluteString; token = restoredSession.token
            if let state = try? restoredSession.state.validated() {
                localState = state; snapshot = state.snapshot; sharedJournal = state.displayedNotes
                pendingInteractionCount = state.pending.count
            }
        } else if !serverAddress.isEmpty { configure() }
        else { restoreLocalDiscord(); if usesLocalDiscord { startPolling() } }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? NSApp.keyWindow ?? ASPresentationAnchor()
    }

    func changeService() {
        reset(); endpoint = nil
        restoreLocalDiscord()
        message = "Enter the new service address, then connect Discord."
    }

    func configure() {
        do {
            let url = try SocialEndpoint.validated(serverAddress)
            reset()
            endpoint = url; serverAddress = url.absoluteString
            let generation = epoch
            Task {
                struct Configuration: Decodable { var discordApplicationID: String }
                if let data = try? await request("GET", "v1/config", authenticated: false), generation == epoch,
                   let configuration = try? JSONDecoder().decode(Configuration.self, from: data),
                   (UInt64(configuration.discordApplicationID) ?? 0) > 0, discordApplicationID.isEmpty {
                    discordApplicationID = configuration.discordApplicationID
                    if !isolated { UserDefaults.standard.set(discordApplicationID, forKey: "social.discord-application") }
                }
            }
            showDiscordGames = isolated ? true : UserDefaults.standard.object(forKey: "social.discord-games." + url.absoluteString) as? Bool ?? true
            if !isolated { UserDefaults.standard.set(serverAddress, forKey: "social.service") }
            hiddenIDs = isolated ? [] : Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
            token = isolated ? nil : SocialKeychain.read(url)
            if token != nil, !isolated, let id = UserDefaults.standard.string(forKey: "social.cached-account." + url.absoluteString) {
                restoreLocalState(accountID: id)
            }
            if !isolated { PlazaUpdater.shared.configure(endpoint: url, token: token) }
            message = token == nil ? "Service ready. Connect Discord to continue." : "Reconnecting to Plaza…"
            restoreLocalDiscord()
            if token != nil {
                if discordCredentials == nil, !isolated, let stored = SocialKeychain.read(url, purpose: "discord-friends"),
                   let data = stored.data(using: .utf8), let credentials = try? JSONDecoder().decode(DiscordSDKCredentials.self, from: data).validated() {
                    discordCredentials = credentials; hasDiscordFriendsAuthorization = true
                    localMiiChoices.useAccount(credentials.discordID)
                    gameHistory.useAccount(credentials.discordID, service: url.absoluteString)
                    if !showDiscordGames { gameHistory.clear() }
                    if credentials.expiresAt > Date().timeIntervalSince1970 + 120 { try discordClient.start(credentials) }
                }
                startPolling()
            }
            else if usesLocalDiscord { startPolling() }
        } catch { message = error.localizedDescription }
    }

    private func reset() {
        epoch += 1; auth?.cancel(); auth = nil; polling?.cancel(); polling = nil
        localAuthorization.cancel(); connectingLocally = false; attachingService = false
        discordClient.stop(); discordCredentials = nil; discordRecords = []; hasDiscordFriendsAuthorization = false
        discordReady = false; discordGames = []; gamesRefreshing = false; gamesRefreshedAt = nil
        discordCustomStatuses = []
        discordGamesMessage = "Custom statuses and games are available for friends in a shared bot server."
        discordRefreshing = false; discordFriendsMessage = "Load your Discord friends to see their Miis automatically."
        token = nil; connected = false; snapshot = nil; friends = []; blocks = []
        sharedJournal = []; uploadedJournal = nil; journalSyncTask?.cancel(); journalSyncTask = nil
        localState = nil; pendingInteractionCount = 0; flushingInteractions = false; flushingProfile = false
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
                SocialKeychain.remove(endpoint); SocialKeychain.remove(endpoint, purpose: "discord-friends"); reset(); restoreLocalDiscord()
                if usesLocalDiscord { startPolling() }
            }
            throw SocialHTTPError(status: http.statusCode, message: String((object?["error"] as? String ?? "The Plaza service is unavailable.").prefix(300)))
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
        if localState?.accountID != next.account.id { restoreLocalState(accountID: next.account.id) }
        snapshot = next; connected = true; refreshedAt = Date()
        if var state = localState { state.snapshot = next; try saveLocalState(state) }
        message = "Connected as \(next.account.displayName)"
        rebuildFriends()
    }

    private func activateDiscord(_ credentials: DiscordSDKCredentials) throws {
        let credentials = try credentials.validated()
        discordApplicationID = credentials.applicationID
        if !isolated { UserDefaults.standard.set(credentials.applicationID, forKey: "social.discord-application") }
        if credentials.localAuthorization == true, !isolated {
            try SocialKeychain.save(String(decoding: JSONEncoder().encode(credentials), as: UTF8.self), endpoint: localDiscordEndpoint, purpose: "discord-local")
            UserDefaults.standard.set(credentials.applicationID, forKey: "social.discord-application")
            discordApplicationID = credentials.applicationID
        } else if !isolated, let endpoint {
            let data = try JSONEncoder().encode(credentials)
            try SocialKeychain.save(String(decoding: data, as: UTF8.self), endpoint: endpoint, purpose: "discord-friends")
        }
        discordCredentials = credentials; hasDiscordFriendsAuthorization = true
        localMiiChoices.useAccount(credentials.discordID)
        gameHistory.useAccount(credentials.discordID, service: endpoint?.absoluteString)
        if !showDiscordGames { gameHistory.clear() }
        try discordClient.start(credentials)
    }

    private func restoreLocalDiscord() {
        guard !isolated, let stored = SocialKeychain.read(localDiscordEndpoint, purpose: "discord-local"),
              let credentials = try? JSONDecoder().decode(DiscordSDKCredentials.self, from: Data(stored.utf8)).validated(),
              credentials.localAuthorization == true else { return }
        // Never combine a different local Discord account with a saved service identity.
        if let endpoint, let storedService = SocialKeychain.read(endpoint, purpose: "discord-friends"),
           let service = try? JSONDecoder().decode(DiscordSDKCredentials.self, from: Data(storedService.utf8)),
           token != nil, service.discordID != credentials.discordID { return }
        discordCredentials = credentials; hasDiscordFriendsAuthorization = true
        localMiiChoices.useAccount(credentials.discordID)
        gameHistory.useAccount(credentials.discordID, service: endpoint?.absoluteString ?? "discord-local")
        if credentials.expiresAt > Date().timeIntervalSince1970 + 120 { try? discordClient.start(credentials) }
        discordFriendsMessage = "Discord connects directly from this Mac."
    }

    func connectLocally() {
        guard !busy, !connectingLocally, !isolated else { return }
        if !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let desired = try SocialEndpoint.validated(serverAddress)
                if endpoint != desired { configure() }
            } catch { message = error.localizedDescription; return }
        }
        guard token == nil || discordCredentials != nil else {
            message = "Use service sign-in once to verify this account, or disconnect this device before choosing a local Discord account."; return
        }
        connectingLocally = true; let generation = epoch
        Task {
            defer { if generation == epoch { connectingLocally = false } }
            do {
                let credentials = try await localAuthorization.authorize(applicationID: discordApplicationID,
                    expectedUserID: token == nil ? nil : discordCredentials?.discordID)
                guard generation == epoch else { return }
                try activateDiscord(credentials); previewing = false
                message = "Discord is connected directly on this Mac. Shared delivery uses the optional Plaza service."
                startPolling()
            } catch is CancellationError { }
            catch { if generation == epoch { message = error.localizedDescription } }
        }
    }

    func disconnectLocalDiscord() {
        SocialKeychain.remove(localDiscordEndpoint, purpose: "discord-local")
        if let endpoint { SocialKeychain.remove(endpoint); SocialKeychain.remove(endpoint, purpose: "discord-friends") }
        reset(); message = "Disconnected on this Mac. Local notes and queued changes are preserved for this account."
    }

    private func attachLocalDiscordToService() async {
        guard token == nil, let credentials = discordCredentials, credentials.localAuthorization == true,
              credentials.expiresAt > Date().timeIntervalSince1970 + 120, endpoint != nil, !attachingService else { return }
        attachingService = true; let generation = epoch
        defer { if generation == epoch { attachingService = false } }
        do {
            struct Session: Decodable { var token: String }
            let session = try JSONDecoder().decode(Session.self, from: await request("POST", "v1/auth/direct",
                body: ["accessToken": credentials.accessToken], authenticated: false))
            guard generation == epoch, let endpoint, (1...128).contains(session.token.count) else { return }
            if !isolated {
                try SocialKeychain.save(session.token, endpoint: endpoint)
                try SocialKeychain.save(String(decoding: JSONEncoder().encode(credentials), as: UTF8.self), endpoint: endpoint, purpose: "discord-friends")
                PlazaUpdater.shared.configure(endpoint: endpoint, token: session.token)
            }
            token = session.token
        } catch {
            guard generation == epoch else { return }
            message = "Discord works directly. Shared delivery will reconnect when the Plaza service is available."
        }
    }

    private func refreshDiscordAuthorization() async {
        guard !discordRefreshing, let credentials = discordCredentials,
              credentials.expiresAt < Date().timeIntervalSince1970 + 120 else { return }
        discordRefreshing = true; let generation = epoch
        defer { if generation == epoch { discordRefreshing = false } }
        do {
            let renewed: DiscordSDKCredentials
            if credentials.localAuthorization == true {
                renewed = try await localAuthorization.authorize(applicationID: credentials.applicationID,
                    expectedUserID: credentials.discordID, refreshToken: credentials.refreshToken)
            } else {
                let data = try await request("POST", "v1/discord/refresh", body: ["refreshToken": credentials.refreshToken])
                renewed = try JSONDecoder().decode(DiscordSDKCredentials.self, from: data).validated()
            }
            guard generation == epoch else { return }
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
            journalSyncMessage = "Posts are shared with their selected audience."
        } catch {
            guard generation == epoch else { return }
            journalSyncMessage = "Notes are saved on this Mac; sharing is pending. " + error.localizedDescription
            onRosterChanged?()
        }
    }

    func expireJournal(now: Date = Date()) {
        let expired = Set(sharedJournal.filter { NoteRetention.isExpired(Date(timeIntervalSince1970: $0.created), now: now) }.map(\.id))
        if var state = localState { state.prune(now: now); try? saveLocalState(state) }
        guard !expired.isEmpty else { return }
        sharedJournal.removeAll { expired.contains($0.id) }
        activity.removeAll { expired.contains($0.noteID) }
        unreadActivityCount = activity.filter { !$0.read }.count
        if let alert = activityAlert, expired.contains(alert.noteID) { dismissActivityAlert() }
        if !isolated {
            activityNotifications.setState(unreadIDs: Set(activity.filter { !$0.read }.map(\.id)), scope: activityScope, count: unreadActivityCount)
            Task { await activityNotifications.reconcile() }
        }
        onActivityChanged?()
    }

    private func reloadJournal() async throws {
        journalFetchSequence += 1
        let sequence = journalFetchSequence, generation = epoch
        let data = try await request("GET", "v1/notes/threads")
        let next = try JSONDecoder().decode(SharedJournalSnapshot.self, from: data).validated().notes
        guard generation == epoch, sequence >= journalAppliedSequence else { return }
        journalAppliedSequence = sequence
        if var state = localState {
            state.notes = next; state.updatedAt = Date().timeIntervalSince1970
            state.prune()
            let visible = Set(next.map(\.id))
            state.pending.removeAll { !visible.contains($0.noteID) }
            try saveLocalState(state)
        } else { sharedJournal = next }
        rebuildFriends(notify: false); onRosterChanged?()
    }

    private func restoreLocalState(accountID: String) {
        guard let endpoint else { return }
        do {
            localState = isolated ? LocalSocialState(accountID: accountID) : try localStore.load(endpoint: endpoint, accountID: accountID)
            snapshot = localState?.snapshot
            sharedJournal = localState?.displayedNotes ?? []
            pendingInteractionCount = localState?.pending.count ?? 0
            activity = localState?.activities ?? []
            unreadActivityCount = activity.filter { !$0.read }.count
            journalSyncMessage = "Saved discussions are available on this Mac. Changes sync when the service reconnects."
        } catch {
            localState = nil
            journalSyncMessage = error.localizedDescription
        }
    }

    private func saveLocalState(_ state: LocalSocialState) throws {
        guard let endpoint else { throw PlazaError.invalid("Choose a sharing service first.") }
        if !isolated {
            try localStore.save(state, endpoint: endpoint)
            UserDefaults.standard.set(state.accountID, forKey: "social.cached-account." + endpoint.absoluteString)
        }
        localState = state; sharedJournal = state.displayedNotes
        pendingInteractionCount = state.pending.count
    }

    private func queue(_ item: PendingJournalInteraction) async -> Bool {
        guard token != nil, !previewing, var state = localState else {
            journalInteractionMessage = "Connect to the Plaza service once before sharing interactions."; return false
        }
        do {
            state.prune(); try state.enqueue(item)
            try saveLocalState(state)
            journalInteractionMessage = nil
            journalSyncMessage = "Saved on this Mac · \(state.pending.count) interaction(s) waiting for delivery."
            onRosterChanged?()
            if connected { Task { await self.flushInteractions() } }
            return true
        } catch { journalInteractionMessage = error.localizedDescription; return false }
    }

    private func flushInteractions() async {
        guard connected, token != nil, !flushingInteractions, !previewing, localState?.pending.isEmpty == false else { return }
        flushingInteractions = true; let generation = epoch
        defer { if generation == epoch { flushingInteractions = false } }
        while generation == epoch, let item = localState?.pending.first {
            do {
                if item.expiresAt <= Date().timeIntervalSince1970 {
                    if var state = localState { state.acknowledge(item.id); try saveLocalState(state) }
                    continue
                }
                var body: [String: Any] = [:]
                let action: String, method: String
                if let liked = item.liked { action = "like"; method = "PUT"; body["liked"] = liked }
                else if let replyID = item.replyID {
                    action = "replies/" + replyID.uuidString; method = item.text == nil ? "DELETE" : "PUT"
                    if let author = item.author, let text = item.text {
                        body["author"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(author)); body["text"] = text
                    }
                } else { return }
                _ = try await request(method, "v1/notes/" + item.noteID.uuidString + "/" + action, body: body)
                guard generation == epoch, var state = localState else { return }
                state.commit(item); try saveLocalState(state)
                onRosterChanged?()
            } catch let error as SocialHTTPError where [400, 403, 404, 409, 410, 422].contains(error.status) {
                guard generation == epoch, var state = localState else { return }
                state.acknowledge(item.id)
                try? saveLocalState(state)
                journalInteractionMessage = "A pending change could not be delivered: " + error.localizedDescription
                onRosterChanged?()
                // Stop if disk storage failed, keeping the original durable queue.
                if localState?.pending.contains(where: { $0.id == item.id }) == true { return }
            } catch {
                guard generation == epoch else { return }
                journalSyncMessage = "Saved on this Mac · delivery will retry when connected."
                return
            }
        }
        guard generation == epoch else { return }
        try? await reloadJournal()
        if pendingInteractionCount == 0 { journalSyncMessage = "Public notes and interactions are up to date." }
    }

    private func interactionExpiry(noteID: UUID) throws -> Double {
        guard let note = sharedJournal.first(where: { $0.id == noteID }),
              !NoteRetention.isExpired(Date(timeIntervalSince1970: note.created)) else {
            throw PlazaError.invalid("This public note is no longer available.")
        }
        return note.created + 7 * 86400
    }
    func like(noteID: UUID, liked: Bool) async -> Bool {
        do { return await queue(PendingJournalInteraction(noteID: noteID, liked: liked, expiresAt: try interactionExpiry(noteID: noteID))) }
        catch { journalInteractionMessage = error.localizedDescription; return false }
    }
    func reply(noteID: UUID, replyID: UUID, author: Avatar, text: String) async -> Bool {
        do {
            _ = try author.validated()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 280 else {
                throw PlazaError.invalid("Write a reply of up to 280 characters.")
            }
            let replies = sharedJournal.first { $0.id == noteID }?.replies ?? []
            guard replies.count < 50 || replies.contains(where: { $0.id == replyID && $0.ownerID == account?.id }) else {
                throw PlazaError.invalid("This note has reached its reply limit.")
            }
            if let previous = replies.first(where: { $0.id == replyID }), previous.ownerID != account?.id {
                throw PlazaError.invalid("Only the reply's author can edit it.")
            }
            var appearance = author
            appearance.features.creator = ""; appearance.features.birthDay = 0; appearance.features.birthMonth = 0
            return await queue(PendingJournalInteraction(noteID: noteID, replyID: replyID, author: appearance,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines), displayName: account?.displayName,
                expiresAt: try interactionExpiry(noteID: noteID)))
        } catch { journalInteractionMessage = error.localizedDescription; return false }
    }
    func deleteReply(noteID: UUID, replyID: UUID) async -> Bool {
        do {
            guard let thread = sharedJournal.first(where: { $0.id == noteID }),
                  let reply = thread.replies?.first(where: { $0.id == replyID }),
                  reply.ownerID == account?.id || thread.ownerID == account?.id else {
                throw PlazaError.invalid("You cannot remove this reply.")
            }
            return await queue(PendingJournalInteraction(noteID: noteID, replyID: replyID, expiresAt: try interactionExpiry(noteID: noteID)))
        } catch { journalInteractionMessage = error.localizedDescription; return false }
    }

    private var currentActivityScope: String? {
        guard let endpoint, let account else { return nil }
        return SHA256.hash(data: Data((endpoint.absoluteString + "|" + account.id).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func applyActivity(_ data: Data, sequence: Int) throws {
        var snapshot = try JSONDecoder().decode(JournalActivitySnapshot.self, from: data).validated()
        if var state = localState {
            let read = Set(state.readActivityIDs)
            snapshot.activities = snapshot.activities.map { var entry = $0; if read.contains(entry.id) { entry.read = true }; return entry }
            snapshot.unreadCount = snapshot.activities.filter { !$0.read }.count
            state.activities = snapshot.activities
            state.readActivityIDs.removeAll { id in !snapshot.activities.contains { $0.id == id } }
            try saveLocalState(state)
        }
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
        guard token != nil, !ids.isEmpty, var state = localState else { return }
        let valid = Set(state.activities.map(\.id)).intersection(ids)
        state.readActivityIDs = Array(Set(state.readActivityIDs).union(valid)).sorted()
        state.activities = state.activities.map { var entry = $0; if valid.contains(entry.id) { entry.read = true }; return entry }
        do {
            try saveLocalState(state)
            activity = state.activities; unreadActivityCount = activity.filter { !$0.read }.count
            if let alert = activityAlert, valid.contains(alert.id) { dismissActivityAlert() }
            if !isolated {
                activityNotifications.setState(unreadIDs: Set(activity.filter { !$0.read }.map(\.id)), scope: currentActivityScope, count: unreadActivityCount)
                Task { await activityNotifications.reconcile() }
            }
            onActivityChanged?()
            if connected { await flushActivityRead() }
        } catch { activityMessage = error.localizedDescription; onActivityChanged?() }
    }
    private func flushActivityRead() async {
        guard token != nil, connected, !markingActivityRead, let ids = localState?.readActivityIDs, !ids.isEmpty else { return }
        markingActivityRead = true; let generation = epoch
        defer { if generation == epoch { markingActivityRead = false } }
        do {
            let data = try await request("PUT", "v1/notes/activity/read", body: ["ids": ids])
            guard generation == epoch, var state = localState else { return }
            state.readActivityIDs.removeAll { ids.contains($0) }; try saveLocalState(state)
            activityFetchSequence += 1
            try applyActivity(data, sequence: activityFetchSequence)
        } catch { if generation == epoch { activityMessage = "Read state is saved on this Mac and will sync when connected." } }
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
                guard let self, self.epoch == generation, self.token != nil || self.usesLocalDiscord else { return }
                if self.active || self.usesLocalDiscord || (self.activityEligible && self.account?.shareActivity == true) { await self.refresh() }
                else if self.activityEligible { await self.refreshActivity() }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard token != nil || usesLocalDiscord, !previewing, !refreshing, !busy, !connectingLocally else { return }
        refreshing = true
        let generation = epoch
        let revision = mutationRevision
        defer { if generation == epoch { refreshing = false } }
        do {
            await refreshDiscordAuthorization()
            guard generation == epoch else { return }
            if usesLocalDiscord { await attachLocalDiscordToService() }
            guard token != nil else { return }
            _ = try await request("POST", "v1/heartbeat", body: heartbeat())
            let data = try await request("GET", "v1/snapshot")
            if revision == mutationRevision { try apply(data) }
            await flushProfile()
            await syncDiscordRecipients()
            await refreshDiscordGames()
            await syncJournal()
            await flushInteractions()
            await flushActivityRead()
            await refreshActivity()
        } catch is CancellationError { }
        catch {
            guard generation == epoch, revision == mutationRevision else { return }
            connected = false; message = error.localizedDescription
            journalSyncMessage = "Offline · saved discussions are available; new changes wait on this Mac."
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
            guard token != nil, !previewing, var state = localState else { throw PlazaError.invalid("Connect to the Plaza service once before sharing your profile.") }
            var appearance = avatar
            appearance.features.creator = ""; appearance.features.birthDay = 0; appearance.features.birthMonth = 0
            let profile = LocalSharedProfile(avatar: appearance, note: note, sharing: sharing, sharePresence: sharePresence,
                shareActivity: shareActivity, shareDiscordFriends: shareDiscordFriends)
            try profile.validate(); state.pendingProfile = profile; try saveLocalState(state)
            if !isolated, let endpoint, let account {
                UserDefaults.standard.set(avatar.id.uuidString, forKey: "social.avatar." + endpoint.absoluteString + account.id)
            }
            discordSharingMessage = "Profile saved on this Mac. Sharing changes will sync when connected."
            if connected { Task { await self.flushProfile() } }
        } catch { message = error.localizedDescription }
    }
    private func flushProfile() async {
        guard connected, token != nil, !flushingProfile, !previewing else { return }
        flushingProfile = true; let generation = epoch
        defer { if generation == epoch { flushingProfile = false } }
        while generation == epoch, let profile = localState?.pendingProfile {
            do {
                let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))
                let data = try await request("PUT", "v1/profile", body: object)
                guard generation == epoch, var state = localState else { return }
                if state.pendingProfile?.id == profile.id { state.pendingProfile = nil }
                try saveLocalState(state); try apply(data)
                audienceRefreshedAt = nil
                discordSharingMessage = "Your profile and sharing settings are up to date."
                await syncDiscordRecipients()
            } catch {
                if generation == epoch { discordSharingMessage = "Profile saved on this Mac. Delivery will retry when connected." }
                return
            }
        }
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
            if block { Task { try? await self.reloadJournal(); await self.refreshActivity() } }
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
            if let endpoint = self.endpoint {
                if let id = self.account?.id {
                    self.localStore.remove(endpoint: endpoint, accountID: id)
                    UserDefaults.standard.removeObject(forKey: "social.cached-account." + endpoint.absoluteString)
                }
                SocialKeychain.remove(endpoint); SocialKeychain.remove(endpoint, purpose: "discord-friends")
            }
            SocialKeychain.remove(self.localDiscordEndpoint, purpose: "discord-local")
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
