import XCTest
@testable import MacPlaza

final class DiagnosticsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var summary: PlazaDiagnosticSummary {
        PlazaDiagnosticSummary(version: "0.test", build: "42", macOS: "Test macOS", architecture: "arm64",
                               safeMode: true, recoveryRequired: true, wallpaperEnabled: false,
                               originalFacesInstalled: false, originalBodiesInstalled: false)
    }
    private func fixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reports = root.appendingPathComponent("Reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, reports)
    }
    private func report(_ name: String, text: String, directory: URL, age: TimeInterval = 0) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }
    private func unpack(_ zip: URL, root: URL) throws -> URL {
        let output = root.appendingPathComponent("Unpacked")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, output.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return output.appendingPathComponent("MacPlazaDiagnostics")
    }

    func testZIPIncludesOnlyRecentMatchingReportsAndNoPlazaData() throws {
        try fixture { root, directory in
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let original = "{\"app_name\":\"MacPlaza\"}\n{\"procPath\":\"\(home)/Applications/Mac Plaza.app\",\"threads\":[]}"
            let source = try report("MacPlaza-modern.ips", text: original, directory: directory)
            _ = try report("MacPlaza_legacy.crash", text: "Process: MacPlaza [12]\nIdentifier: local.macplaza.app\nStack trace", directory: directory, age: 60)
            _ = try report("OtherApp-recent.ips", text: "{\"app_name\":\"OtherApp\"}", directory: directory)
            _ = try report("MacPlaza-renamed.ips", text: "{\"app_name\":\"OtherApp\"}", directory: directory)
            _ = try report("MacPlaza-malformed.ips", text: "invalid", directory: directory)
            _ = try report("MacPlaza-old.ips", text: original, directory: directory, age: 31 * 86400)
            _ = try report("plaza.json", text: "SECRET_NOTES_AND_MII_DATA", directory: directory)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("MacPlaza-link.ips"), withDestinationURL: source)
            let zip = root.appendingPathComponent("Diagnostics.zip")
            let result = try PlazaDiagnostics.export(to: zip, summary: summary, directories: [directory], now: now)
            XCTAssertEqual(result.reportCount, 2)
            let unpacked = try unpack(zip, root: root)
            let names = try FileManager.default.contentsOfDirectory(atPath: unpacked.appendingPathComponent("Crash Reports").path)
            XCTAssertEqual(Set(names), Set(["Crash-01.ips", "Crash-02.crash"]))
            let copied = try String(contentsOf: unpacked.appendingPathComponent("Crash Reports/Crash-01.ips"), encoding: .utf8)
            XCTAssertFalse(copied.contains(home)); XCTAssertTrue(copied.contains("~/Applications"))
            XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), original, "Never edit original crash reports")
            let manifestData = try Data(contentsOf: unpacked.appendingPathComponent("Summary.json"))
            let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let system = try XCTUnwrap(manifest["system"] as? [String: Any])
            XCTAssertEqual(system["build"] as? String, "42")
            XCTAssertEqual(system["recoveryRequired"] as? Bool, true)
            XCTAssertFalse(String(decoding: manifestData, as: UTF8.self).contains("SECRET"))
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: unpacked.path)), Set(["Crash Reports", "Summary.json", "Read Me.txt", "Tester Notes.txt"]))
        }
    }

    func testReportCountAndByteLimits() throws {
        try fixture { root, directory in
            for index in 0..<12 {
                _ = try report("MacPlaza-\(index).crash", text: "Process: MacPlaza [1]\n", directory: directory, age: Double(index))
            }
            let result = try PlazaDiagnostics.export(to: root.appendingPathComponent("Ten.zip"), summary: summary, directories: [directory], now: now)
            XCTAssertEqual(result.reportCount, 10)
            let large = root.appendingPathComponent("Large")
            try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)
            for index in 0..<6 {
                _ = try report("MacPlaza-\(index).crash", text: "Process: MacPlaza [1]\n" + String(repeating: "x", count: 4_900_000), directory: large)
            }
            _ = try report("MacPlaza-oversize.crash", text: "Process: MacPlaza [1]\n" + String(repeating: "x", count: 5_000_000), directory: large)
            let bounded = try PlazaDiagnostics.export(to: root.appendingPathComponent("Bounded.zip"), summary: summary, directories: [large], now: now)
            XCTAssertEqual(bounded.reportCount, 4, "Total report bytes must stay below 20 MB")
        }
    }

    func testNoCrashStillExportsSummaryAndFailedDestinationPreservesData() throws {
        try fixture { root, directory in
            let zip = root.appendingPathComponent("Empty.zip")
            let result = try PlazaDiagnostics.export(to: zip, summary: summary, directories: [directory, root.appendingPathComponent("Missing")], now: now)
            XCTAssertEqual(result.reportCount, 0)
            let unpacked = try unpack(zip, root: root)
            XCTAssertTrue(try String(contentsOf: unpacked.appendingPathComponent("Read Me.txt"), encoding: .utf8).contains("Included crash reports: 0"))
            XCTAssertEqual(try String(contentsOf: unpacked.appendingPathComponent("Tester Notes.txt"), encoding: .utf8), "No description provided.\n")
            let sentinel = try report("Preserved.txt", text: "keep me", directory: directory)
            XCTAssertThrowsError(try PlazaDiagnostics.export(to: directory, summary: summary, directories: [], now: now))
            XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep me")
        }
    }

    func testTesterDescriptionSurvivesZIPWithUnicodeAndLineBreaksAndIsBounded() throws {
        try fixture { root, directory in
            let description = "Opened Mii Maker → changed eyes.\nClicked Save, then the plaza froze. 😕\nSteps: repeat twice."
            let zip = root.appendingPathComponent("WithNotes.zip")
            _ = try PlazaDiagnostics.export(to: zip, summary: summary, testerDescription: description, directories: [directory], now: now)
            let unpacked = try unpack(zip, root: root)
            XCTAssertEqual(try String(contentsOf: unpacked.appendingPathComponent("Tester Notes.txt"), encoding: .utf8), description + "\n")
            let original = try Data(contentsOf: zip)
            XCTAssertThrowsError(try PlazaDiagnostics.export(to: zip, summary: summary,
                testerDescription: String(repeating: "x", count: PlazaDiagnostics.maximumDescriptionLength + 1), directories: [], now: now))
            XCTAssertEqual(try Data(contentsOf: zip), original, "An over-limit description must not replace an existing export")
        }
    }
}
