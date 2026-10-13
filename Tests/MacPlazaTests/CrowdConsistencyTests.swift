import XCTest
import AppKit
import PlazaCore
@testable import MacPlaza

final class CrowdConsistencyTests:XCTestCase {
    @MainActor func testVisitorAppearanceAndPosesSurviveRosterEditsAtSixty() {
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),owner=UUID()
        let mine=[Avatar(name:"One"),Avatar(name:"Two"),Avatar(name:"Three")]
        scene.configure(avatars:mine,population:60)
        var poses:[[Double]]=[],events:[String]=[]
        scene.attachFFL(owner:owner,frame:{poses=$0;events.append("frame")},configure:{_ in events.append("roster")})
        defer {scene.detachFFL(owner:owner)}
        scene.configure(avatars:mine,population:60,localCount:2)
        let before=scene.fflCharacters,positions=Dictionary(uniqueKeysWithValues:zip(before.map(\.id),poses.map {Array($0.prefix(4))}))
        events=[]
        scene.configure(avatars:mine+[Avatar(name:"New")],population:60)
        XCTAssertEqual(events.first,"roster","Identify the roster before sending its poses")
        XCTAssertEqual(scene.fflCharacters.count,60);XCTAssertEqual(poses.count,60)
        XCTAssertEqual(Set(scene.fflCharacters.map(\.id)).count,60)
        XCTAssertEqual(Array(poses[mine.count].prefix(4)),positions[before.last!.id],"The new member takes the vacated slot")
        let old=Dictionary(uniqueKeysWithValues:before.map {($0.id,$0)})
        for (i,avatar) in scene.fflCharacters.enumerated() where old[avatar.id] != nil {
            XCTAssertEqual(avatar,old[avatar.id],"Adding one Mii must not change any surviving visitor's appearance")
            XCTAssertEqual(Array(poses[i].prefix(4)),positions[avatar.id],"Existing Miis keep their location and facing")
        }
    }

    @MainActor func testPopulationSettingIncludesSavedMiisAndStaysSixtyInLowPowerMode() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=PlazaModel(directory:directory)
        defer {model.scene.setMoving(false);try? FileManager.default.removeItem(at:directory)}
        for _ in 0..<200 where !model.loaded {try await Task.sleep(for:.milliseconds(10))}
        model.document.preferences.population=60;model.document.preferences.safeMode=false
        model.scene.finishEntrance();model.social.preview()
        for lowPower in [false,true,false] {
            model.lowPower=lowPower;model.rebuildScene()
            XCTAssertEqual(model.scene.fflCharacters.count,60)
            XCTAssertEqual(Set(model.scene.fflCharacters.map(\.id)).count,60)
        }
        await model.flush();try await model.storage.endSession()
    }

    @MainActor func testRealRendererRetainsSixtyRigsAndRejectsStaleIndexPoses() async throws {
        guard let head=ProcessInfo.processInfo.environment["PLAZA_FFL_QA_RESOURCE"] else {throw XCTSkip("Requires a local head resource")}
        _=NSApplication.shared
        for original in [false,true] {
            let surface=FFLSurface(mode:"plaza",resource:try FFLResources.checkedData(at:URL(fileURLWithPath:head)),useInstalledBody:original)
            try await surface.waitUntilReady()
            let avatars=(0..<60).map {Avatar(name:"Stable \($0)",outfit:$0%12)}
            try await configure(surface,avatars)
            let poses=(0..<60).map {i -> [Double] in [Double(i%10)*3-13.5,Double(i/10)*2-5,0,0,0,0,0,0,0,0,0,0,0]}
            let payload=String(decoding:try JSONEncoder().encode(poses),as:UTF8.self)
            let ids=String(decoding:try JSONEncoder().encode(avatars.map {$0.id.uuidString}),as:UTF8.self)
            let before=try await evaluate(surface,"window.plazaFFL.frame(\(payload),\(ids));window.plazaFFL.diagnostics()")
            let first=try XCTUnwrap(before["roster"] as? [[String:Any]])
            let reversed=Array(avatars.reversed())
            try await configure(surface,reversed)
            // Deliver an already queued frame in the old order after the new
            // roster is installed. Each Mii must keep its own pose and rig.
            let after=try await evaluate(surface,"window.plazaFFL.frame(\(payload),\(ids));window.plazaFFL.diagnostics()")
            let second=try XCTUnwrap(after["roster"] as? [[String:Any]])
            XCTAssertEqual(second.count,60)
            for (old,new) in zip(first,second.reversed()) {
                XCTAssertEqual(old["id"] as? String,new["id"] as? String)
                XCTAssertEqual(old["root"] as? String,new["root"] as? String)
                XCTAssertEqual(old["position"] as? [Double],new["position"] as? [Double])
                XCTAssertEqual(new["visible"] as? Bool,true)
            }
            // Repeat same-size substitutions: fallback batches must not retain
            // ghost limbs, and unchanged actors must never be reconstructed.
            var updated=[Avatar(name:"Admitted")]+Array(reversed.dropLast())
            try await configure(surface,updated)
            let admission=try await evaluate(surface,"window.plazaFFL.diagnostics()")
            let admitted=try XCTUnwrap(admission["roster"] as? [[String:Any]])
            XCTAssertEqual(admitted[0]["position"] as? [Double],second.last?["position"] as? [Double],
                           "Admission at another array index must use the vacated actor's pose")
            XCTAssertEqual(admitted[1]["root"] as? String,second[0]["root"] as? String)
            for _ in 0..<3 {
                updated[0]=Avatar(name:"Replacement",outfit:3)
                try await configure(surface,updated)
                let report=try await evaluate(surface,"window.plazaFFL.diagnostics()")
                XCTAssertEqual(report["rigs"] as? Int,60)
                XCTAssertEqual(report["bodyInstances"] as? Int,before["bodyInstances"] as? Int)
                let roster=try XCTUnwrap(report["roster"] as? [[String:Any]])
                XCTAssertTrue(roster.allSatisfy {$0["visible"] as? Bool == true})
                XCTAssertEqual(roster[1]["root"] as? String,admitted[1]["root"] as? String)
            }
            surface.invalidate()
        }
    }
    @MainActor private func configure(_ surface:FFLSurface,_ avatars:[Avatar]) async throws {
        try await withCheckedThrowingContinuation {(c:CheckedContinuation<Void,Error>) in surface.configure(avatars) {error in
            if let error {c.resume(throwing:error)}else{c.resume()}
        }}
    }
    @MainActor private func evaluate(_ surface:FFLSurface,_ script:String) async throws -> [String:Any] {
        try await withCheckedThrowingContinuation {c in surface.webView.evaluateJavaScript(script) {value,error in
            if let error {c.resume(throwing:error)}else{c.resume(returning:value as? [String:Any] ?? [:])}
        }}
    }
}
