import AppKit
import SwiftUI
import PlazaCore

@MainActor
enum MiiHeadPictures {
    static func key(for avatar: Avatar) -> String {
        String(describing: avatar) + "-\(FFLResources.shared.installed)-\(FFLResources.shared.revision)-\(PlazaBodyResources.shared.revision)"
    }

    static func fallback(_ avatar: Avatar) -> NSImage {
        AvatarArtwork.headshot(avatar, size: CGSize(width: 128, height: 128))
    }

    static func image(_ avatar: Avatar) async -> NSImage {
        if FFLResources.shared.installed,
           let image = try? await FFLPortraits.shared.image(avatar, headOnly: true, width: 128, height: 128) {
            return image
        }
        return fallback(avatar)
    }
}

struct MiiHeadIcon: View {
    let avatar: Avatar
    @ObservedObject private var resource = FFLResources.shared
    @ObservedObject private var bodyResource = PlazaBodyResources.shared
    @State private var image: NSImage?
    var body: some View {
        Image(nsImage: image ?? MiiHeadPictures.fallback(avatar))
            .resizable().scaledToFit().padding(2)
            .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.9), lineWidth: 1) }
            .accessibilityHidden(true)
            .task(id: MiiHeadPictures.key(for: avatar)) {
                image = MiiHeadPictures.fallback(avatar)
                let head = await MiiHeadPictures.image(avatar)
                guard !Task.isCancelled else { return }
                image = head
            }
    }
}
