import XCTest
import PlazaCore
@testable import MacPlaza

final class PrimaryMiiSceneTests:XCTestCase {
    @MainActor func testSceneCentersChosenPrimaryAndChangingItPreservesSixtyPoses() {
        let scene=PlazaScene(size:CGSize(width:1200,height:720)),owner=UUID()
        let avatars=[Avatar(name:"First"),Avatar(name:"Second"),Avatar(name:"Main")]
        var frames:[[Double]]=[],configurations=0
        scene.attachFFL(owner:owner,frame:{frames=$0},configure:{_ in configurations+=1})
        defer {scene.detachFFL(owner:owner)}
        scene.configure(avatars:avatars,population:60,primaryAvatarID:avatars[2].id)
        XCTAssertEqual(frames.count,60)
        let depth=48.0*720/1200/(16/sqrt(22.0*22+16*16))
        let main=frames[2],x=main[0]/48+0.5,y=main[1]/depth+0.5
        XCTAssertLessThan(hypot(x-0.5,y-0.55),0.12,"Use the chosen primary identity, even when it is not first")
        let poses=frames.map {Array($0.prefix(4))}
        scene.configure(avatars:avatars,population:60,primaryAvatarID:avatars[0].id)
        XCTAssertEqual(configurations,2,"Changing only the primary identity must update the simulation")
        XCTAssertEqual(frames.map {Array($0.prefix(4))},poses,"Change routes, never relocate the crowd")
        XCTAssertEqual(Set(scene.fflCharacters.map(\.id)).count,60)
    }
}
