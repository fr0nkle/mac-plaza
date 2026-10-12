import SwiftUI

/// Vector pictograms following the feature silhouettes and grouping of the Wii U editor.
/// Kept as paths so they stay crisp at every display scale.
struct MiiFeatureIcon: View {
    enum Kind { case face, hair, brows, eyes, nose, mouth, accessories, mustache, beard, mole, body, makeup, wrinkles, camera }
    let kind: Kind
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            context.translateBy(x: (size.width-64*scale)/2, y: (size.height-64*scale)/2)
            context.scaleBy(x: scale, y: scale)
            let ink = GraphicsContext.Shading.foreground
            func fill(_ p: Path) { context.fill(p, with: ink) }
            func line(_ p: Path, _ width: CGFloat = 3) { context.stroke(p, with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)) }
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, filled: Bool = true) {
                let p = Path(ellipseIn: CGRect(x:x,y:y,width:w,height:h)); if filled {fill(p)} else {line(p)}
            }
            func contour() -> Path {
                var p=Path();p.move(to:CGPoint(x:32,y:5))
                p.addCurve(to:CGPoint(x:57,y:27),control1:CGPoint(x:49,y:5),control2:CGPoint(x:58,y:14))
                p.addCurve(to:CGPoint(x:32,y:60),control1:CGPoint(x:57,y:43),control2:CGPoint(x:40,y:58))
                p.addCurve(to:CGPoint(x:7,y:27),control1:CGPoint(x:24,y:58),control2:CGPoint(x:7,y:43))
                p.addCurve(to:CGPoint(x:32,y:5),control1:CGPoint(x:6,y:14),control2:CGPoint(x:15,y:5));p.closeSubpath();return p
            }
            func mustache() -> Path {
                var p=Path();p.move(to:CGPoint(x:32,y:39))
                p.addCurve(to:CGPoint(x:9,y:53),control1:CGPoint(x:22,y:32),control2:CGPoint(x:18,y:49))
                p.addQuadCurve(to:CGPoint(x:32,y:48),control:CGPoint(x:23,y:58))
                p.addQuadCurve(to:CGPoint(x:55,y:53),control:CGPoint(x:41,y:58))
                p.addCurve(to:CGPoint(x:32,y:39),control1:CGPoint(x:46,y:49),control2:CGPoint(x:42,y:32));p.closeSubpath();return p
            }
            switch kind {
            case .face, .makeup, .wrinkles:
                line(contour());ellipse(19,25,5,6);ellipse(40,25,5,6)
                var smile=Path();smile.move(to:CGPoint(x:22,y:42));smile.addQuadCurve(to:CGPoint(x:42,y:42),control:CGPoint(x:32,y:53));line(smile)
                if kind == .makeup {ellipse(11,35,12,7);ellipse(41,35,12,7)}
                if kind == .wrinkles {
                    var p=Path();for y in [16.0,20.0] {p.move(to:CGPoint(x:24,y:y));p.addLine(to:CGPoint(x:40,y:y))};line(p,2)
                }
            case .hair:
                line(contour(),3)
                var p=Path();p.move(to:CGPoint(x:7,y:29));p.addCurve(to:CGPoint(x:57,y:29),control1:CGPoint(x:3,y:-3),control2:CGPoint(x:61,y:-3));p.addLine(to:CGPoint(x:47,y:31));p.addLine(to:CGPoint(x:39,y:23));p.addLine(to:CGPoint(x:30,y:32));p.addLine(to:CGPoint(x:22,y:24));p.addLine(to:CGPoint(x:15,y:32));p.closeSubpath();fill(p)
            case .brows:
                var p=Path();p.move(to:CGPoint(x:4,y:38));p.addLine(to:CGPoint(x:27,y:26));p.addLine(to:CGPoint(x:27,y:34));p.closeSubpath()
                p.move(to:CGPoint(x:60,y:38));p.addLine(to:CGPoint(x:37,y:26));p.addLine(to:CGPoint(x:37,y:34));p.closeSubpath();fill(p)
            case .eyes:
                ellipse(3,21,26,21,filled:false);ellipse(35,21,26,21,filled:false)
                ellipse(14,22,9,19);ellipse(41,22,9,19)
            case .nose:
                var p=Path();p.move(to:CGPoint(x:38,y:8));p.addCurve(to:CGPoint(x:25,y:44),control1:CGPoint(x:36,y:21),control2:CGPoint(x:23,y:33));p.addQuadCurve(to:CGPoint(x:40,y:49),control:CGPoint(x:25,y:52));line(p,7)
            case .mouth:
                var upper=Path();upper.move(to:CGPoint(x:6,y:29));upper.addCurve(to:CGPoint(x:32,y:23),control1:CGPoint(x:17,y:11),control2:CGPoint(x:26,y:17));upper.addCurve(to:CGPoint(x:58,y:29),control1:CGPoint(x:40,y:13),control2:CGPoint(x:49,y:15));upper.closeSubpath();fill(upper)
                var lower=Path();lower.move(to:CGPoint(x:6,y:35));lower.addLine(to:CGPoint(x:58,y:35));lower.addQuadCurve(to:CGPoint(x:6,y:35),control:CGPoint(x:32,y:64));fill(lower)
            case .accessories:
                ellipse(3,8,25,25,filled:false);ellipse(36,8,25,25,filled:false)
                var p=Path();p.move(to:CGPoint(x:28,y:19));p.addQuadCurve(to:CGPoint(x:36,y:19),control:CGPoint(x:32,y:16));line(p)
                fill(mustache());ellipse(56,47,5,5)
            case .mustache: fill(mustache())
            case .beard:
                var p=Path();p.move(to:CGPoint(x:10,y:25));p.addQuadCurve(to:CGPoint(x:32,y:43),control:CGPoint(x:18,y:44));p.addQuadCurve(to:CGPoint(x:54,y:25),control:CGPoint(x:47,y:44));p.addQuadCurve(to:CGPoint(x:32,y:61),control:CGPoint(x:52,y:52));p.addQuadCurve(to:CGPoint(x:10,y:25),control:CGPoint(x:12,y:52));fill(p)
            case .mole: line(contour(),2);ellipse(42,39,7,7)
            case .body:
                ellipse(22,5,20,20);fill(Path(roundedRect:CGRect(x:25,y:28,width:14,height:21),cornerRadius:3))
                var p=Path();for x in [28.0,36.0] {p.move(to:CGPoint(x:x,y:46));p.addLine(to:CGPoint(x:x,y:59))};line(p,5)
            case .camera:
                var p=Path(roundedRect:CGRect(x:5,y:18,width:54,height:36),cornerRadius:5)
                p.addRoundedRect(in:CGRect(x:20,y:10,width:24,height:14),cornerSize:CGSize(width:3,height:3));fill(p)
                context.blendMode = .destinationOut;context.fill(Path(ellipseIn:CGRect(x:22,y:26,width:20,height:20)),with:.color(.white))
            }
        }.accessibilityHidden(true)
    }
}

enum MiiEditorStyle {
    static let green = Color(red:0.42,green:0.66,blue:0.14)
    static let darkGreen = Color(red:0.23,green:0.37,blue:0.14)
    static let lime = Color(red:0.88,green:0.96,blue:0.48)
    static let ink = Color(red:0.23,green:0.27,blue:0.22)
}

struct MiiControlStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(MiiEditorStyle.ink)
            .background(LinearGradient(colors:selected ? [Color(red:0.95,green:1,blue:0.75),MiiEditorStyle.lime] : [.white,Color(red:0.92,green:0.94,blue:0.90)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.95),lineWidth:2))
            .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(selected ? MiiEditorStyle.green.opacity(0.65):.black.opacity(0.12),lineWidth:1).padding(3))
            .shadow(color:.black.opacity(configuration.isPressed ? 0.04:0.12),radius:2,y:configuration.isPressed ? 0:3)
            .opacity(enabled ? (configuration.isPressed ? 0.75:1):0.4)
    }
}
