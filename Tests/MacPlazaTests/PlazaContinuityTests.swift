import XCTest
import PlazaCore
@testable import MacPlaza

final class PlazaContinuityTests:XCTestCase {
    @MainActor func testSceneReconfigurationPreservesPositionsAndVisitorIdentities() async throws {
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),owner=UUID()
        var frames:[[Double]]=[]
        scene.attachFFL(owner:owner,frame:{frames=$0},configure:{_ in})
        defer {scene.detachFFL(owner:owner)}
        var avatar=Avatar(name:"Continuity",outfit:0)
        scene.configure(avatars:[avatar],population:20)
        let before=frames,identities=scene.fflCharacters.map(\.id)
        XCTAssertEqual(before.count,20);XCTAssertEqual(Set(identities).count,20)
        avatar.hair=12;avatar.outfit=4
        scene.configure(avatars:[avatar],population:20)
        XCTAssertEqual(frames,before,"Editing a Mii must preserve every world pose and animation sample")
        XCTAssertEqual(scene.fflCharacters.map(\.id),identities)
        scene.configure(avatars:[avatar],population:10)
        XCTAssertEqual(frames,Array(before.prefix(10)))
        scene.configure(avatars:[avatar],population:20)
        XCTAssertEqual(frames,before,"Temporarily reducing the population must not shuffle returning visitors")
        scene.beginEntrance(enabled:false)
        scene.configure(avatars:[avatar],population:21)
        XCTAssertEqual(Array(frames.prefix(20)),before)
        XCTAssertTrue(scene.entranceClock.finished)
    }
    @MainActor func testReconfigurationDoesNotFinishOrRestartActiveBootEntrance() async throws {
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),owner=UUID()
        var frames:[[Double]]=[]
        scene.attachFFL(owner:owner,frame:{frames=$0},configure:{_ in})
        defer {scene.detachFFL(owner:owner)}
        var avatar=Avatar(name:"Boot",outfit:0)
        scene.configure(avatars:[avatar],population:20);scene.beginEntrance(enabled:true)
        let entering=frames
        avatar.hair=33
        scene.configure(avatars:[avatar],population:20)
        XCTAssertFalse(scene.entranceClock.finished)
        XCTAssertEqual(frames,entering,"A pending renderer update must preserve the boot entrance pose")
    }
}
