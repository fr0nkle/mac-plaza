import SwiftUI
import AppKit

/// A shared outline for the plaza's white speech panels and journal posts.
enum PlazaPostStyle {
    static let name = Color(white: 0.28)
    static let text = Color(white: 0.24)
    static let edge = Color(white: 0.76)
    static let radius: CGFloat = 16

    static func outline(in rect: CGRect, tailX: CGFloat? = nil, tailAtTop: Bool = false) -> Path {
        let top: CGFloat = tailX != nil && tailAtTop ? 9 : 0
        let bottom: CGFloat = tailX != nil && !tailAtTop ? 9 : 0
        let body = CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: rect.height - top - bottom)
        let r = min(radius, body.height / 2, body.width / 2)
        let x = min(body.maxX - r - 9, max(body.minX + r + 9, tailX ?? body.midX))
        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        if tailX != nil && tailAtTop {
            p.addLine(to: CGPoint(x: x - 8, y: body.minY))
            p.addQuadCurve(to: CGPoint(x: x, y: rect.minY), control: CGPoint(x: x - 3, y: body.minY - 2))
            p.addLine(to: CGPoint(x: x + 8, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + r), control: CGPoint(x: body.maxX, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addQuadCurve(to: CGPoint(x: body.maxX - r, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        if tailX != nil && !tailAtTop {
            p.addLine(to: CGPoint(x: x + 8, y: body.maxY))
            p.addQuadCurve(to: CGPoint(x: x, y: rect.maxY), control: CGPoint(x: x + 3, y: body.maxY + 2))
            p.addLine(to: CGPoint(x: x - 8, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - r), control: CGPoint(x: body.minX, y: body.maxY))
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addQuadCurve(to: CGPoint(x: body.minX + r, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        p.closeSubpath()
        return p
    }
}

struct PlazaSpeechPanel: Shape {
    var tailX: CGFloat? = nil
    func path(in rect: CGRect) -> Path { PlazaPostStyle.outline(in: rect, tailX: tailX) }
}

struct PlazaPostSurface: ViewModifier {
    var tailX: CGFloat? = nil
    func body(content: Content) -> some View {
        content
            .background {
                PlazaSpeechPanel(tailX: tailX)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.98).opacity(0.97)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
            }
            .overlay { PlazaSpeechPanel(tailX: tailX).stroke(PlazaPostStyle.edge.opacity(0.65), lineWidth: 1) }
    }
}

struct PlazaNameTab: View {
    var name: String
    var large = false
    var body: some View {
        Text(name).font(.system(size: large ? 12 : 10, weight: .medium, design: .rounded))
            .lineLimit(1).foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(PlazaPostStyle.name, in: Capsule())
    }
}

/// One to three posts per interval, with quiet gaps between journal and friends.
/// Elapsed time is advanced only while the plaza can present posts.
struct PlazaPostCadence {
    enum Presentation { case quiet, journal, friends }
    private(set) var elapsed: TimeInterval = 0
    private(set) var bubbleCount = 1
    private var hasPresented = false
    var presentation: Presentation {
        let phase = elapsed.truncatingRemainder(dividingBy: 52)
        if (12..<22).contains(phase) { return .journal }
        if (36..<46).contains(phase) { return .friends }
        return .quiet
    }
    mutating func advance(by seconds: TimeInterval, held: Bool = false) {
        guard !held, seconds.isFinite, seconds > 0 else { return }
        let previous = presentation
        elapsed = (elapsed + seconds.truncatingRemainder(dividingBy: 52)).truncatingRemainder(dividingBy: 52)
        if presentation != .quiet, presentation != previous {
            // Pick a different density each time, rather than always filling all slots.
            if !hasPresented { bubbleCount = Int.random(in: 1...3); hasPresented = true }
            else {
                let choice = Int.random(in: 1...2)
                bubbleCount = choice >= bubbleCount ? choice + 1 : choice
            }
        }
    }
}
