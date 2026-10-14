import AppKit
import SwiftUI
import PlazaCore

struct SteamGamePicker: View {
    @ObservedObject var model: PlazaModel
    var replacing: AppIsland?
    @State private var games: [SteamGames.Game] = []
    @State private var selected: Set<UInt32> = []
    @State private var search = ""
    @State private var loading = true

    private var filtered: [SteamGames.Game] {
        games.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private func alreadyAdded(_ game: SteamGames.Game) -> Bool {
        replacing == nil && model.document.apps.contains { $0.steamAppID == game.id || $0.path == game.applicationURL.path }
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: replacing == nil ? "Add Steam games" : "Choose a Steam game",
                        subtitle: "Installed Mac games from your Steam libraries.", backToPlaza: model.returnToPlaza) { model.returnToPlaza() }
            VStack(alignment: .leading, spacing: 14) {
                TextField("Find a Steam game", text: $search).textFieldStyle(.roundedBorder)
                if loading {
                    ProgressView("Looking for installed games…").frame(maxWidth: .infinity, minHeight: 220)
                } else if games.isEmpty {
                    ContentUnavailableView("No installed Mac games found", systemImage: "gamecontroller",
                                           description: Text("Install a Mac version of a game in Steam, then choose Refresh. Games on disconnected drives will appear when the drive is available."))
                        .frame(height: 220)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { game in
                                PlazaButton {
                                    if replacing != nil { selected = [game.id] }
                                    else if !selected.insert(game.id).inserted { selected.remove(game.id) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: game.applicationURL.path)).resizable().scaledToFit().frame(width: 42, height: 42)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(game.name).font(.system(.body, design: .rounded, weight: .semibold))
                                            Text(alreadyAdded(game) ? "Already on your home screen" : "Installed · Opens with Steam").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: alreadyAdded(game) || selected.contains(game.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(PlazaStyle.teal)
                                    }.padding(10).contentShape(Rectangle())
                                        .background(selected.contains(game.id) ? PlazaStyle.teal.opacity(0.10) : .white, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).disabled(alreadyAdded(game))
                                    .accessibilityLabel(game.name)
                                    .accessibilityValue(alreadyAdded(game) ? "Already added" : selected.contains(game.id) ? "Selected" : "Not selected")
                            }
                            if filtered.isEmpty { Text("No games match your search.").foregroundStyle(.secondary).padding() }
                        }
                    }.frame(height: 260)
                }
                Text("Games keep their own icons and open through Steam. Only games installed for Mac are shown.").font(.caption).foregroundStyle(.secondary)
                if replacing == nil, selected.count > 120 - model.document.apps.count {
                    Text("There is room for \(120 - model.document.apps.count) more shortcuts. Select fewer games to continue.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    PlazaButton("Refresh") { Task { await refresh() } }.disabled(loading)
                    Spacer()
                    PlazaButton("Cancel") { model.returnToPlaza() }
                    PlazaButton(replacing == nil ? "Add to Home Screen" : "Use Game") {
                        let urls = games.filter { selected.contains($0.id) && !alreadyAdded($0) }.map(\.applicationURL)
                        model.addApps(urls, replacing: replacing)
                        if model.error == nil {
                            if let first = games.first(where: { selected.contains($0.id) }),
                               let index = model.document.apps.firstIndex(where: { $0.steamAppID == first.id }) { model.page = index / 12 }
                            model.returnToPlaza()
                        }
                    }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal)
                        .disabled(selected.isEmpty || selected.count > (replacing == nil ? 120 - model.document.apps.count : 1))
                }
            }.padding(22)
        }.frame(width: 570).background(PlazaStyle.paper)
            .task { await refresh() }
    }
    private func refresh() async {
        loading = true
        let installed = await Task.detached(priority: .userInitiated) { SteamGames.installed() }.value
        guard !Task.isCancelled else { return }
        games = installed
        selected = selected.intersection(Set(games.filter { !alreadyAdded($0) }.map(\.id)))
        loading = false
    }
}
