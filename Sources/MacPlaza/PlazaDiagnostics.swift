import AppKit
import UniformTypeIdentifiers

/// Deliberately contains no plaza document, account information or local app paths.
struct PlazaDiagnosticSummary: Codable, Sendable {
    var version: String
    var build: String
    var macOS: String
    var architecture: String
    var safeMode: Bool
    var recoveryRequired: Bool
    var wallpaperEnabled: Bool
    var originalFacesInstalled: Bool
    var originalBodiesInstalled: Bool
    var previousSessionInterrupted = false
}

enum PlazaDiagnostics {
    static let maximumDescriptionLength = 10_000
    static let supportEmail = "alexanderhosier@squidproductions.org"
    struct Result: Sendable { let reportCount: Int }
    private struct Manifest: Encodable {
        let exportedAt: Date
        let system: PlazaDiagnosticSummary
        let reports: [String]
        let skippedReports: Int
        let unavailableReportFolders: Int
    }
    static var reportDirectories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
         URL(fileURLWithPath: "/Library/Logs/DiagnosticReports", isDirectory: true)]
    }

    /// Runs off the main thread. Only Mac Plaza reports from the last 30 days are read.
    static func export(to destination: URL, summary: PlazaDiagnosticSummary,
                       testerDescription: String = "",
                       directories: [URL] = reportDirectories, now: Date = Date()) throws -> Result {
        guard testerDescription.count <= maximumDescriptionLength else { throw ExportError.descriptionTooLong }
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("MacPlazaDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("MacPlazaDiagnostics", isDirectory: true)
        let reports = root.appendingPathComponent("Crash Reports", isDirectory: true)
        try fm.createDirectory(at: reports, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var candidates: [(URL, Date)] = []
        var unavailable = 0, skipped = 0
        for directory in directories {
            guard fm.fileExists(atPath: directory.path) else { continue }
            do {
                for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
                    let name = url.lastPathComponent.lowercased()
                    guard ["macplaza-", "mac plaza-", "macplaza_", "mac plaza_"].contains(where: name.hasPrefix),
                          ["ips", "crash"].contains(url.pathExtension.lowercased()) else { continue }
                    guard let values = try? url.resourceValues(forKeys: keys),
                          values.isRegularFile == true, values.isSymbolicLink != true,
                          let date = values.contentModificationDate,
                          date >= now.addingTimeInterval(-30 * 24 * 60 * 60) else { continue }
                    guard let size = values.fileSize, size > 0, size <= 5_000_000 else { skipped += 1; continue }
                    candidates.append((url, date))
                }
            } catch { unavailable += 1 }
        }
        candidates.sort { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
        var included: [String] = [], totalBytes = 0
        for (url, _) in candidates {
            guard included.count < 10, totalBytes < 20_000_000 else { skipped += 1; continue }
            // Bound the read even if a report grows after the directory scan.
            guard let handle = try? FileHandle(forReadingFrom: url) else { skipped += 1; continue }
            let data = try? handle.read(upToCount: 5_000_001)
            try? handle.close()
            guard let data, data.count <= 5_000_000, totalBytes + data.count <= 20_000_000,
                  let text = String(data: data, encoding: .utf8), belongsToPlaza(text, extension: url.pathExtension.lowercased()) else {
                skipped += 1; continue
            }
            let name = String(format: "Crash-%02d", included.count + 1) + "." + url.pathExtension.lowercased()
            // Keep Apple's stack traces intact while removing this user's home path.
            let redacted = text.replacingOccurrences(of: fm.homeDirectoryForCurrentUser.path, with: "~")
            try Data(redacted.utf8).write(to: reports.appendingPathComponent(name), options: .atomic)
            included.append(name); totalBytes += data.count
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Manifest(exportedAt: now, system: summary, reports: included,
                                   skippedReports: skipped, unavailableReportFolders: unavailable))
            .write(to: root.appendingPathComponent("Summary.json"), options: .atomic)
        let description = testerDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        try Data((description.isEmpty ? "No description provided.\n" : description + "\n").utf8)
            .write(to: root.appendingPathComponent("Tester Notes.txt"), options: .atomic)
        let readme = """
        Mac Plaza Diagnostics

        Included crash reports: \(included.count)
        Up to 10 Mac Plaza reports from the last 30 days are included, newest first.
        Reports larger than 5 MB are skipped; total report content is limited to 20 MB.
        Summary.json lists the app build, macOS version and basic renderer/recovery state.
        Tester Notes.txt contains the optional description entered during export.
        No saved plaza, Miis, notes, Discord credentials or custom music are collected.
        This user's home directory is replaced with ~ in reports. Reports can still
        contain other file paths and system information; review before sharing.

        Nothing is uploaded. Email this ZIP to \(supportEmail), together with what you
        were doing, the approximate crash time, and steps to reproduce the issue.
        If there are no reports, macOS may not have recorded one (for example after
        a forced quit or a hang). The build/system summary is still useful.
        Skipped reports: \(skipped). Unavailable report folders: \(unavailable).
        """
        try Data(readme.utf8).write(to: root.appendingPathComponent("Read Me.txt"), options: .atomic)
        let archive = temporary.appendingPathComponent("Diagnostics.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", root.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExportError.archiveFailed }
        // Atomic replacement leaves an existing destination intact on failure.
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
        return Result(reportCount: included.count)
    }

    private static func belongsToPlaza(_ text: String, extension ext: String) -> Bool {
        let names = ["MacPlaza", "Mac Plaza"]
        if ext == "ips" {
            // Apple IPS contains a metadata JSON line followed by the report JSON.
            let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
            for part in parts {
                guard let object = try? JSONSerialization.jsonObject(with: Data(part.utf8)) as? [String: Any] else { continue }
                if names.contains(object["app_name"] as? String ?? "") || names.contains(object["procName"] as? String ?? "") { return true }
                if object["bundleID"] as? String == "local.macplaza.app" { return true }
                if let bundle = object["bundleInfo"] as? [String: Any], bundle["CFBundleIdentifier"] as? String == "local.macplaza.app" { return true }
            }
            return false
        }
        return text.split(separator: "\n").contains { line in
            line.hasPrefix("Process:") && names.contains { name in
                line.dropFirst("Process:".count).trimmingCharacters(in: .whitespaces).hasPrefix(name + " [")
            }
        }
    }
    private enum ExportError: LocalizedError {
        case archiveFailed, descriptionTooLong
        var errorDescription: String? {
            switch self {
            case .archiveFailed: "The diagnostics ZIP could not be created. Please try another save location."
            case .descriptionTooLong: "The crash description must be 10,000 characters or fewer."
            }
        }
    }
}

extension PlazaModel {
    func exportDiagnostics() {
        guard !diagnosticsExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "MacPlaza-Diagnostics-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).zip"
        panel.title = "Export Diagnostics"
        panel.message = "Save recent Mac Plaza crash reports and build details. Reports can include file paths and system information. Nothing is uploaded."
        let descriptionEditor = DiagnosticsDescriptionAccessory(text: diagnosticsDescriptionDraft)
        panel.accessoryView = descriptionEditor
        let response = panel.runModal()
        diagnosticsDescriptionDraft = descriptionEditor.text
        guard response == .OK, let url = panel.url else { return }
        let testerDescription = diagnosticsDescriptionDraft
        let summary = PlazaDiagnosticSummary(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.diagnosticArchitecture,
            safeMode: document.preferences.safeMode, recoveryRequired: recoveryRequired,
            wallpaperEnabled: wallpaperEnabled, originalFacesInstalled: FFLResources.shared.installed,
            originalBodiesInstalled: PlazaBodyResources.shared.installed,
            previousSessionInterrupted: previousSessionInterrupted)
        diagnosticsExporting = true; diagnosticsExportMessage = nil; diagnosticsExportURL = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try PlazaDiagnostics.export(to: url, summary: summary, testerDescription: testerDescription)
                }.value
                diagnosticsDescriptionDraft = ""
                diagnosticsExportURL = url
                diagnosticsExportMessage = "Diagnostics exported with \(result.reportCount) crash report\(result.reportCount == 1 ? "" : "s"). Send the ZIP with steps to reproduce the issue."
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                diagnosticsExportMessage = "Diagnostics could not be exported: \(error.localizedDescription)"
            }
            diagnosticsExporting = false
        }
    }

    func emailDiagnostics() {
        guard let url = diagnosticsExportURL, FileManager.default.fileExists(atPath: url.path) else {
            diagnosticsExportMessage = "Export diagnostics again to attach the ZIP to an email."
            return
        }
        guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: [url]) else {
            diagnosticsExportMessage = "Email is not available on this Mac. Attach the exported ZIP and send it to \(PlazaDiagnostics.supportEmail)."
            return
        }
        service.recipients = [PlazaDiagnostics.supportEmail]
        service.subject = "Mac Plaza diagnostics"
        service.perform(withItems: ["Crash description and reproduction steps are included in Tester Notes.txt inside the attached diagnostics ZIP.", url])
    }

    func offerDiagnosticsAfterInterruptedSession() {
        guard loaded, diagnosticsRecoveryOfferPending else { return }
        // Window attachment and SwiftUI's startup updates may finish in either order.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.loaded, self.diagnosticsRecoveryOfferPending,
                  self.error == nil, self.sheet == nil, let window = self.window,
                  window.attachedSheet == nil else { return }
            self.diagnosticsRecoveryOfferPending = false
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Mac Plaza didn’t close normally"
            alert.informativeText = "The previous session may have crashed, been force quit or ended during a power loss. Mac Plaza has opened in safe mode.\n\nHelp improve Mac Plaza by exporting diagnostics. You can describe what happened and email the ZIP to \(PlazaDiagnostics.supportEmail). Nothing is sent automatically. You can also export later in Settings → System & Recovery."
            alert.addButton(withTitle: "Export Diagnostics…")
            alert.addButton(withTitle: "Not Now").keyEquivalent = "\u{1b}"
            alert.window.identifier = NSUserInterfaceItemIdentifier("MacPlazaCrashDiagnosticsOffer")
            self.diagnosticsRecoveryAlert = alert
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            alert.beginSheetModal(for: window) { [weak self] response in
                Task { @MainActor in
                    guard let self else { return }
                    self.diagnosticsRecoveryAlert = nil
                    if response == .alertFirstButtonReturn {
                        await Task.yield()
                        self.exportDiagnostics()
                        // Present Settings after the save dialog has finished so
                        // its sheet transition cannot cancel that dialog.
                        self.sheet = .preferences
                    }
                }
            }
        }
    }

    private static var diagnosticArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "Unknown"
        #endif
    }
}

