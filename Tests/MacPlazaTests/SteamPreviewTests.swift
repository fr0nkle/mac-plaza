import XCTest
import AppKit
import SwiftUI
import PlazaCore
@testable import MacPlaza

private final class SteamPreviewProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests = [URLRequest]()
    static func reset(_ handler: @escaping (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler; requests = []
    }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.requests.append(request); let handler = Self.handler; Self.lock.unlock()
        do {
            guard let handler else { throw URLError(.notConnectedToInternet) }
            let (status, data) = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class SteamPreviewTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SteamPreviewProtocol.self]
        return URLSession(configuration: config)
    }
    private func payload(id: UInt32 = 2379780, description: String = "Build a deck &amp; find <b>Jokers</b>.", header: String = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/2379780/header.jpg") throws -> Data {
        try JSONSerialization.data(withJSONObject: [String(id): ["success": true, "data": ["steam_appid": id, "short_description": description, "header_image": header]]])
    }
    private func picture() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 920, pixelsHigh: 430, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:]))
    }

    func testMetadataIsMatchedToGameAndConvertedToPlainText() throws {
        let entry = try SteamGameDetailsStore.metadata(payload(description: "<p>Build &amp; discover &#39;Jokers&#39; &#x2665;.</p><script>unwanted()</script>"), appID: 2379780)
        XCTAssertEqual(entry.summary, "Build & discover 'Jokers' ♥.")
        XCTAssertNotNil(entry.imageURL)
        XCTAssertThrowsError(try SteamGameDetailsStore.metadata(payload(), appID: 123))
        let mismatch = Data("{\"2379780\":{\"success\":true,\"data\":{\"steam_appid\":123}}}".utf8)
        XCTAssertThrowsError(try SteamGameDetailsStore.metadata(mismatch, appID: 2379780))
        XCTAssertThrowsError(try SteamGameDetailsStore.metadata(Data("{\"2379780\":{\"success\":false}}".utf8), appID: 2379780))
        XCTAssertLessThanOrEqual(SteamGameDetailsStore.plainText(String(repeating: "word ", count: 10000)).count, 1200)
    }

    func testArtworkURLsAndImageBytesAreRestricted() throws {
        for bad in ["http://shared.akamai.steamstatic.com/header.jpg", "https://steamstatic.com.example.org/image", "https://example.org/header.jpg", "file:///tmp/image.jpg", "https://user:password@store.steampowered.com/image", "https://store.steampowered.com:8443/image"] {
            XCTAssertFalse(SteamGameDetailsStore.allowedURL(URL(string: bad)!))
            XCTAssertNil(try SteamGameDetailsStore.metadata(payload(header: bad), appID: 2379780).imageURL)
        }
        XCTAssertNil(SteamGameDetailsStore.artwork(Data("not an image".utf8)))
        XCTAssertNotNil(SteamGameDetailsStore.artwork(try picture()))
    }

    func testConcurrentLoadsCacheDescriptionAndCoverAndReloadOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = try payload(), image = try picture()
        SteamPreviewProtocol.reset { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, request.url?.host == "store.steampowered.com" ? metadata : image)
        }
        let store = SteamGameDetailsStore(directory: root, steamRoot: root, session: session())
        async let first = store.details(appID: 2379780)
        async let second = store.details(appID: 2379780)
        let values = await [first, second]
        XCTAssertEqual(values[0], values[1])
        XCTAssertEqual(values[0].summary, "Build a deck & find Jokers.")
        XCTAssertNotNil(values[0].artwork)
        XCTAssertEqual(SteamPreviewProtocol.count, 2, "One metadata and one image request are shared by both callers")
        SteamPreviewProtocol.reset { _ in throw URLError(.notConnectedToInternet) }
        let offline = SteamGameDetailsStore(directory: root, steamRoot: root, session: session())
        let saved = await offline.details(appID: 2379780)
        XCTAssertEqual(saved.summary, values[0].summary)
        XCTAssertNotNil(saved.artwork)
        XCTAssertEqual(SteamPreviewProtocol.count, 0, "Fresh cached data works without a request")
        var stale = saved; stale.fetchedAt = Date().addingTimeInterval(-SteamGameDetailsStore.freshness - 10)
        try JSONEncoder().encode(stale).write(to: root.appendingPathComponent("2379780.json"))
        let expired = SteamGameDetailsStore(directory: root, steamRoot: root, session: session())
        let retained = await expired.details(appID: 2379780)
        XCTAssertEqual(retained.summary, saved.summary)
        XCTAssertNotNil(retained.artwork)
        _ = await expired.details(appID: 2379780)
        XCTAssertEqual(SteamPreviewProtocol.count, 1, "An outage retains the cache and backs off retries")
    }

    func testLocalHashedSteamArtworkIsAvailableBeforeNetworkAndSurvivesFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("appcache/librarycache/2379780/hash")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try picture().write(to: folder.appendingPathComponent("library_header.jpg"))
        SteamPreviewProtocol.reset { _ in throw URLError(.notConnectedToInternet) }
        let store = SteamGameDetailsStore(directory: root.appendingPathComponent("cache"), steamRoot: root, session: session())
        let cached = await store.cached(appID: 2379780)
        XCTAssertNotNil(cached.artwork)
        XCTAssertNil(cached.summary)
        XCTAssertEqual(SteamPreviewProtocol.count, 0)
        let unavailable = await store.details(appID: 2379780)
        XCTAssertEqual(cached, unavailable)
        let different = await store.cached(appID: 123)
        XCTAssertNil(different.artwork)
        XCTAssertNil(different.summary)
    }

    @MainActor func testLiveBalatroDetailsAndPreviewLayout() async throws {
        guard ProcessInfo.processInfo.environment["PLAZA_STEAM_PREVIEW_QA"] == "1" else { throw XCTSkip("Opt-in live Steam preview capture") }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/steam-preview-fixture")
        let store = SteamGameDetailsStore(directory: root.appendingPathComponent("cache"))
        let details = await store.details(appID: 2379780)
        XCTAssertTrue(details.summary?.contains("Balatro") == true)
        XCTAssertNotNil(details.artwork)
        let model = PlazaModel(directory: root.appendingPathComponent("plaza"))
        for _ in 0..<200 where !model.loaded { try await Task.sleep(for: .milliseconds(10)) }
        defer { model.audio.update(enabled: false, allowPreview: false) }
        var app = AppIsland(label: "Balatro", bundleID: "com.Balatro.localthunk", path: SteamGames.defaultRoot.appendingPathComponent("steamapps/common/Balatro/Balatro.app").path)
        app.steamAppID = 2379780
        model.document.preferences.ambientSound = false
        model.mutate { $0.apps = [app] }
        for height in [510, 340] {
            let host = NSHostingView(rootView: AppPreviewView(model: model, app: app, close: {}, maximumHeight: CGFloat(height), detailsStore: store).frame(width: 360).padding(20).background(PlazaStyle.paper))
            let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 400, height: height + 40), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try png.write(to: root.appendingPathComponent("balatro-preview-\(height).png"))
            window.orderOut(nil)
        }
        await model.flush()
        try await model.storage.endSession()
    }
}
