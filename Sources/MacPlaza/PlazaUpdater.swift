import AppKit
import Combine
import Sparkle
import SwiftUI

/// Private beta updates use the Plaza session, never a bundled GitHub credential.
@MainActor
final class PlazaUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = PlazaUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var signedIn = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    private var endpoint: URL?
    private var started = false
    private var observations: Set<AnyCancellable> = []
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func configure(endpoint: URL?, token: String?) {
        self.endpoint = endpoint
        signedIn = endpoint != nil && token != nil
        controller.updater.httpHeaders = token.map { ["Authorization": "Bearer " + $0] }
        guard signedIn else { canCheck = false; return }
        if !started {
            started = true
            controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] value in
                self?.canCheck = value && self?.signedIn == true
            }.store(in: &observations)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
            controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
            controller.startUpdater()
        } else { canCheck = controller.updater.canCheckForUpdates }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        endpoint?.appendingPathComponent("updates/appcast.xml").absoluteString
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if !signedIn { throw NSError(domain: "MacPlaza.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connect Discord to check for private testing updates."]) }
    }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        guard let endpoint, let url = request.url, url.scheme == endpoint.scheme,
              url.host == endpoint.host, url.port == endpoint.port, url.path.hasPrefix("/updates/") else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            request.url = endpoint?.appendingPathComponent("updates/rejected-download")
            return
        }
    }
    func check() { if signedIn { controller.checkForUpdates(nil) } }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
}

struct UpdateSettingsView: View {
    @ObservedObject private var updater = PlazaUpdater.shared
    var body: some View {
        Section("App updates") {
            Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
            Toggle("Automatically download and install updates", isOn: Binding(get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                .disabled(!updater.automaticChecks)
            PlazaButton("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
            Text(updater.signedIn ? "Updates come from the private testing channel and are verified before installation. Your Miis and settings stay on this Mac." : "Connect Discord to enable private testing updates.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CheckForPlazaUpdates: View {
    @ObservedObject private var updater = PlazaUpdater.shared
    var body: some View { PlazaButton("Check for Updates…", action: updater.check).disabled(!updater.canCheck) }
}
