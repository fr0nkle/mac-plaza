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
    @Published private(set) var availability = PlazaUpdateAvailability()
    var updateAvailable: Bool { signedIn && availability.available }
    private var endpoint: URL?
    private var started = false
    private var observations: Set<AnyCancellable> = []
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func configure(endpoint: URL?, token: String?) {
        if self.endpoint != endpoint || token == nil { availability.clear() }
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
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard signedIn else { availability.clear(); return }
        availability.found(version: item.versionString, displayVersion: item.displayVersionString,
            installedVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            downloadURL: item.isInformationOnlyUpdate ? nil : item.fileURL, source: endpoint)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { availability.clear() }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { availability.clear() }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { availability.clear() }
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
            if updater.updateAvailable {
                Label("Mac Plaza \(updater.availability.displayVersion ?? "") is available to download.", systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(PlazaStyle.teal)
            }
            Text(updater.signedIn ? "Updates come from the private testing channel and are verified before installation. Your Miis and settings stay on this Mac." : "Connect Discord to enable private testing updates.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PlazaUpdateBadge: View {
    var available: Bool
    var body: some View {
        if available {
            Text("!").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 19, height: 19).background(.red, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct PlazaUpdateIndicator: ViewModifier {
    var available: Bool
    var label: String
    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) { PlazaUpdateBadge(available: available).padding(3) }
            .accessibilityLabel(label + (available ? ", update available" : ""))
            .help(available ? "A new Mac Plaza update is available. Open System Update in Settings." : label)
    }
}

struct CheckForPlazaUpdates: View {
    @ObservedObject private var updater = PlazaUpdater.shared
    var body: some View { PlazaButton("Check for Updates…", action: updater.check).disabled(!updater.canCheck) }
}
