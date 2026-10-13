import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SteamGameDetails: Codable, Equatable, Sendable {
    let appID: UInt32
    var summary: String?
    var artwork: Data?
    var fetchedAt: Date?
}

private final class SteamPreviewRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(SteamGameDetailsStore.allowedURL) == true ? request : nil)
    }
}

/// Public store details only, requested when a game is previewed. No Steam login,
/// cookies, API key, journal content or local library paths are sent to Steam.
actor SteamGameDetailsStore {
    static let shared = SteamGameDetailsStore()
    static let freshness: TimeInterval = 7 * 24 * 60 * 60
    private let directory: URL
    private let steamRoot: URL
    private let session: URLSession
    private var memory: [UInt32: SteamGameDetails] = [:]
    private var pending: [UInt32: Task<SteamGameDetails, Never>] = [:]
    private var retryAfter: [UInt32: Date] = [:]

    init(directory: URL? = nil, steamRoot: URL = SteamGames.defaultRoot, session: URLSession? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacPlaza/SteamPreviews")
        self.steamRoot = steamRoot
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            self.session = URLSession(configuration: configuration, delegate: SteamPreviewRedirects(), delegateQueue: nil)
        }
    }

    func cached(appID: UInt32) -> SteamGameDetails {
        if let value = memory[appID] { return value }
        var value = SteamGameDetails(appID: appID)
        let file = directory.appendingPathComponent("\(appID).json")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 3_000_000,
           let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(SteamGameDetails.self, from: data), saved.appID == appID {
            value = saved
            value.summary = saved.summary.map(Self.plainText)
            value.artwork = saved.artwork.flatMap(Self.artwork)
        }
        if value.artwork == nil { value.artwork = localArtwork(appID: appID) }
        memory[appID] = value
        return value
    }

    func details(appID: UInt32) async -> SteamGameDetails {
        let previous = cached(appID: appID)
        guard appID > 0 else { return previous }
        if let fetched = previous.fetchedAt, previous.summary != nil, previous.artwork != nil, Date().timeIntervalSince(fetched) < Self.freshness { return previous }
        if let retry = retryAfter[appID], retry > Date() { return previous }
        if let task = pending[appID] { return await task.value }
        let task = Task { await fetch(appID: appID, previous: previous) }
        pending[appID] = task
        let value = await task.value
        pending[appID] = nil
        return value
    }

    private func fetch(appID: UInt32, previous: SteamGameDetails) async -> SteamGameDetails {
        var value = previous
        do {
            let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english&filters=basic")!
            let data = try await download(url, limit: 1_000_000)
            let metadata = try Self.metadata(data, appID: appID)
            if let summary = metadata.summary { value.summary = summary }
            if value.artwork == nil, let imageURL = metadata.imageURL,
               let image = try? await download(imageURL, limit: 5_000_000) { value.artwork = Self.artwork(image) }
            value.fetchedAt = Date()
            memory[appID] = value
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(value) { try? data.write(to: directory.appendingPathComponent("\(appID).json"), options: .atomic) }
            retryAfter[appID] = Date().addingTimeInterval(60)
        } catch {
            // Keep prior descriptions/artwork through outages and delisted games.
            retryAfter[appID] = Date().addingTimeInterval(60)
        }
        return value
    }

    private func download(_ url: URL, limit: Int) async throws -> Data {
        guard Self.allowedURL(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              response.url.map(Self.allowedURL) == true,
              response.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    nonisolated static func allowedURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "store.steampowered.com" || host == "steamstatic.com" || host.hasSuffix(".steamstatic.com") || host == "steamcdn-a.akamaihd.net"
    }

    nonisolated static func metadata(_ data: Data, appID: UInt32) throws -> (summary: String?, imageURL: URL?) {
        struct Envelope: Decodable { let success: Bool; let data: Entry? }
        struct Entry: Decodable { let steam_appid: UInt32; let short_description: String?; let header_image: String? }
        guard data.count <= 1_000_000,
              let entry = try JSONDecoder().decode([String: Envelope].self, from: data)[String(appID)], entry.success,
              let game = entry.data, game.steam_appid == appID else { throw URLError(.cannotParseResponse) }
        let summary = game.short_description.map(plainText).flatMap { $0.isEmpty ? nil : $0 }
        let image = game.header_image.flatMap(URL.init(string:)).flatMap { allowedURL($0) ? $0 : nil }
        return (summary, image)
    }

    nonisolated static func plainText(_ html: String) -> String {
        var text = String(html.prefix(8192))
            .replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)</?(p|div|br|li|ul|ol|h[1-6])\\b[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        if let expression = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: text), let number = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[number])
                let code = raw.first == "x" ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let code, let scalar = UnicodeScalar(code) { text.replaceSubrange(range, with: String(scalar)) }
            }
        }
        // Decode ampersands last so an encoded entity cannot be decoded twice.
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(1200))
    }

    private func localArtwork(appID: UInt32) -> Data? {
        let cache = steamRoot.appendingPathComponent("appcache/librarycache")
        let folder = cache.appendingPathComponent(String(appID))
        let hashes = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.path < $1.path }
        let candidates = [folder.appendingPathComponent("library_header.jpg")] + hashes.map { $0.appendingPathComponent("library_header.jpg") } +
            [cache.appendingPathComponent("\(appID)_header.jpg"), folder.appendingPathComponent("library_600x900.jpg"), cache.appendingPathComponent("\(appID)_library_600x900.jpg")]
        for file in candidates {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5_000_000,
                  let data = try? Data(contentsOf: file), let image = Self.artwork(data) else { continue }
            return image
        }
        return nil
    }

    nonisolated static func artwork(_ data: Data) -> Data? {
        guard data.count <= 5_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 920, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 2_000_000 else { return nil }
        return output as Data
    }
}
