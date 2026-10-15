import SwiftUI
import PlazaCore

enum MiiversePage: String { case user = "User Menu", feed = "Activity Feed", communities = "Communities", notifications = "Notifications" }

/// A responsive Miiverse shell. Feed, communities and account setup retain
/// their own state without replacing the plaza's native presentation route.
struct MiiverseView: View {
    @ObservedObject var model: PlazaModel
    var authorID: UUID?
    var onClose: (() -> Void)?
    var initialPage: MiiversePage = .feed
    @Environment(\.dismiss) private var dismiss
    @State private var page: MiiversePage = .feed
    @State private var section = "all"
    @State private var query = ""
    @State private var order: [String] = []
    @State private var setup = false
    @State private var alphabetic = false

    var body: some View {
        GeometryReader { proxy in
          let compact = proxy.size.width < 900
          HStack(spacing: 0) {
            MiiverseNavigationRail(model: model, social: model.social, page: $page, compact: compact, onClose: close)
            VStack(spacing: 0) {
                HStack {
                    Text(page.rawValue).font(.system(size: 23, weight: .semibold, design: .rounded))
                    Spacer()
                    Label("Miiverse", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }.foregroundStyle(.white).padding(.horizontal, 25).frame(height: 66)
                    .background(LinearGradient(colors: [Color(red: 0.46, green: 0.87, blue: 0.12), MiiverseStyle.green], startPoint: .top, endPoint: .bottom))
                Group {
                    switch page {
                    case .user: MiiverseAccountView(model: model, social: model.social) { setup = true }
                    case .notifications:
                        PlazaActivityView(model: model, social: model.social, onClose: { page = .feed }, fillsContent: true)
                    case .feed, .communities:
                        if page == .communities && section == "all" { communities(compact: compact) }
                        else {
                            MiiversePostsView(model: model, authorID: authorID, section: page == .feed ? .constant("all") : $section,
                                onBack: { section = "all" }, onAccount: { page = .user }, onActivity: { page = .notifications })
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }.background(MiiverseStyle.background).foregroundStyle(PlazaStyle.ink)
        }.frame(minWidth: 720, minHeight: 540).preferredColorScheme(.light)
            .modifier(SocialActivityModifier(model: model))
            .sheet(isPresented: $setup) { SocialSettingsView(model: model, social: model.social) }
            .onAppear { page = authorID == nil ? initialPage : .feed; reshuffle(); revealSelectedNote() }
            .onChange(of: model.selectedNoteID) { _, _ in revealSelectedNote() }
            .onChange(of: page) { _, value in if value == .feed { section = "all" }; if value == .communities { section = "all"; reshuffle() } }
    }
    private func close() { if let onClose { onClose() } else { dismiss() } }
    private func revealSelectedNote() { if model.selectedNoteID != nil { section = "all"; page = .feed } }
    private func reshuffle() {
        var random = SystemRandomNumberGenerator()
        order = model.miiverseCatalog.orderedCommunities(popularity: model.miiversePopularity, using: &random).map(\.id)
    }
    private var orderedCommunities: [MiiverseSection] {
        let communities = model.miiverseCatalog.communities
        let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return communities.sorted {
            if $0.id == "plaza" || $1.id == "plaza" { return $0.id == "plaza" && $1.id != "plaza" }
            if alphabetic { return $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return (ranks[$0.id] ?? Int.max) < (ranks[$1.id] ?? Int.max)
        }
    }
    private func communities(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Spotlight", systemImage: "sparkles").font(.system(size: 16, weight: .semibold)).foregroundStyle(MiiverseStyle.blue)
                    .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 10))
                ForEach(Array(orderedCommunities.filter { $0.id != "plaza" }.prefix(compact ? 3 : 5))) { item in
                    PlazaButton { section = item.id } label: { MiiverseCommunityIcon(model: model, item: item, size: 56) }
                        .buttonStyle(.plain).accessibilityLabel("Open \(item.label) community")
                }
                Spacer(minLength: 0)
            }.padding(20)
            HStack {
                Text("Communities").font(.system(size: 18, weight: .semibold))
                Spacer()
                TextField("Find a community", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 220).accessibilityLabel("Find a community")
                Menu {
                    PlazaButton(alphabetic ? "✓ Name" : "Name") { alphabetic = true }
                    PlazaButton(!alphabetic ? "✓ Popular apps" : "Popular apps") { alphabetic = false; reshuffle() }
                } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize()
                PlazaButton { reshuffle() } label: { Image(systemName: "shuffle") }.buttonStyle(.plain).accessibilityLabel("Shuffle popular communities")
            }.foregroundStyle(.white).padding(.horizontal, 18).frame(height: 48)
                .background(LinearGradient(colors: [MiiverseStyle.blue, Color(red: 0.10, green: 0.61, blue: 0.84)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 20)
            ScrollView {
                LazyVGrid(columns: compact ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    ForEach(orderedCommunities.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }) { item in
                        PlazaButton { section = item.id } label: {
                            HStack(spacing: 14) {
                                MiiverseCommunityIcon(model: model, item: item, size: 66)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.label).font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(2)
                                    Text("\(item.count) \(item.count == 1 ? "post" : "posts")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(15).frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 15))
                                .padding(5)
                        }.buttonStyle(.plain).accessibilityLabel("\(item.label), \(item.count) posts")
                    }
                }.padding(15)
                if !query.isEmpty && !orderedCommunities.contains(where: { $0.label.localizedCaseInsensitiveContains(query) }) {
                    Text("No communities found.").foregroundStyle(.secondary).padding(30)
                }
            }
            Text("Plaza is always first. Other communities rotate with popular apps, recent activity and posts.")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }.background(MiiversePattern())
    }
}

private struct MiiverseNavigationRail: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    @Binding var page: MiiversePage
    var compact = false
    let onClose: () -> Void
    private var railWidth: CGFloat { compact ? 84 : 104 }
    var body: some View {
        VStack(spacing: 0) {
            PlazaButton { page = .user } label: {
                VStack(spacing: 5) {
                    MiiHeadIcon(avatar: model.document.primaryAvatar).frame(width: 42, height: 48).background(.white, in: RoundedRectangle(cornerRadius: 9))
                    Text("User Menu").font(.system(size: 11, weight: .medium))
                }.frame(width: railWidth, height: 99).background(page == .user ? .white : .clear)
            }.buttonStyle(.plain).accessibilityLabel("User Menu, Discord account and setup")
            railItem(.feed, icon: "text.bubble")
            railItem(.communities, icon: "person.3.fill")
            railItem(.notifications, icon: "bell")
            Spacer(minLength: 0)
            PlazaButton(action: onClose) {
                VStack(spacing: 7) { Image(systemName: "xmark").font(.system(size: 30, weight: .bold)); Text("Close").font(.caption) }
                    .foregroundStyle(.white).frame(width: railWidth, height: 88).background(Color(white: 0.24))
            }.buttonStyle(.plain).accessibilityLabel("Close Miiverse")
        }.frame(width: railWidth).background(Color(white: 0.94)).overlay(alignment: .trailing) { Divider() }
    }
    private func railItem(_ item: MiiversePage, icon: String) -> some View {
        PlazaButton { page = item } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 30))
                    .overlay(alignment: .topTrailing) { if item == .notifications { PlazaUnreadActivityBadge(count: social.unreadActivityCount).offset(x: 14, y: -6) } }
                Text(item.rawValue).font(.system(size: 11, weight: .medium))
            }.foregroundStyle(page == item ? MiiverseStyle.green : Color(white: 0.47))
                .frame(width: railWidth, height: 98).background(page == item ? .white.opacity(0.85) : .clear)
                .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.10)).frame(height: 1).padding(.horizontal, 9) }
        }.buttonStyle(.plain).accessibilityLabel(item == .notifications ? "Notifications, \(social.unreadActivityCount) unread" : item.rawValue)
            .accessibilityAddTraits(page == item ? .isSelected : [])
    }
}

