import AppKit
import UserNotifications
import PlazaCore

/// Native delivery is optional; the in-plaza inbox and badge always work.
@MainActor
final class PlazaActivityNotifications: NSObject, UNUserNotificationCenterDelegate {
    private var reconciliation = 0
    private var scope: String?
    private var unreadIDs = Set<Int>()
    var previewsAllowed = false
    private var center: UNUserNotificationCenter?
    var onOpen: ((Int, String) -> Void)?
    override init() {
        super.init()
        // Command-line tests have no notification bundle identity.
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil {
            center = UNUserNotificationCenter.current(); center?.delegate = self
        }
    }
    func isEnabled() async -> Bool {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func requestPermission() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func deliver(_ activity: JournalActivity, scope: String, additional: Int) async {
        guard let center, self.scope == scope, unreadIDs.contains(activity.id), await isEnabled(),
              self.scope == scope, unreadIDs.contains(activity.id) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mac Plaza"
        content.body = previewsAllowed ? activity.message + (additional > 0 ? " and \(additional) more updates" : "") : "New activity on your notes"
        content.sound = .default
        content.userInfo = ["activityID": String(activity.id), "scope": scope]
        content.threadIdentifier = "plaza-note-" + activity.noteID.uuidString
        let identifier = "macplaza.activity.\(scope).\(activity.id)"
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        if self.scope != scope || !unreadIDs.contains(activity.id) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }
    func setState(unreadIDs: Set<Int>, scope: String?, count: Int) {
        reconciliation += 1; self.scope = scope; self.unreadIDs = unreadIDs
        if center != nil { NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil }
    }
    func reconcile() async {
        guard let center else { return }
        let generation = reconciliation
        let valid = Set(unreadIDs.map { "macplaza.activity.\(scope ?? "").\($0)" })
        let delivered = await center.deliveredNotifications()
        guard generation == reconciliation else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter {
            $0.hasPrefix("macplaza.activity.") && !valid.contains($0)
        })
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let value = info["activityID"] as? String, let id = Int(value), let scope = info["scope"] as? String {
            Task { @MainActor [weak self] in self?.onOpen?(id, scope) }
        }
        completionHandler()
    }
}
