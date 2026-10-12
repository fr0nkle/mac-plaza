import AppKit
import PlazaCore

enum MiiTileFeature: String, CaseIterable {
    case eyes, brows, nose, mouth
    init?(tab: FeatureTab) {
        switch tab {
        case .eyes: self = .eyes
        case .brows: self = .brows
        case .nose: self = .nose
        case .mouth: self = .mouth
        default: return nil
        }
    }
    /// Catalog choices have a consistent scale, independent of the Mii's pose
    /// or adjustments. Retain the selected style ID and its actual color.
    func sample(from avatar: Avatar) -> Avatar {
        var sample = Avatar(name: "Feature")
        sample.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        switch self {
        case .eyes: sample.eyes = avatar.eyes; sample.features.eyeColor = avatar.features.eyeColor
        case .brows: sample.brows = avatar.brows; sample.features.browColor = avatar.features.browColor
        case .nose: sample.nose = avatar.nose; sample.skin = avatar.skin
        case .mouth: sample.mouth = avatar.mouth; sample.features.mouthColor = avatar.features.mouthColor
        }
        return sample
    }
    @MainActor func fallback(_ avatar: Avatar) -> NSImage {
        let image = NSImage(size: CGSize(width: 144, height: 96), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.translateBy(x: 72, y: 48)
            c.scaleBy(x: 3, y: 3)
            c.setLineCap(.round); c.setLineJoin(.round)
            switch self {
            case .eyes: FaceDrawing.eye(c, id: avatar.eyes, size: 0.5, stretch: 0.5, side: 1, color: AvatarArtwork.eyeColors[avatar.features.eyeColor], blink: false, mood: .neutral)
            case .brows: FaceDrawing.brow(c, id: avatar.brows, size: 0.5, stretch: 0.5, side: 1, color: AvatarArtwork.hairs[avatar.features.browColor], mood: .neutral)
            case .nose:
                if avatar.nose == 0 {
                    c.move(to: CGPoint(x: 0, y: -7)); c.addLine(to: CGPoint(x: -4, y: 5)); c.addLine(to: CGPoint(x: 4, y: 5)); c.closePath()
                    c.setFillColor(AvatarArtwork.skins[avatar.skin].cgColor); c.fillPath()
                    c.setStrokeColor(NSColor(hex: 0x936144).cgColor); c.setLineWidth(1)
                    c.move(to: CGPoint(x: -4, y: 5)); c.addLines(between: [CGPoint(x: 4,y: 5), CGPoint(x: 0,y: -7)]); c.strokePath()
                } else { FaceDrawing.nose(c, id: avatar.nose, size: 0.5, color: AvatarArtwork.skins[avatar.skin]) }
            case .mouth: FaceDrawing.mouth(c, id: avatar.mouth, size: 0.5, stretch: 0.5, color: AvatarArtwork.lipColors[avatar.features.mouthColor], mood: .neutral)
            }
            return true
        }
        return image
    }
}