private struct MiiverseCommunityIcon: View {
    @ObservedObject var model: PlazaModel
    let item: MiiverseSection
    let size: CGFloat
    var body: some View {
        Group {
            if let id = item.appID, let app = model.topicApps.first(where: { $0.id == id }) {
                Image(nsImage: model.icon(app)).resizable().scaledToFit()
            } else {
                Image(systemName: item.id == "plaza" ? "sun.max.fill" : "app.fill")
                    .resizable().scaledToFit().padding(size * 0.18).foregroundStyle(item.id == "plaza" ? MiiverseStyle.green : MiiverseStyle.blue)
            }
        }.frame(width: size, height: size).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.10), radius: 2, y: 2).accessibilityHidden(true)
    }
}

private struct MiiverseAccountView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    let onSetup: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    MiiHeadIcon(avatar: model.document.primaryAvatar).frame(width: 80, height: 94)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(social.account?.displayName ?? model.document.primaryAvatar.name).font(.title2.bold())
                        Label(social.hasSession ? "Discord account linked" : "Connect with Discord", systemImage: social.hasSession ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                            .foregroundStyle(MiiverseStyle.green)
                    }
                }
                Text("Discord connects this Miiverse").font(.title3.bold())
                Text("Link your Discord account to browse shared posts, find friends, and publish with your Discord name and primary Mii. Your private notes and drafts stay on this Mac.")
                Text(social.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                PlazaButton(social.hasSession ? "Manage Discord Connection" : "Set Up Discord", action: onSetup)
                    .buttonStyle(.borderedProminent).tint(MiiverseStyle.green)
                Divider()
                MiiverseMusicThemeSettings(model: model)
                Divider()
                MiiverseBirthdaySettings(model: model)
                PlazaButton("Edit Your Mii") { model.sheet = .characters }
            }.padding(30).frame(maxWidth: 720, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 18)).padding(28).frame(maxWidth: .infinity)
        }.background(MiiversePattern())
    }
}

