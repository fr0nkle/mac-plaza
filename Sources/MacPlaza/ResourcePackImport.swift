import AppKit
import UniformTypeIdentifiers
import PlazaCore

extension PlazaModel {
    func importResourcePack() {
        guard !resourcePackBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Plaza Resource Pack"
        panel.allowedContentTypes = [UTType(filenameExtension: "plazapack") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the .plazapack file you received. Your saved Miis, notes and apps will stay in place."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        resourcePackBusy = true; resourcePackMessage = "Checking resource pack…"
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; resourcePackBusy = false }
            do {
                let pack = try await Task.detached(priority: .userInitiated) { try PlazaResourcePack.prepare(url) }.value
                defer { pack.discard() }
                let alert = NSAlert()
                alert.messageText = "Import \(pack.manifest.name)?"
                alert.informativeText = "This adds the original Wii U faces and bodies, \(pack.animationCount) animations and \(pack.music.count) menu music tracks. Included resources and music replace your current selections, with a backup. Your saved Miis, notes, apps, account and volume settings stay unchanged."
                alert.addButton(withTitle: "Import Pack")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { resourcePackMessage = "Resource pack import cancelled."; return }
                resourcePackMessage = "Checking the original Mii renderer…"
                let surface = FFLSurface(mode: "portrait", resource: try FFLResources.checkedData(at: pack.faces),
                                         bodyResource: try Data(contentsOf: pack.bodies), useInstalledBody: false)
                defer { surface.invalidate() }
                try await surface.waitUntilReady()
                var avatar = Avatar(name: "Pack check")
                _ = try await surface.portrait(avatar, width: 96, height: 144)
                avatar.features.gender = 1
                _ = try await surface.portrait(avatar, width: 96, height: 144)
                resourcePackMessage = "Installing resources and music…"
                let root = storage.url.deletingLastPathComponent()
                let result = try await Task.detached(priority: .userInitiated) { try PlazaResourcePack.install(pack, at: root) }.value
                FFLResources.shared.reloadInstalled()
                PlazaBodyResources.shared.reloadInstalled()
                music.reloadInstalled()
                rebuildScene(); updateAudio()
                resourcePackBackup = result.backup
                resourcePackMessage = "Original Wii U faces, bodies, \(pack.animationCount) animations and \(result.musicCount) music tracks installed."
                if document.preferences.safeMode { resourcePackMessage! += " Turn off Safe mode in System & Recovery to display them." }
            } catch { resourcePackMessage = "Resource pack was not installed: \(error.localizedDescription)" }
        }
    }
}
