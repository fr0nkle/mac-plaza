import SwiftUI
import AppKit
import PlazaCore

/// App metadata stays local; Steam previews can also use public store details.
struct AppPreviewInfo {
    let version: String?
    let category: String
    let summary: String
    let location: String?

    init(app: AppIsland, url: URL?) {
        if app.steamAppID != nil {
            version = nil; category = "Steam game"; location = "Steam library"
            summary = "Launch \(app.label) through Steam, using your saved Steam launch options. Leave a note here for your next visit."
            return
        }
        let bundle = url.flatMap(Bundle.init(url:))
        version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let rawCategory = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        category = rawCategory.map { $0.replacingOccurrences(of: "public.app-category.", with: "").replacingOccurrences(of: "-", with: " ").capitalized } ?? "Mac application"
        location = url?.deletingLastPathComponent().lastPathComponent
        switch app.bundleID.lowercased() {
        case let id where id.contains("brave") || id.contains("safari") || id.contains("chrome") || id.contains("firefox"):
            summary = "Explore the web, return to your favorite sites, and pick up where you left off."
        case let id where id.contains("discord"):
            summary = "Spend time with your communities through conversations, voice chats, and shared moments."
        case let id where id.contains("resolve"):
            summary = "Bring your next story to life with video editing, color, visual effects, and sound."
        case "com.apple.music": summary = "Find something to listen to and return to the music you love."
        case "com.apple.notes": summary = "Capture a thought, make a list, or return to an idea you've been keeping."
        case "com.apple.ical": summary = "See what's coming up and make a little room for what matters."
        case "com.apple.photos": summary = "Revisit your photos, organize your memories, and find a favorite moment."
        case "com.apple.mobileSMS".lowercased(): summary = "Pick up a conversation with the people you care about."
        default: summary = bundle?.object(forInfoDictionaryKey: "NSHumanReadableDescription") as? String ?? "A little space for \(app.label) in your plaza. Open it when you're ready, or leave a note for your next visit."
        }
    }
}

struct AppPreviewView: View {
    @ObservedObject var model: PlazaModel
    let app: AppIsland
    let close: () -> Void
    var maximumHeight: CGFloat = 510
    var detailsStore: SteamGameDetailsStore = .shared
    @State private var steamDetails: SteamGameDetails?
    @State private var detailsLoading = false
    private var url: URL? { model.resolvedURL(app) }
    private var notes: [LocalNote] { model.notes(for: app) }

    var body: some View {
        let info = AppPreviewInfo(app: app, url: url)
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                description(info: info)
            }.scrollIndicators(.hidden)
            HStack(spacing: 9) {
                Label(url == nil ? "Needs reconnecting" : "Ready to open", systemImage: url == nil ? "link.badge.plus" : "checkmark.circle")
                if let version = info.version { Text("v\(version)").lineLimit(1) }
            }.font(.system(size: 10)).foregroundStyle(PlazaStyle.teal)
            Button {
                if url == nil { model.pickApp(replacing: app) }
                else { close(); model.launch(app) }
            } label: {
                Label(url == nil ? "Locate App…" : "Open \(app.label)", systemImage: url == nil ? "folder" : "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(PlazaStyle.teal).keyboardShortcut(.defaultAction)
                .disabled(model.launching.contains(app.id))
            Divider().opacity(0.5)
            HStack {
                Button(notes.isEmpty ? "Leave a note" : "Read notes") {
                    if let note = notes.first { model.openJournal(note: note.id) }
                    else { model.sheet = .compose(app.id) }
                }
                Spacer()
                Button(model.document.apps.contains(where: { $0.id == app.id }) ? "Shortcut settings…" : "Pin to saved layout") {
                    if model.document.apps.contains(where: { $0.id == app.id }) { model.sheet = .app(app) }
                    else { model.pinHomeApp(app) }
                }
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(PlazaStyle.teal)
        }
        .padding(23)
        .frame(height: min(app.steamAppID != nil ? 510 : 400, maximumHeight))
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .leading) {
            PlazaInfoTail().fill(.white.opacity(0.96)).frame(width: 18, height: 30).offset(x: -16)
        }
        .shadow(color: PlazaStyle.ink.opacity(0.12), radius: 15, y: 7)
        .accessibilityElement(children: .contain)
        .foregroundStyle(PlazaStyle.ink)
        .preferredColorScheme(.light)
        .onExitCommand(perform: close)
        .task(id: app.steamAppID) {
            steamDetails = nil
            detailsLoading = false
            guard let id = app.steamAppID else { return }
            detailsLoading = true
            let cached = await detailsStore.cached(appID: id)
            guard !Task.isCancelled else { return }
            steamDetails = cached
            let details = await detailsStore.details(appID: id)
            guard !Task.isCancelled else { return }
            steamDetails = details
            detailsLoading = false
        }
    }

    @ViewBuilder private func description(info: AppPreviewInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = app.steamAppID {
                if maximumHeight < 430 {
                    HStack(alignment: .center, spacing: 12) {
                        coverArt(appID: id, height: 60).frame(width: 100)
                        VStack(alignment: .leading, spacing: 6) { title(info: info) }
                    }
                } else {
                    coverArt(appID: id, height: 150)
                    title(info: info)
                }
            } else { title(info: info) }
            AppFriendsView(model: model, social: model.social, app: app, close: close)
            let summary = steamDetails?.appID == app.steamAppID ? steamDetails?.summary : nil
            Text(summary ?? info.summary).font(.system(size: 13)).lineSpacing(3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if summary != nil { Text("From the Steam store").font(.system(size: 10)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func title(info: AppPreviewInfo) -> some View {
        Text(info.category.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(PlazaStyle.teal)
        Text(app.label).font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func coverArt(appID: UInt32, height: CGFloat) -> some View {
        let details = steamDetails?.appID == appID ? steamDetails : nil
        if let data = details?.artwork, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity).frame(height: height)
                .background(PlazaStyle.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("\(app.label) cover art")
        } else {
            HStack(spacing: 8) {
                Image(nsImage: model.icon(app)).resizable().scaledToFit().frame(width: min(64, height), height: min(64, height)).accessibilityHidden(true)
                if detailsLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading game details") }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
        }
    }
}

private struct PlazaInfoTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.midY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.midY))
            p.closeSubpath()
        }
    }
}
