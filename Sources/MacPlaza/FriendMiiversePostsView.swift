import SwiftUI
import PlazaCore

/// A friend's content is selected by verified account ownership, never by
/// nickname, local Mii choice or the legacy profile-note field.
struct FriendMiiversePostsView: View {
    @ObservedObject var model: PlazaModel
    @ObservedObject var social: SocialController
    let friend: SharedMii
    var compact = false
    var body: some View {
        let posts = social.miiversePosts(for: friend)
        if compact, let post = posts.first {
            VStack(alignment: .leading, spacing: 4) {
                Text("Miiverse post").font(.caption).foregroundStyle(PlazaStyle.teal)
                Text(post.text.isEmpty ? post.drawingDescription : post.text).font(.callout).lineLimit(3)
            }
        } else if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Miiverse Posts").font(.headline)
                ForEach(Array(posts.prefix(3))) { post in
                    PlazaButton { model.openMiiverse(note: post.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if !post.text.isEmpty { Text(post.text).font(.callout).lineLimit(4) }
                            if !post.drawing.isEmpty {
                                InkCanvas(strokes: post.drawing).frame(width: 160, height: 160).accessibilityLabel(post.drawingDescription)
                            }
                            Text("View Miiverse post").font(.caption).foregroundStyle(PlazaStyle.teal)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityLabel("View \(post.publicDisplayName)’s Miiverse post: \(post.text.isEmpty ? post.drawingDescription : post.text)")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
