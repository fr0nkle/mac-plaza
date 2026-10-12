import XCTest
import AppKit
import PlazaCore
import ImageIO
@testable import MacPlaza

final class FFLTests:XCTestCase {
    @MainActor
    func testResourceImportRejectsDirectoriesAndOversizedOrEmptyFiles() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        XCTAssertThrowsError(try FFLResources.checkedData(at:root))
        let empty=root.appendingPathComponent("empty.dat");try Data().write(to:empty)
        XCTAssertThrowsError(try FFLResources.checkedData(at:empty))
        let large=root.appendingPathComponent("large.dat")
        _ = FileManager.default.createFile(atPath:large.path,contents:nil)
        let handle=try FileHandle(forWritingTo:large);try handle.truncate(atOffset:65*1024*1024);try handle.close()
        XCTAssertThrowsError(try FFLResources.checkedData(at:large))
    }
    @MainActor
    func testAllMakerFieldsReachFFLAsValidStoreData() throws {
        var avatar=Avatar(name:"Offline");avatar.hair=131;avatar.face=11;avatar.eyes=59;avatar.features.flipHair=true;avatar.features.mustache=5
        let payload=try FFLSurface.avatar(avatar)
        let data=try XCTUnwrap(Data(base64Encoded:payload["data"] as! String))
        let decoded=try MiiFile.decode(data)
        XCTAssertEqual(decoded.hair,131);XCTAssertEqual(decoded.face,11);XCTAssertEqual(decoded.eyes,59);XCTAssertTrue(decoded.features.flipHair)
    }
    @MainActor
    func testInvalidResourceLeavesInstalledCopyUntouched() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let old=root.appendingPathComponent("FFLResHigh.dat"),incoming=root.appendingPathComponent("wrong.dat")
        try Data(repeating:1,count:2048).write(to:old);try Data(repeating:0,count:2048).write(to:incoming)
        let resources=FFLResources(directory:root)
        await resources.install(incoming)
        XCTAssertTrue(resources.installed);XCTAssertEqual(try Data(contentsOf:old),Data(repeating:1,count:2048))
        XCTAssertTrue(resources.message.contains("not installed"))
        var corrupt=Data(repeating:0,count:2048);corrupt.replaceSubrange(0..<4,with:Data("FFRA".utf8));try corrupt.write(to:incoming)
        await resources.install(incoming)
        XCTAssertTrue(resources.installed);XCTAssertEqual(try Data(contentsOf:old),Data(repeating:1,count:2048))
        XCTAssertTrue(resources.message.contains("not installed"))
    }
    @MainActor
    func testLongLocalNamesStillRenderWithConsoleData() throws {
        var a=Avatar(name:"A long local nickname");a.features.creator="A long local creator"
        XCTAssertNoThrow(try FFLSurface.avatar(a));XCTAssertThrowsError(try MiiFile.encode(a))
    }
    @MainActor
    func testFFLResourceAndOriginalShaderRenderLocally() async throws {
        guard let path=ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else{throw XCTSkip("Set PLAZA_FFL_QA_RESOURCE to a local FFL/AFL resource to exercise the actual renderer.")}
        _=NSApplication.shared
        let data=try FFLResources.checkedData(at:URL(fileURLWithPath:path))
        let surface=FFLSurface(mode:"portrait",resource:data,useInstalledBody:false)
        try await surface.waitUntilReady()
        let blocked:Any = try await withCheckedThrowingContinuation { continuation in
            surface.webView.callAsyncJavaScript("return fetch('https://example.invalid/blocked').then(()=>false,()=>true)",arguments:[:],in:nil,in:.page){continuation.resume(with:$0)}
        }
        XCTAssertEqual(blocked as? Bool,true,"Content Security Policy must reject external connections.")
        var avatar=Avatar(name:"FFL QA")
        let front=try await surface.portrait(avatar,width:256,height:384)
        let back=try await surface.portrait(avatar,angle:.pi,width:256,height:384)
        let wave=try await surface.portrait(avatar,pose:3,width:256,height:384)
        let frontPNG=try png(front),backPNG=try png(back),wavePNG=try png(wave)
        XCTAssertNotEqual(frontPNG,backPNG);XCTAssertNotEqual(frontPNG,wavePNG)
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:frontPNG))
        var visible=0
        for y in stride(from:0,to:384,by:4){for x in stride(from:0,to:256,by:4){if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.5{visible += 1}}}
        XCTAssertGreaterThan(visible,120,"The FFL renderer must produce a visible head and body, not an empty canvas.")
        // Exercise the crowded path too: repeated bodies are batched while masks blink independently.
        let crowd=FFLSurface(mode:"plaza",resource:data,useInstalledBody:false)
        try await crowd.waitUntilReady()
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in
            crowd.configure(Array(repeating:avatar,count:200)){error in if let error{c.resume(throwing:error)}else{c.resume()}}
        }
        let positions:[[Double]]=(0..<200).map {i in
            let x=Double(i%20)*1.2-11.4,z=Double(i/20)*1.1-4.95,blink:Double=i==0 ? 1:0
            return [x,z,0,0,0,0,0,0,blink,0]
        }
        let encoded=try JSONSerialization.data(withJSONObject:positions)
        let frames=String(decoding:encoded,as:UTF8.self)
        let stats:Any=try await withCheckedThrowingContinuation{c in
            crowd.webView.evaluateJavaScript("window.plazaFFL.frame(\(frames));window.plazaFFL.diagnostics()"){value,error in if let error{c.resume(throwing:error)}else{c.resume(returning:value ?? NSNull())}}
        }
        let report=try XCTUnwrap(stats as? [String:Any]);XCTAssertEqual(report["rigs"] as? Int,200)
        XCTAssertEqual(report["models"] as? Int,1);XCTAssertLessThan(report["drawCalls"] as! Int,2000)
        XCTAssertGreaterThan(report["bodyInstances"] as! Int,1600)
        let masks=try XCTUnwrap(report["masks"] as? [[String:Any]])
        XCTAssertNotEqual(masks[0]["material"] as? String,masks[1]["material"] as? String)
        XCTAssertNotEqual(masks[0]["texture"] as? String,masks[1]["texture"] as? String)
        crowd.invalidate()
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        for (name,image) in [("FFL Front",frontPNG),("FFL Back",backPNG),("FFL Wave",wavePNG)]{try image.write(to:root.appendingPathComponent(name+".png"))}
        let gallery=NSImage(size:CGSize(width:960,height:720));gallery.lockFocus();NSColor(hex:0xf2f3ef).setFill();NSRect(x:0,y:0,width:960,height:720).fill()
        // Render outside lockFocus to avoid carrying a graphics context across suspension.
        gallery.unlockFocus()
        for i in 0..<12 {
            avatar.hair=[33,12,44,0,37,18,55,28,1,93,69,131][i];avatar.face=i;avatar.eyes=[2,0,8,24,18,35,15,40,6,53,32,59][i];avatar.skin=i%6;avatar.hairColor=i%8;avatar.glasses=i%4==0
            let head=try await surface.portrait(avatar,headOnly:true,width:240,height:240)
            gallery.lockFocus();head.draw(in:NSRect(x:(i%4)*240,y:(2-i/4)*240,width:240,height:240));gallery.unlockFocus()
        }
        try png(gallery).write(to:root.appendingPathComponent("FFL Appearance Gallery.png"))
    }
    @MainActor
    func testArticulatedFFLRigContactsAndMotionParity() async throws {
        guard let path=ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else{throw XCTSkip("Requires a local FFL/AFL resource.")}
        _=NSApplication.shared
        let surface=FFLSurface(mode:"plaza",resource:try FFLResources.checkedData(at:URL(fileURLWithPath:path)),useInstalledBody:false)
        defer{surface.invalidate()}
        try await surface.waitUntilReady()
        var avatar=Avatar(name:"Motion QA")
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        let gallery=NSImage(size:CGSize(width:1024,height:768));gallery.lockFocus();NSColor(hex:0xf2f3ef).setFill();NSRect(x:0,y:0,width:1024,height:768).fill();gallery.unlockFocus()
        var walkFrames:[CGImage]=[]
        for height in [0.0,0.5,1.0] {for build in [0.0,1.0] {
            avatar.height=height;avatar.build=build
            _=try await surface.portrait(avatar,width:256,height:384)
            for frame in 0..<12 {
                let phase=Double(frame)/12*2 * .pi,time=Double(frame)*0.1
                let w=[0.0,0,0,0,1,phase,1,0,0,0,time,0,0]
                let json=String(decoding:try JSONEncoder().encode([w]),as:UTF8.self)
                let result=try await evaluate(surface,"window.plazaFFL.frame(\(json));({stats:window.plazaFFL.diagnostics(),motion:window.plazaFFL.motion(1,\(phase),1,\(time)),png:window.plazaFFL.snapshot()})") as! [String:Any]
                let stats=result["stats"] as! [String:Any],feet=(stats["feet"] as! [[[Double]]])[0]
                let p=CharacterMotion.solve(state:1,phase:phase,amount:1,time:time)
                let motion=result["motion"] as! [String:Any]
                XCTAssertEqual(motion["bob"] as! Double,p.bob,accuracy:1e-10)
                for i in 0..<2 {
                    XCTAssertEqual(feet[i][1],(0.065+p.feet[i].y)*(0.72+height*0.4),accuracy:1e-8)
                    XCTAssertEqual(feet[i][2],p.feet[i].z*(0.72+height*0.4),accuracy:1e-8)
                }
                if height==0.5 && build==0 {
                    var display=w;display[3]=0.65
                    let shown=String(decoding:try JSONEncoder().encode([display]),as:UTF8.self)
                    let shot=try await evaluate(surface,"window.plazaFFL.frame(\(shown));window.plazaFFL.snapshot()") as! String
                    let payload=shot.split(separator:",").last!,data=try XCTUnwrap(Data(base64Encoded:String(payload)))
                    let bitmap=try XCTUnwrap(NSBitmapImageRep(data:data)),cg=try XCTUnwrap(bitmap.cgImage)
                    let opaque=NSImage(size:CGSize(width:256,height:384));opaque.lockFocus();NSColor(hex:0xf2f3ef).setFill();NSRect(x:0,y:0,width:256,height:384).fill();NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:0,y:0,width:256,height:384));opaque.unlockFocus()
                    walkFrames.append(try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(opaque.tiffRepresentation))?.cgImage))
                    if frame<8 {gallery.lockFocus();NSImage(cgImage:cg,size:.zero).draw(in:NSRect(x:(frame%4)*256,y:(1-frame/4)*384,width:256,height:384));gallery.unlockFocus()}
                }
            }
        }}
        try png(gallery).write(to:root.appendingPathComponent("FFL Walking Study.png"))
        let gif=try XCTUnwrap(CGImageDestinationCreateWithURL(root.appendingPathComponent("FFL Walking.gif") as CFURL,"com.compuserve.gif" as CFString,walkFrames.count,nil))
        CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in walkFrames {CGImageDestinationAddImage(gif,frame,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)}
        XCTAssertTrue(CGImageDestinationFinalize(gif))
        // Distinct speaker/listener poses and independently composed facial expressions.
        avatar.height=0.5;avatar.build=0.5
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in surface.configure([avatar,avatar]){e in if let e{c.resume(throwing:e)}else{c.resume()}}}
        let two=[[ -0.55,0,0,1.1,3,0,0,1,0,3,1.5,0,0],[0.55,0,0,-1.1,5,0,0,1,0,0,1.5,0,0]]
        let json=String(decoding:try JSONEncoder().encode(two),as:UTF8.self)
        let encoded=try await evaluate(surface,"for(let i=0;i<8;i++)window.plazaFFL.frame(\(json));window.plazaFFL.snapshot()") as! String
        try XCTUnwrap(Data(base64Encoded:String(encoded.split(separator:",").last!))).write(to:root.appendingPathComponent("FFL Conversation.png"))
    }
    @MainActor private func evaluate(_ surface:FFLSurface,_ script:String) async throws->Any {
        try await withCheckedThrowingContinuation{c in surface.webView.evaluateJavaScript(script){v,e in if let e{c.resume(throwing:e)}else{c.resume(returning:v ?? NSNull())}}}
    }
    private func png(_ image:NSImage) throws -> Data {let rep=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(image.tiffRepresentation)));return try XCTUnwrap(rep.representation(using:.png,properties:[:]))}
}
