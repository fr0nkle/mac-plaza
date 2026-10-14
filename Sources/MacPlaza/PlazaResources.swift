import Foundation

/// SwiftPM's generated Bundle.module traps if its build-time bundle is absent.
/// Distributed apps use Contents/Resources; missing optional assets return nil.
enum PlazaResources {
    private final class Token: NSObject {}
    static let searchRoots = roots(bundle: .main,
        executableURL: Bundle(for: Token.self).executableURL ?? Bundle.main.executableURL)

    static func roots(bundle: Bundle, executableURL: URL?) -> [URL] {
        var result = [bundle.resourceURL ?? bundle.bundleURL]
        var candidates = [bundle.bundleURL.appendingPathComponent("MacPlaza_MacPlaza.bundle")]
        if let resources = bundle.resourceURL {
            candidates.append(resources.appendingPathComponent("MacPlaza_MacPlaza.bundle"))
        }
        // swift run / swift test place the resource bundle beside the executable
        // or the test bundle. Installed apps must never search outside their app.
        if bundle.bundleURL.pathExtension != "app", let executableURL {
            var folder = executableURL.deletingLastPathComponent()
            for _ in 0..<4 {
                candidates.append(folder.appendingPathComponent("MacPlaza_MacPlaza.bundle"))
                folder.deleteLastPathComponent()
            }
        }
        for candidate in candidates {
            result.append(candidate)
            result.append(candidate.appendingPathComponent("Contents/Resources"))
        }
        return result
    }

    static func url(for name: String, extension ext: String, directory: String,
                    roots: [URL] = searchRoots) -> URL? {
        for root in roots {
            let url = root.appendingPathComponent(directory).appendingPathComponent(name).appendingPathExtension(ext).standardizedFileURL
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
        }
        return nil
    }
}
