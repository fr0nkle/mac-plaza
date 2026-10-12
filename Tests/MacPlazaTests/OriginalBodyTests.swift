import XCTest
import AppKit
import ImageIO
import PlazaCore
@testable import MacPlaza

final class OriginalBodyTests:XCTestCase {
    @MainActor func testRecoveredControllerSamplesRenderLocally()async throws {
        guard let path=ProcessInfo.processInfo.environment["PLAZA_MENU_QA_RESOURCE"],let head=ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else{throw XCTSkip("Requires local original menu/head resources.")}
        _=NSApplication.shared
        let surface=FFLSurface(mode:"plaza",resource:try FFLResources.checkedData(at:URL(fileURLWithPath:head)),useInstalledBody:false)
        defer{surface.invalidate()}
        try await surface.waitUntilReady()
        let data=try await surface.importMenu(PlazaBodyResources.checkedMenu(at:URL(fileURLWithPath:path)))
        let resource=try JSONSerialization.jsonObject(with:data) as! [String:Any],headers=resource["animations"] as! [[String:Any]]
        let catalog=try XCTUnwrap(OriginalLoungeCatalog(clips:headers.map {
            .init(name:$0["name"] as! String,frames:Float($0["frames"] as! Double),loop:$0["loop"] as! Bool)
        }))
        var avatars:[Avatar]=[]
        for i in 0..<20 {var a=Avatar(name:"Port QA",outfit:i%12);a.height=Double(i%7)/7;a.features.gender=i%2;avatars.append(a)}
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in surface.configure(avatars){error in if let error{c.resume(throwing:error)}else{c.resume()}}}
        var crowd=CrowdSimulation(population:20,localCount:2)
        crowd.worldAspect=1.25;crowd.enableOriginalControllers(catalog)
        crowd.strideLength=1.456;crowd.nominalSpeed=1.456*60*0.8461539/40/24
        crowd.setStatures(avatars.map{0.5+($0.height*127).rounded()*0.77/128})
        crowd.islands=[CrowdPoint(0.38,0.10),CrowdPoint(0.62,0.10),CrowdPoint(0.89,0.52),CrowdPoint(0.72,0.78),CrowdPoint(0.28,0.78),CrowdPoint(0.11,0.52)]
        var nativeClips=Set<Int>()
        for frame in 0..<1800 {
            if frame==300 {crowd.acknowledge(0)}
            if frame==900 {crowd.cheer(near:crowd.walkers[0].position)}
            crowd.step(1.0/30)
            guard frame%30==0 || (300...345).contains(frame) else{continue}
            let samples=crowd.walkers.enumerated().map {i,w->[Double] in
                let base=[(w.position.x-0.5)*24,(w.position.y-0.5)*24/1.25,0,w.angle,Double(w.state),w.phase,w.motion,0,0,Double(w.mood),w.animationTime,w.lookYaw,w.turn,Double(w.activity.rawValue),w.activityTime,w.activityDuration,crowd.animationClock]
                return base+crowd.originalSample(i)!.bridge
            }
            let json=String(decoding:try JSONEncoder().encode(samples),as:UTF8.self)
            surface.frame(samples)
            // Exercise the real structured frame bridge, including delivery
            // completion, rather than injecting the poses through a test path.
            let report=try await deliveredFrame(surface,crowd:crowd,catalog:catalog)
            let actual=report["original"] as! [[String:Any]]
            for i in 0..<4 {
                let sample=try XCTUnwrap(crowd.originalSample(i));nativeClips.insert(sample.clip)
                XCTAssertEqual(actual[i]["nativeController"] as? Bool,true)
                XCTAssertEqual(actual[i]["clip"] as? String,catalog.clips[sample.clip].name)
                XCTAssertEqual(actual[i]["frame"] as! Double,Double(sample.frame),accuracy:1e-6)
                XCTAssertEqual(actual[i]["blend"] as! Double,Double(sample.blend),accuracy:1e-6)
            }
            if frame==1200 {
                let first=actual
                _=try await evaluate(surface,"window.plazaFFL.frame(\(json))")
                let second=(try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any])["original"] as! [[String:Any]]
                XCTAssertEqual(try JSONSerialization.data(withJSONObject:first,options:.sortedKeys),try JSONSerialization.data(withJSONObject:second,options:.sortedKeys),"Repeating a paused native snapshot must not advance renderer blending")
                let encoded=try await evaluate(surface,"window.plazaFFL.snapshot()") as! String
                let png=try XCTUnwrap(Data(base64Encoded:String(encoded.split(separator:",").last!)))
                try png.write(to:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa/Native Port Crowd.png"))
            }
        }
        XCTAssertGreaterThan(nativeClips.count,12)
        if PlazaBodyResources.shared.installed {XCTAssertEqual(PlazaBodyResources.shared.originalCatalog?.clips.count,172,"The installed resource must activate the native controller adapter")}
    }
    @MainActor func testReplacingRendererKeepsNewFrameDeliveryAndMotion()async throws{
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),old=UUID(),replacement=UUID()
        scene.attachFFL(owner:old,frame:{_ in XCTFail("Outgoing renderer received a frame")},configure:{_ in})
        var frames=0
        scene.attachFFL(owner:replacement,frame:{_ in frames += 1},configure:{_ in})
        scene.setMoving(true);scene.detachFFL(owner:old)
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertGreaterThan(frames,1,"Outgoing view teardown must not stop the replacement renderer")
        scene.detachFFL(owner:replacement);let stopped=frames
        try await Task.sleep(for:.milliseconds(100));XCTAssertEqual(frames,stopped)
    }
    @MainActor func testRejectsWrongMenuHeadersWithoutReplacingData()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let old=root.appendingPathComponent("plaza-body.json"),incoming=root.appendingPathComponent("wrong.pack"),data=Data("old resource".utf8);try data.write(to:old);try Data(repeating:0,count:2048).write(to:incoming)
        XCTAssertThrowsError(try PlazaBodyResources.checkedMenu(at:incoming));XCTAssertThrowsError(try PlazaBodyResources.check(Data("{}".utf8)))
        let resource=PlazaBodyResources(directory:root);await resource.install(incoming);XCTAssertEqual(try Data(contentsOf:old),data)
    }
    @MainActor func testOriginalMenuBodiesAndCurvesRenderWithoutNetwork()async throws{
        guard let path=ProcessInfo.processInfo.environment["PLAZA_MENU_QA_RESOURCE"],let head=ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else{throw XCTSkip("Set local Men2.pack and FFL paths to exercise original body assets.")}
        _=NSApplication.shared
        let surface=FFLSurface(mode:"plaza",resource:try FFLResources.checkedData(at:URL(fileURLWithPath:head)),useInstalledBody:false);defer{surface.invalidate()}
        try await surface.waitUntilReady()
        let pack=try await surface.importMenu(PlazaBodyResources.checkedMenu(at:URL(fileURLWithPath:path)))
        let count=try PlazaBodyResources.check(pack);XCTAssertEqual(count,172)
        let decoded=try JSONSerialization.jsonObject(with:pack) as! [String:Any],models=decoded["models"] as! [[String:Any]]
        XCTAssertEqual((models[0]["positions"] as! [Double]).count,940*3);XCTAssertEqual((models[1]["positions"] as! [Double]).count,955*3)
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent(".qa")
        var a=Avatar(name:"Original plaza")
        for (name,gender,pose) in [("Original Male",0,0),("Original Female",1,0),("Original Wave",0,3),("Original Walk",0,1)]{
            a.features.gender=gender;let image=try await surface.portrait(a,angle:0.5,pose:pose,width:320,height:480)
            try png(image).write(to:root.appendingPathComponent(name+".png"))
        }
        let report=try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any]
        XCTAssertEqual(report["originalBodies"] as? Bool,true);XCTAssertEqual(report["originalClips"] as? Int,172)
        XCTAssertEqual((report["original"] as! [[String:Any]])[0]["clip"] as? String,"Walk00_l")
        var frames:[CGImage]=[]
        for i in 0..<40 {
            let phase=Double(i)/40*2 * .pi,w=[0.0,0,0,0.65,1,phase,1,0,0,0,Double(i)/30,0,0],json=String(decoding:try JSONEncoder().encode([w]),as:UTF8.self)
            let encoded=try await evaluate(surface,"window.plazaFFL.frame(\(json));window.plazaFFL.snapshot()") as! String
            let bytes=try XCTUnwrap(Data(base64Encoded:String(encoded.split(separator:",").last!))),image=try XCTUnwrap(NSImage(data:bytes))
            let opaque=NSImage(size:CGSize(width:320,height:480));opaque.lockFocus();NSColor(hex:0xf2f3ef).setFill();NSRect(x:0,y:0,width:320,height:480).fill();image.draw(in:NSRect(x:0,y:0,width:320,height:480));opaque.unlockFocus();frames.append(try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(opaque.tiffRepresentation))?.cgImage))
        }
        let gif=try XCTUnwrap(CGImageDestinationCreateWithURL(root.appendingPathComponent("Original Plaza Walk.gif") as CFURL,"com.compuserve.gif" as CFString,frames.count,nil));CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for frame in frames{CGImageDestinationAddImage(gif,frame,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/30]] as CFDictionary)};XCTAssertTrue(CGImageDestinationFinalize(gif))
        // The actual source clips must be selected by the native activity clocks,
        // including the seated entrance and stand-up exit, not only the walk path.
        let sheet=NSImage(size:CGSize(width:960,height:960));sheet.lockFocus();NSColor(hex:0xf2f3ef).setFill();NSRect(x:0,y:0,width:960,height:960).fill();sheet.unlockFocus()
        var clock=10.0
        let activities:[(Int,Double,Double,String)]=[(1,0.3,2.5,"Handwaving00_o"),(1,1.0,2.5,"Handwaving00_l"),(1,2.1,2.5,"Handwaving00_oe"),(7,0.8,340.0/30,"SquatDown00_o"),(7,5,340.0/30,"SquatDown00_l"),(7,10.8,340.0/30,"SquatDown00_oe"),(4,2,4.8,"LookAround00_o"),(2,2,130.0/30,"Talk00_l"),(10,1.5,2,"Bow00_o")]
        for (index,value) in activities.enumerated(){
            let (activity,time,duration,expected)=value
            for _ in 0..<8 {clock+=1.0/30
                let state=activity==1 || activity==2 ? 3:0
                let w=[0.0,0,0,0.45,Double(state),0,0,activity==2 ? 1:0,0,0,time,0,0,Double(activity),time,duration,clock]
                let json=String(decoding:try JSONEncoder().encode([w]),as:UTF8.self)
                _=try await evaluate(surface,"window.plazaFFL.frame(\(json))")
            }
            let report=try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any]
            XCTAssertEqual((report["original"] as! [[String:Any]])[0]["clip"] as? String,expected)
            let encoded=try await evaluate(surface,"window.plazaFFL.snapshot()") as! String
            let bytes=try XCTUnwrap(Data(base64Encoded:String(encoded.split(separator:",").last!))),image=try XCTUnwrap(NSImage(data:bytes))
            sheet.lockFocus();image.draw(in:NSRect(x:(index%3)*320,y:(2-index/3)*320,width:320,height:320));sheet.unlockFocus()
        }
        try png(sheet).write(to:root.appendingPathComponent("Original Activity Sequences.png"))
        // Real crowded path, original shared geometry and independent FFL masks.
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in surface.configure(Array(repeating:a,count:60)){e in if let e{c.resume(throwing:e)}else{c.resume()}}}
        let stats=try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any];XCTAssertEqual(stats["rigs"] as? Int,60);XCTAssertLessThan(stats["drawCalls"] as! Int,700)
        let malformed=Data(repeating:0,count:2048)
        do{_=try await surface.importMenu(malformed);XCTFail("Invalid archive accepted")}catch{}
        let still=try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any];XCTAssertEqual(still["originalBodies"] as? Bool,true)
    }
    @MainActor private func evaluate(_ surface:FFLSurface,_ script:String)async throws->Any{try await withCheckedThrowingContinuation{c in surface.webView.evaluateJavaScript(script){v,e in if let e{c.resume(throwing:e)}else{c.resume(returning:v ?? NSNull())}}}}
    @MainActor private func deliveredFrame(_ surface:FFLSurface,crowd:CrowdSimulation,catalog:OriginalLoungeCatalog)async throws->[String:Any] {
        let deadline=ProcessInfo.processInfo.systemUptime+3
        repeat {
            let report=try await evaluate(surface,"window.plazaFFL.diagnostics()") as! [String:Any]
            let actual=report["original"] as! [[String:Any]]
            let count=min(4,crowd.walkers.count) // Renderer diagnostics cap pose detail at four rigs.
            if actual.count==count && (0..<count).allSatisfy({i in
                guard let sample=crowd.originalSample(i) else{return false}
                return actual[i]["clip"] as? String==catalog.clips[sample.clip].name &&
                    actual[i]["frame"] as? Double==Double(sample.frame) && actual[i]["blend"] as? Double==Double(sample.blend)
            }) {return report}
            try await Task.sleep(for:.milliseconds(5))
        } while ProcessInfo.processInfo.systemUptime<deadline
        throw FFLError.message("The native pose snapshot did not reach the structured frame bridge")
    }
    private func png(_ image:NSImage)throws->Data{let rep=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(image.tiffRepresentation)));return try XCTUnwrap(rep.representation(using:.png,properties:[:]))}
}