@MainActor
struct MiiverseMusicThemeSettings: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject private var music: PlazaMusicLibrary
    @ObservedObject private var audio: PlazaAudio
    @State private var previewError: String?
    init(model: PlazaModel) { self.model = model; music = model.music; audio = model.audio }
    private var alternateAvailable: Bool { model.hasAlternateMiiverseMusic }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Miiverse music").font(.headline)
            Toggle("Use Alternate Miiverse Music", isOn: Binding(
                get: { model.document.preferences.miiverseAlternateTheme == true },
                set: { value in audio.stopPreview(); model.mutate { $0.preferences.miiverseAlternateTheme = value }; model.updateAudio() }
            )).disabled(!alternateAvailable)
            Text(alternateAvailable ? "Alternate theme: eShop (July 2014) · Wii U" : "Choose a local audio file for the eShop (July 2014) alternate theme. Current Miiverse music stays active until you apply it.")
                .font(.callout).foregroundStyle(.secondary)
            PlazaButton("Choose Alternate Theme Audio") {
                audio.stopPreview(); previewError = nil; music.choose(for: .miiverseAlternate)
            }
            if let selection = music.selections[PlazaAudio.Track.miiverseAlternate.rawValue] {
                Text("Selected: \(selection.name)").font(.caption).textSelection(.enabled)
            } else if alternateAvailable {
                Text(music.title(for: .miiverseAlternate)).font(.caption).foregroundStyle(.secondary)
            }
            if music.previewURL(for: .miiverseAlternate) != nil {
                HStack {
                    PlazaButton(audio.previewTrack == .miiverseAlternate ? "Stop Preview" : "Preview Alternate Theme") {
                        previewError = nil
                        if audio.previewTrack == .miiverseAlternate { audio.stopPreview() }
                        else if let url = music.previewURL(for: .miiverseAlternate) {
                            do { try audio.preview(url, track: .miiverseAlternate, volume: model.document.preferences.miiverseMusicVolume ?? 0.10) }
                            catch { previewError = "Could not preview music: \(error.localizedDescription)" }
                        }
                    }.disabled(model.document.preferences.safeMode || model.automaticMusicMuteReason != nil)
                    if music.selections[PlazaAudio.Track.miiverseAlternate.rawValue] != nil {
                        PlazaButton("Apply Alternate Theme") {
                            audio.stopPreview(); music.applySelection(for: .miiverseAlternate)
                            if music.selections[PlazaAudio.Track.miiverseAlternate.rawValue] == nil && alternateAvailable {
                                model.mutate { $0.preferences.miiverseAlternateTheme = true }; model.updateAudio()
                            }
                        }.buttonStyle(.borderedProminent).tint(MiiverseStyle.green)
                        PlazaButton("Cancel") { audio.stopPreview(); music.discardSelection(for: .miiverseAlternate) }
                    }
                }
            }
            if let previewError { Text(previewError).font(.caption).foregroundStyle(.red) }
            if let message = music.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.onDisappear { audio.stopPreview(); music.discardSelection(for: .miiverseAlternate) }
    }
}

private enum MiiverseStyle {
    static let green = Color(red: 0.33, green: 0.70, blue: 0.08)
    static let blue = Color(red: 0.05, green: 0.65, blue: 0.76)
    static let background = Color(white: 0.94)
}
private struct MiiversePattern: View {
    var body: some View {
        Canvas { context, size in
            for row in 0..<Int(size.height / 84 + 1) {
                for column in 0..<Int(size.width / 84 + 1) where (row + column) % 2 == 0 {
                    context.fill(Path(roundedRect: CGRect(x: column * 84, y: row * 84, width: 80, height: 80), cornerRadius: 16), with: .color(.white.opacity(0.38)))
                }
            }
        }.background(MiiverseStyle.background).accessibilityHidden(true)
    }
}
