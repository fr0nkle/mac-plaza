import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> CGColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).cgColor }
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let c = context.cgContext; c.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    c.setFillColor(color(0xF2F7EE)); c.addPath(CGPath(roundedRect: CGRect(x: 38, y: 38, width: 948, height: 948), cornerWidth: 215, cornerHeight: 215, transform: nil)); c.fillPath()
    c.setFillColor(color(0xDFEDE1)); c.fillEllipse(in: CGRect(x: 95, y: 170, width: 834, height: 600))
    c.setStrokeColor(color(0xFFFFFF)); c.setLineWidth(14); c.strokeEllipse(in: CGRect(x: 135, y: 200, width: 754, height: 540))
    let people: [(CGFloat, CGFloat, UInt32, UInt32)] = [(290, 340, 0xD5A078, 0xE0A85F), (660, 340, 0x885638, 0xDC8191), (475, 450, 0xEAC19B, 0x408D83)]
    for (x, y, skin, outfit) in people {
        c.setFillColor(color(0xCFDCD2)); c.fillEllipse(in: CGRect(x: x - 25, y: y - 20, width: 125, height: 35))
        c.setFillColor(color(0x394E56)); c.fill(CGRect(x: x + 5, y: y, width: 22, height: 70)); c.fill(CGRect(x: x + 49, y: y, width: 22, height: 70))
        c.setFillColor(color(outfit)); c.addPath(CGPath(roundedRect: CGRect(x: x - 9, y: y + 45, width: 100, height: 105), cornerWidth: 30, cornerHeight: 30, transform: nil)); c.fillPath()
        c.setFillColor(color(skin)); c.fillEllipse(in: CGRect(x: x - 31, y: y + 125, width: 144, height: 151))
        c.saveGState(); c.addEllipse(in: CGRect(x: x - 31, y: y + 125, width: 144, height: 151)); c.clip()
        c.setFillColor(color(0x654332)); c.fillEllipse(in: CGRect(x: x - 45, y: y + 223, width: 175, height: 85)); c.restoreGState()
        c.setFillColor(color(0x394039)); c.fillEllipse(in: CGRect(x: x + 7, y: y + 188, width: 12, height: 18)); c.fillEllipse(in: CGRect(x: x + 64, y: y + 188, width: 12, height: 18))
        let smile = CGMutablePath(); smile.move(to: CGPoint(x: x + 13, y: y + 168)); smile.addQuadCurve(to: CGPoint(x: x + 70, y: y + 168), control: CGPoint(x: x + 41, y: y + 139))
        c.addPath(smile); c.setStrokeColor(color(0x72473D)); c.setLineWidth(6); c.setLineCap(.round); c.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(pixels) { try data.write(to: destination.appendingPathComponent("icon_\(pixels)x\(pixels).png")) }
    if [32, 64, 256, 512, 1024].contains(pixels) { try data.write(to: destination.appendingPathComponent("icon_\(pixels / 2)x\(pixels / 2)@2x.png")) }
}
