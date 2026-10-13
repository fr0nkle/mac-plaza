import SwiftUI

/// A continuous, fine checker floor receding into the white plaza horizon.
/// Both renderers and the zoomed backdrop share the same viewport coordinates.
struct PlazaGround: View {
    var viewportSize: CGSize? = nil

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, canvasSize in
            let size = viewportSize ?? canvasSize
            guard size.width > 0, size.height > 0 else { return }
            let margin = CGSize(width: (canvasSize.width - size.width) / 2,
                                height: (canvasSize.height - size.height) / 2)
            context.translateBy(x: margin.width, y: margin.height)
            let bounds = CGRect(x: -margin.width, y: -margin.height,
                                width: canvasSize.width, height: canvasSize.height)
            let bottom = CGPoint(x: 0, y: size.height)
            context.fill(Path(bounds), with: .linearGradient(Gradient(colors: [
                Color(red: 0.985, green: 0.988, blue: 0.980),
                Color(red: 0.94, green: 0.95, blue: 0.935),
                Color(red: 0.86, green: 0.885, blue: 0.87)
            ]), startPoint: .zero, endPoint: bottom))

            // Project a tiled plane rather than placing disconnected diamonds.
            // Tile rows get smaller and flatter as they recede into the distance.
            let perspective: CGFloat = 0.45
            let halfWidth = max(4, size.width / 128)
            let halfHeight = halfWidth * 0.30
            let centerX = size.width / 2
            func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let scale = 1 / max(0.1, 1 - perspective * y / size.height)
                return CGPoint(x: centerX + (x - centerX) * scale, y: y * scale)
            }
            func planeY(_ y: CGFloat) -> CGFloat {
                y / max(0.1, 1 + perspective * y / size.height)
            }
            let firstRow = Int(floor(planeY(max(0, bounds.minY)) / halfHeight)) - 2
            let lastRow = Int(ceil(planeY(bounds.maxY) / halfHeight)) + 2
            var lightTiles = Path()
            for row in firstRow...max(firstRow, lastRow) where (row & 1) == 0 {
                let y = CGFloat(row) * halfHeight
                let scale = 1 / max(0.1, 1 - perspective * (y - halfHeight) / size.height)
                let firstColumn = Int(floor((centerX + (bounds.minX - centerX) / scale) / (halfWidth * 2))) - 2
                let lastColumn = Int(ceil((centerX + (bounds.maxX - centerX) / scale) / (halfWidth * 2))) + 2
                for column in firstColumn...max(firstColumn, lastColumn) {
                    let x = CGFloat(column) * halfWidth * 2
                    lightTiles.move(to: project(x, y - halfHeight))
                    lightTiles.addLine(to: project(x + halfWidth, y))
                    lightTiles.addLine(to: project(x, y + halfHeight))
                    lightTiles.addLine(to: project(x - halfWidth, y))
                    lightTiles.closeSubpath()
                }
            }
            // One batched fill keeps the enlarged floor inexpensive to redraw.
            context.fill(lightTiles, with: .color(.white.opacity(0.50)))
            context.fill(Path(bounds), with: .linearGradient(Gradient(stops: [
                .init(color: .white.opacity(0.90), location: 0),
                .init(color: .white.opacity(0.30), location: 0.30),
                .init(color: .clear, location: 0.65)
            ]), startPoint: .zero, endPoint: bottom))
        }
    }
}
