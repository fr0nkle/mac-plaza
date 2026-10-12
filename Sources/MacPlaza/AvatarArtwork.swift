import AppKit
import SceneKit
import PlazaCore

/// Built-in fallback artwork. FFL mode uses the locally imported original head resources.
@MainActor
enum AvatarArtwork {
    static func clearCaches(){cache.removeAll();heads.removeAllObjects();faces.removeAllObjects()}
    static let outfits: [NSColor] = [0xD21E14,0xFF6E19,0xFFD820,0x78D220,0x007830,0x0A48BC,0x3CAADE,0xF55A7D,0x7328AD,0x483818,0xE0E0E0,0x181814].map(NSColor.init(hex:))
    static let skins: [NSColor] = [0xFFD3AD,0xFEB66B,0xDE7942,0xFFAA8C,0xAD5129,0x632C18].map(NSColor.init(hex:))
    static let hairs: [NSColor] = [0x000000,0x402010,0x5C180A,0x7C3A14,0x787880,0x4E3E11,0x875917,0xD0A049].map(NSColor.init(hex:))
    static let eyeColors: [NSColor] = [0x000000,0x717372,0x663C2C,0x686537,0x4B58A8,0x387059].map(NSColor.init(hex:))
    static let lipColors: [NSColor] = [0x823018,0x780C0D,0x882028,0xDC7751,0x461E0A].map(NSColor.init(hex:))
    static let glassColors: [NSColor] = [0x252321,0x75432C,0xA83729,0x254C81,0xB39B35,0x909293].map(NSColor.init(hex:))
    private static var cache: [String: NSImage] = [:]
    private static let renderer = SCNRenderer(device:nil,options:nil)
    static func image(_ avatar: Avatar, direction: Int = 0, size: CGSize = CGSize(width: 96, height: 128), pose: Int = 0) -> NSImage {
        let key = String(describing: avatar) + "\(direction)-\(size)-\(pose)"
        if let image = cache[key] { return image }
        let scene = SCNScene(); let rig = CharacterRig(avatar); scene.rootNode.addChildNode(rig.root)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.wantsHDR=false; camera.camera?.orthographicScale = 1.40
        camera.position = SCNVector3(0,1.20,6); scene.rootNode.addChildNode(camera)
        rig.root.eulerAngles.y = CGFloat(direction % 8) * .pi / 4
        rig.pose(state:pose,phase:1,amount:pose==1 ? 1:0,time:0.4);rig.setFace(blink:false,mood:pose==4 ? .happy:pose==5 ? .surprised:.neutral)
        CharacterRig.addLighting(to: scene)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        renderer.scene=nil; renderer.pointOfView=nil
        if size.width*size.height<=100_000 { if cache.count>=128 {cache.removeAll()};cache[key]=image };return image
    }
    private static let heads:NSCache<NSString,NSImage> = { let c=NSCache<NSString,NSImage>();c.countLimit=192;c.totalCostLimit=12*1024*1024;return c }()
    static func headshot(_ a:Avatar,size:CGSize=CGSize(width:96,height:96)) -> NSImage {
        let key=(String(describing:a)+"head-\(size)") as NSString
        if let image=heads.object(forKey:key) {return image}
        let scene=SCNScene(),rig=CharacterRig(a),camera=SCNNode();scene.rootNode.addChildNode(rig.head)
        camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.wantsHDR=false;camera.camera?.orthographicScale=0.67
        camera.position=SCNVector3(0,rig.head.position.y-0.035,5);scene.rootNode.addChildNode(camera);CharacterRig.addLighting(to:scene)
        renderer.scene=scene;renderer.pointOfView=camera;let image=renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling4X);renderer.scene=nil;renderer.pointOfView=nil
        heads.setObject(image,forKey:key,cost:Int(size.width*size.height)*4);return image
    }
    private static let faces: NSCache<NSString,NSImage> = { let c=NSCache<NSString,NSImage>(); c.countLimit=160; c.totalCostLimit=64*1024*1024; return c }()
    /// Transparent facial mask, wrapped around the head surface by CharacterRig.
    static func face(_ a: Avatar, blink: Bool = false, mood: FaceMood = .neutral) -> NSImage {
        let key=(String(describing:a)+"\(blink)-\(mood.rawValue)") as NSString
        if let cached=faces.object(forKey:key) { return cached }
        let f = a.features
        let image = NSImage(size: CGSize(width: 256,height: 256), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.scaleBy(x: 2, y: 2); c.setLineCap(.round); c.setLineJoin(.round)
            func ellipse(_ r: CGRect, _ color: NSColor) { c.setFillColor(color.cgColor); c.fillEllipse(in:r) }
            func line(_ points: [CGPoint], _ color: NSColor, _ width: CGFloat = 1.5) { c.setStrokeColor(color.cgColor); c.setLineWidth(width); c.addLines(between: points); c.strokePath() }
            let ink = NSColor(hex: 0x2F251E)
            if f.makeup > 0 {
                let color = NSColor(hex: f.makeup % 3 == 0 ? 0xBD715D : 0xDB8D81).withAlphaComponent(0.18 + Double(f.makeup / 3) * 0.08)
                ellipse(CGRect(x: 22,y:65,width:20,height:10),color); ellipse(CGRect(x:86,y:65,width:20,height:10),color)
            }
            if a.beard {
                let y = 85.0 + Double(f.beardType % 3)*3
                if f.beardType % 2 == 0 { ellipse(CGRect(x:48,y:y,width:32,height:24),hairs[f.facialHairColor]) }
                else { c.setStrokeColor(hairs[f.facialHairColor].cgColor); c.setLineWidth(CGFloat(5+f.beardType)); c.addArc(center: CGPoint(x:64,y:78), radius:29,startAngle:0.18,endAngle:2.96,clockwise:false); c.strokePath() }
            }
            let global = (a.featureHeight-0.5)*14
            for side in [-1.0,1.0] {
                let x=64+side*(13+a.eyeSpacing*15),y=65+(f.eyeY-0.5)*25+global
                c.saveGState();c.translateBy(x:x,y:y);c.rotate(by:side*(f.eyeRotation-0.5)*0.9)
                FaceDrawing.eye(c,id:a.eyes,size:f.eyeSize,stretch:f.eyeStretch,side:side,color:eyeColors[f.eyeColor],blink:blink,mood:mood);c.restoreGState()
                let bx=64+side*(13+f.browSpacing*15),by=49+(f.browY-0.5)*25+global
                c.saveGState();c.translateBy(x:bx,y:by);c.rotate(by:side*(f.browRotation-0.5)*1.2)
                FaceDrawing.brow(c,id:a.brows,size:f.browSize,stretch:f.browStretch,side:side,color:hairs[f.browColor],mood:mood);c.restoreGState()
            }
            c.saveGState();c.translateBy(x:64,y:76+(f.noseY-0.5)*22+global)
            FaceDrawing.nose(c,id:a.nose,size:f.noseSize,color:skins[a.skin]);c.restoreGState()
            c.saveGState();c.translateBy(x:64,y:88+(f.mouthY-0.5)*25+global)
            FaceDrawing.mouth(c,id:a.mouth,size:f.mouthSize,stretch:f.mouthStretch,color:lipColors[f.mouthColor],mood:mood);c.restoreGState()
            if f.mustache > 0 {
                let y = 77 + (f.mustacheY-0.5)*20+global, w=15+f.mustacheSize*25
                for side in [-1.0,1.0] { c.saveGState(); c.translateBy(x:64+side*w*0.2,y:y); c.rotate(by:side*Double(f.mustache%3-1)*0.25); ellipse(CGRect(x:-w/4,y:-2,width:w/2,height:Double(3+f.mustache)),hairs[f.facialHairColor]); c.restoreGState() }
            }
            if a.glasses {
                let gy=65+(f.glassesY-0.5)*27+global, gw=18+f.glassesSize*18, gh=12+f.glassesSize*7
                c.setStrokeColor(glassColors[f.glassesColor].cgColor); c.setLineWidth(f.glassesType>5 ? 3:2)
                for side in [-1.0,1.0] { let r=CGRect(x:64+side*23-gw/2,y:gy-gh/2,width:gw,height:gh); if f.glassesType%3 == 1 { c.strokeEllipse(in:r) } else { c.addPath(CGPath(roundedRect:r,cornerWidth:f.glassesType%3 == 2 ? 4:1,cornerHeight:4,transform:nil)); c.strokePath() }; if f.glassesType>5 { ellipse(r,glassColors[f.glassesColor].withAlphaComponent(0.25)) } }
                line([CGPoint(x:59,y:gy),CGPoint(x:69,y:gy)],glassColors[f.glassesColor],2)
            }
            if f.mole { let r=1+f.moleSize*3; ellipse(CGRect(x:23+f.moleX*82-r/2,y:35+f.moleY*68-r/2,width:r,height:r),ink) }
            if f.wrinkles>0 { for side in [-1.0,1.0] { let x=64+side*39; line([CGPoint(x:x,y:57),CGPoint(x:x+side*4,y:60)],skins[a.skin].blended(withFraction:0.3,of:.black)!,0.6+Double(f.wrinkles%3)*0.4); if f.wrinkles>3 { line([CGPoint(x:48,y:24),CGPoint(x:80,y:24)],skins[a.skin].blended(withFraction:0.25,of:.black)!,0.6) } } }
            return true
        }
        // Material images are concrete 256-pixel rasters. A drawing-handler NSImage can
        // otherwise generate extra Retina representations lazily inside SceneKit.
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:256,pixelsHigh:256,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else {return image}
        bitmap.size=CGSize(width:256,height:256)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        image.draw(in:NSRect(x:0,y:0,width:256,height:256),from:.zero,operation:.copy,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let raster=NSImage(size:CGSize(width:256,height:256));raster.addRepresentation(bitmap)
        faces.setObject(raster,forKey:key,cost:bitmap.bytesPerRow*bitmap.pixelsHigh);return raster
    }
}

extension NSColor {
    convenience init(hex: Int) { self.init(srgbRed:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,alpha:1) }
}
