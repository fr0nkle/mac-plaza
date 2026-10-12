import XCTest
@testable import PlazaCore

final class PlazaArrivalTests:XCTestCase {
    func testCameraEasingIsBoundedAndSettlesWithoutVelocityOrAccelerationJumps() {
        XCTAssertGreaterThan(PlazaArrival.zoomIn,PlazaArrival.landing)
        for frame in 0...1000 {
            XCTAssertTrue((0...1).contains(PlazaArrival.focus(at:Double(frame)/1000*PlazaArrival.duration)))
        }
        let delta=0.001
        for boundary in [0,PlazaArrival.zoomIn,PlazaArrival.pullback,PlazaArrival.duration] {
            let a=PlazaArrival.focus(at:boundary-delta),b=PlazaArrival.focus(at:boundary),c=PlazaArrival.focus(at:boundary+delta)
            XCTAssertEqual((c-a)/(2*delta),0,accuracy:0.0001)
            XCTAssertEqual((c-2*b+a)/(delta*delta),0,accuracy:0.025)
        }
        XCTAssertEqual(PlazaArrival.focus(at:PlazaArrival.zoomIn),1)
        XCTAssertEqual(PlazaArrival.focus(at:PlazaArrival.duration),0)
    }
    func testArrivalHoldsOnlyTheNewMiiThenReleasesItToRoam() throws {
        for original in [false,true] {
            var waveClips=Set<Int>()
            var crowd=CrowdSimulation(population:40,localCount:4)
            crowd.groupsBelowIslands=true;crowd.islands=[CrowdPoint(0.2,0.15),CrowdPoint(0.8,0.15)]
            if original {
                var names=Set(OriginalLounge.animations.map(\.name))
                for id in [34,110] {
                    let root=String(OriginalLounge.animations[id].name.dropLast(2))
                    names.insert(root+"_o");names.insert(root+"_oe")
                }
                let catalog=try XCTUnwrap(OriginalLoungeCatalog(clips:names.sorted().map {
                    .init(name:$0,frames:$0.hasSuffix("_l") ? 40:12,loop:$0.hasSuffix("_l"))
                }))
                waveClips=Set(catalog.clips.indices.filter {catalog.clips[$0].name.hasPrefix("Handwaving")})
                crowd.enableOriginalControllers(catalog)
            }
            crowd.setGatheringIslands([0:0,1:1,2:0])
            let others=crowd.walkers.prefix(3).map(\.position)
            crowd.beginArrival(index:3)
            var sawWave=false,sawOriginalWave=false
            for _ in 0..<180 {
                crowd.step(1.0/30)
                let mii=crowd.walkers[3]
                XCTAssertEqual(mii.position,PlazaArrival.center)
                XCTAssertNil(mii.partner)
                if mii.state==3 {sawWave=true;XCTAssertEqual(mii.angle,0)}
                if let sample=crowd.originalSample(3) {
                    // The installed-body bridge must receive the greeting, too.
                    sawOriginalWave = sawOriginalWave || waveClips.contains(sample.clip)
                }
            }
            XCTAssertTrue(sawWave)
            if original {XCTAssertTrue(sawOriginalWave)}
            XCTAssertNotEqual(others,crowd.walkers.prefix(3).map(\.position),"Other Miis keep simulating during the welcome")
            for _ in 0..<600 {crowd.step(1.0/30)}
            XCTAssertNil(crowd.arrivalIndex);XCTAssertNil(crowd.arrivalElapsed)
            XCTAssertGreaterThan(hypot(crowd.walkers[3].position.x-0.5,crowd.walkers[3].position.y-0.55),0.005)
        }
    }
    func testSkippingAndInvalidIndicesLeaveNoReservedActor() {
        var crowd=CrowdSimulation(population:20,localCount:1)
        crowd.beginArrival(index:50)
        XCTAssertNil(crowd.arrivalIndex)
        crowd.beginArrival(index:0);crowd.finishArrival()
        XCTAssertNil(crowd.arrivalIndex)
        XCTAssertEqual(crowd.walkers[0].wait,0)
        XCTAssertNotEqual(crowd.walkers[0].target,PlazaArrival.center)
        XCTAssertEqual(PlazaArrival.height(at:0),8)
        XCTAssertEqual(PlazaArrival.height(at:2),0,accuracy:0.0001)
    }
}
