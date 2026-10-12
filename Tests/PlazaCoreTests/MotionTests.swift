import XCTest
@testable import PlazaCore

final class MotionTests:XCTestCase {
    func testSolesReachFloorAndStayPlantedAcrossStatures() {
        for amount in [0.0,0.15,0.5,1.0] {for frame in 0..<720 {
            let phase=Double(frame)/720*2 * .pi,p=CharacterMotion.solve(state:1,phase:phase,amount:amount)
            for i in 0..<2 {
                let r=p.legs[i],z = -0.34*sin(r[0])-0.36*sin(r[0]+r[1]),y=0.764+p.bob-0.34*cos(r[0])-0.36*cos(r[0]+r[1])
                XCTAssertEqual(z,p.feet[i].z,accuracy:1e-9)
                XCTAssertEqual(y,0.065+p.feet[i].y,accuracy:1e-9)
                XCTAssertEqual(r.reduce(0,+),p.feet[i].pitch,accuracy:1e-9)
                XCTAssertGreaterThanOrEqual(y,0.065-1e-9)
            }
        }}
        for stature in [0.72,0.92,1.12] {
            for frame in 0..<60 {let u=Double(frame)/100,f=CharacterMotion.foot(phase:u*2 * .pi,amount:1)
                XCTAssertEqual((u*0.48+f.z)*stature,0.144*stature,accuracy:1e-9)
            }
        }
    }
    func testIdleDoesNotAdvanceFootfallsAndAcknowledgementExpires() {
        var crowd=CrowdSimulation(population:1,localCount:1)
        let p=crowd.walkers[0].position,phase=crowd.walkers[0].phase
        crowd.acknowledge(0)
        for _ in 0..<30 {crowd.step(1.0/30)}
        XCTAssertEqual(crowd.walkers[0].position,p);XCTAssertEqual(crowd.walkers[0].phase,phase)
        XCTAssertEqual(crowd.walkers[0].state,3);XCTAssertGreaterThan(crowd.walkers[0].animationTime,0.9)
        for _ in 0..<50 {crowd.step(1.0/30)}
        XCTAssertEqual(crowd.walkers[0].greeting,0);XCTAssertEqual(crowd.walkers[0].state,0)
    }
    func testFootfallDistanceAccountsForDepthAndHeight() {
        for aspect in [0.5,1.0,1.8] {
            var crowd=CrowdSimulation(population:20,localCount:3)
            crowd.worldAspect=aspect;crowd.setStatures(Array(repeating:0.72,count:20))
            var samples=0
            for _ in 0..<900 {
                let old=crowd.walkers;crowd.step(1.0/30)
                for (i,w) in crowd.walkers.enumerated() where w.phase != old[i].phase {
                    let travel=hypot((w.position.x-old[i].position.x)*24,(w.position.y-old[i].position.y)*24/aspect)
                    XCTAssertEqual(w.phase-old[i].phase,travel/(0.48*0.72)*2 * .pi,accuracy:1e-9);samples+=1
                }
            }
            XCTAssertGreaterThan(samples,100)
        }
    }
    func testConversationHasOneSpeakerAfterGreetingAndNoRepeatedWaving() {
        var crowd=CrowdSimulation(population:60,localCount:3)
        var exchanges=0
        for _ in 0..<2400 {
            let before=crowd.walkers;crowd.step(1.0/30)
            for (i,w) in crowd.walkers.enumerated() {
                guard let j=w.partner,j>i,w.greeting<=0,crowd.walkers[j].greeting<=0,w.conversation>crowd.timing.bow else{continue}
                XCTAssertEqual(Set([w.state,crowd.walkers[j].state]),Set([3,5]))
                XCTAssertEqual(w.animationTime,crowd.walkers[j].animationTime,accuracy:1e-9)
                if before[i].partner==w.partner {XCTAssertEqual(w.position,before[i].position,"Conversing visitors must stay planted")}
                exchanges+=1
            }
        }
        XCTAssertGreaterThan(exchanges,100)
    }
}
