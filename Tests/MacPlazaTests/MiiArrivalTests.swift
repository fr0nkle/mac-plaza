import XCTest
import PlazaCore
@testable import MacPlaza

final class MiiArrivalTests:XCTestCase {
    @MainActor func testCameraUsesSimulationTimeWithoutDriftingBetweenTicks() {
        let clock=PlazaArrivalClock(),date=Date()
        clock.begin(Avatar());clock.resume(at:0);clock.advance(to:1.4)
        XCTAssertEqual(clock.elapsed(at:date),1.4)
        XCTAssertEqual(clock.elapsed(at:date.addingTimeInterval(60)),1.4,"Render delays must not run the camera ahead of the Mii")
        clock.pause()
        XCTAssertEqual(clock.elapsed(at:date.addingTimeInterval(120)),1.4)
        clock.resume(at:1.4);clock.advance(to:2)
        XCTAssertEqual(clock.elapsed(at:date),2)
        clock.finish();clock.advance(to:3)
        XCTAssertNil(clock.elapsed(at:date))
    }
    @MainActor func testConfirmedNewMiiReturnsToPlazaAndEditingDoesNotReplayArrival() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model=PlazaModel(directory:directory)
        defer {model.scene.setMoving(false);try? FileManager.default.removeItem(at:directory)}
        for _ in 0..<200 where !model.loaded {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertTrue(model.loaded)
        model.document.preferences.pauseMotion=false
        let count=model.document.avatars.count
        let avatar=Avatar(name:"Arrival Test",outfit:3)
        model.sheet = .characters
        XCTAssertTrue(model.isMoving,"A windowed maker also keeps a visible ordinary plaza moving")
        XCTAssertTrue(model.saveMii(avatar))
        XCTAssertNil(model.sheet)
        XCTAssertEqual(model.document.avatars.count,count+1)
        XCTAssertEqual(model.scene.arrivalClock.avatar?.id,avatar.id)
        XCTAssertTrue(model.scene.fflCharacters.contains {$0.id==avatar.id})
        await model.flush()
        let saved=try await model.storage.load()
        XCTAssertTrue(saved?.avatars.contains {$0.id==avatar.id} == true)
        model.scene.finishArrival()
        model.sheet = .characters
        var edited=avatar;edited.name="Edited Arrival"
        XCTAssertTrue(model.saveMii(edited))
        XCTAssertEqual(model.document.avatars.count,count+1)
        XCTAssertEqual(model.sheet?.id,"characters")
        XCTAssertNil(model.scene.arrivalClock.avatar,"Existing Mii edits stay in the maker")
        model.document.preferences.pauseMotion=true
        XCTAssertTrue(model.saveMii(Avatar(name:"Quiet Arrival",outfit:1)))
        XCTAssertNil(model.sheet)
        XCTAssertNil(model.scene.arrivalClock.avatar,"Pause Motion skips the drop and camera movement")
        await model.flush();try await model.storage.endSession()
    }

    @MainActor func testArrivalWaitsForRendererAndFreezesWhilePaused() async throws {
        let scene=PlazaScene(size:CGSize(width:1200,height:720))
        let avatar=Avatar(name:"Welcome",outfit:1)
        scene.configure(avatars:[avatar],population:20)
        let owner=UUID();var latest:[[Double]]=[]
        scene.attachFFL(owner:owner,frame:{latest=$0},configure:{_ in})
        defer {scene.detachFFL(owner:owner)}
        scene.beginArrival(for:avatar.id,animated:true);scene.setMoving(true)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertNil(scene.arrivalClock.anchor)
        XCTAssertEqual(latest.first?[2],8)
        scene.rendererDidBecomeReady()
        for _ in 0..<100 where scene.arrivalClock.anchor == nil {try await Task.sleep(for:.milliseconds(10))}
        XCTAssertNotNil(scene.arrivalClock.anchor)
        scene.setMoving(false)
        let frozen=scene.arrivalClock.elapsed(at:Date())
        XCTAssertEqual(frozen,scene.arrivalClock.elapsed(at:Date().addingTimeInterval(60)))
        scene.finishArrival()
        XCTAssertNil(scene.arrivalClock.avatar)
        XCTAssertEqual(latest.first?[2],0)
    }

    func testCloseUpReturnsExactlyToTheUsersZoomAndPan() {
        let size=CGSize(width:1200,height:720),pan=CGSize(width:80,height:-30)
        let initial=PlazaViewport.arrivalFocus(elapsed:0,zoom:1.3,offset:pan,size:size)
        let close=PlazaViewport.arrivalFocus(elapsed:2,zoom:1.3,offset:pan,size:size)
        let final=PlazaViewport.arrivalFocus(elapsed:PlazaArrival.duration,zoom:1.3,offset:pan,size:size)
        XCTAssertEqual(initial.zoom,1.3);XCTAssertEqual(initial.offset,pan)
        XCTAssertGreaterThan(close.zoom,4)
        XCTAssertEqual(final.zoom,1.3,accuracy:0.000001)
        XCTAssertEqual(final.offset,pan)
    }
}
