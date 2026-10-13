import AppKit
import PlazaCore

extension PlazaModel {
    var rotatingHomeEnabled: Bool { document.preferences.rotatingHomeScreen ?? true }
    var homeApps: [AppIsland] {
        guard rotatingHomeEnabled && !editing else { return document.apps }
        return rotationReady ? rotatingApps : document.apps.filter { resolvedURL($0) != nil }
    }
    var topicApps: [AppIsland] {
        var seen = Set<UUID>()
        return (document.apps + rotatingApps + recentApps.entries.map(\.app)).filter { seen.insert($0.id).inserted }
    }

    func recordRecentLaunch(_ app: AppIsland, at date: Date = Date()) {
        guard rotatingHomeEnabled, app.bundleID != Bundle.main.bundleIdentifier,
              app.bundleID != "local.macplaza.app", resolvedURL(app) != nil else { return }
        do { try recentApps.record(app, at: date) }
        catch { status = "Recent app history could not be saved. Your pinned apps are unchanged." }
    }

    func prepareRotatingHome() {
        guard loaded, rotatingHomeEnabled, !recoveryRequired else { return }
        rotationScanTask?.cancel()
        preparingRotatingHome = true
        rotationAwaitingFriends = true
        if observesSystemAppLaunches {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                if let url = app.bundleURL, let island = try? Self.island(at: url) {
                    recordRecentLaunch(island, at: app.launchDate ?? Date())
                }
            }
        }
        rotationScanTask = Task { [weak self] in
            let urls = await Task.detached(priority: .utility) {
                InstalledHomeApps.applicationURLs() + SteamGames.installed().map(\.applicationURL)
            }.value
            guard !Task.isCancelled, let self, self.rotatingHomeEnabled else { return }
            // Pins retain their UUID, labels and custom artwork on either screen.
            let candidates = self.document.apps + self.recentApps.entries.map(\.app) + urls.compactMap { try? Self.island(at: $0) }
            var seen = Set<String>()
            self.installedRotationApps = candidates.filter { app in
                app.bundleID != "local.macplaza.app" && self.resolvedURL(app) != nil &&
                seen.insert(HomeScreenRotation.key(app)).inserted
            }.map { app in
                if self.document.apps.contains(where: { $0.id == app.id }) { return app }
                var stable = app; stable.id = RecentAppHistory.stableID(for: app); return stable
            }
            self.preparingRotatingHome = false
            self.rotationNeedsRefresh = true
            self.applyPendingHomeRotation()
        }
    }

    func refreshHomeForFriendActivity() {
        guard rotatingHomeEnabled, rotationAwaitingFriends, !preparingRotatingHome,
              !HomeScreenRotation.installedFriendGames(friends: social.friends, installed: installedRotationApps).isEmpty else { return }
        rotationNeedsRefresh = true
        applyPendingHomeRotation()
    }

    func applyPendingHomeRotation() {
        guard rotationNeedsRefresh, rotatingHomeEnabled, loaded, !editing, previewAppID == nil,
              launching.isEmpty, sheet == nil || sheet?.id == "preferences" else { return }
        let installed = installedRotationApps.filter { resolvedURL($0) != nil }
        let byKey = Dictionary(uniqueKeysWithValues: installed.map { (HomeScreenRotation.key($0), $0) })
        let recent = recentApps.entries.filter { Date().timeIntervalSince($0.launched) < 90 * 86400 }
            .compactMap { byKey[HomeScreenRotation.key($0.app)] }
        let games = HomeScreenRotation.installedFriendGames(friends: social.friends, installed: installed)
        let fallback = document.apps.compactMap { byKey[HomeScreenRotation.key($0)] }
        var random = SystemRandomNumberGenerator()
        rotatingApps = HomeScreenRotation.select(recent: recent, friendGames: games, fallback: fallback,
            previous: recentApps.previous, using: &random)
        rotationReady = true
        rotationNeedsRefresh = false
        if !games.isEmpty { rotationAwaitingFriends = false }
        page = 0
        try? recentApps.remember(rotatingApps)
        updateVisibleIslands()
    }

    func pinHomeApp(_ app: AppIsland) {
        guard document.apps.count < 120, resolvedURL(app) != nil else { return }
        guard !document.apps.contains(where: { HomeScreenRotation.key($0) == HomeScreenRotation.key(app) }) else { return }
        rememberLayout()
        if mutate({ $0.apps.append(app) }) { status = "\(app.label) pinned. Turn off rotation to use your saved layout." }
    }
}