/// AppKit editing remains responsive inside NSSavePanel's modal event loop.
private final class DiagnosticsDescriptionAccessory: NSView, NSTextViewDelegate {
    private let editor = NSTextView()
    private let counter = NSTextField(labelWithString: "")
    var text: String { editor.string }

    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 210))
        let heading = NSTextField(labelWithString: "What were you doing before the crash? (optional)")
        heading.font = .boldSystemFont(ofSize: 13)
        heading.frame = NSRect(x: 16, y: 180, width: 448, height: 20)
        addSubview(heading)
        let hint = NSTextField(wrappingLabelWithString: "Include what you clicked, what happened and any steps to reproduce it. Your description will be included in the ZIP.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 142, width: 448, height: 32)
        addSubview(hint)
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 34, width: 448, height: 102))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        editor.frame = NSRect(origin: .zero, size: scroll.contentSize)
        editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isEditable = true; editor.isSelectable = true
        editor.isRichText = false; editor.font = .systemFont(ofSize: 13)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.setAccessibilityLabel("Crash description")
        editor.string = String(text.prefix(PlazaDiagnostics.maximumDescriptionLength))
        editor.delegate = self
        scroll.documentView = editor; addSubview(scroll)
        counter.frame = NSRect(x: 16, y: 10, width: 448, height: 18)
        counter.font = .systemFont(ofSize: 11); counter.textColor = .secondaryLabelColor
        addSubview(counter); updateCounter()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func textDidChange(_ notification: Notification) {
        if editor.string.count > PlazaDiagnostics.maximumDescriptionLength {
            editor.string = String(editor.string.prefix(PlazaDiagnostics.maximumDescriptionLength))
        }
        updateCounter()
    }
    private func updateCounter() {
        counter.stringValue = "\(editor.string.count.formatted()) / \(PlazaDiagnostics.maximumDescriptionLength.formatted()) characters"
    }
}
