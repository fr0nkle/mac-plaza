import XCTest
@testable import PlazaCore

final class OriginalLoungePlaybackTests: XCTestCase {
    private func catalog() throws -> OriginalLoungeCatalog {
        var names = Set(OriginalLounge.animations.map(\.name))
        for id in [34,110] {
            let root = String(OriginalLounge.animations[id].name.dropLast(2))
            names.insert(root + "_o"); names.insert(root + "_oe")
        }
        return try XCTUnwrap(OriginalLoungeCatalog(clips: names.sorted().map {
            .init(name: $0, frames: $0.hasSuffix("_l") ? 40 : 12, loop: $0.hasSuffix("_l"))
        }))
    }
    func testSeatedExitFinishesBeforeWalkingAndBothEntranceAndMainHaveOriginalBlends() throws {
        let catalog = try catalog()
        var player = OriginalLoungePlayback(catalog: catalog)
        XCTAssertTrue(player.request(34, catalog: catalog))
        XCTAssertEqual(player.stage, .entrance)
        for _ in 0..<14 { player.advance(catalog: catalog); player.finishStages(catalog: catalog) }
        XCTAssertEqual(player.stage, .entrance, "A finished entrance waits for its 15-update blend")
        player.advance(catalog: catalog); player.finishStages(catalog: catalog)
        XCTAssertEqual(player.stage, .main)
        for _ in 0..<5 { player.advance(catalog: catalog) }
        XCTAssertEqual(player.sample.blend, 1, accuracy: 1e-6)
        XCTAssertTrue(player.request(3, catalog: catalog, rate: 0.8))
        XCTAssertEqual(player.stage, .exit)
        XCTAssertEqual(catalog.clips[player.sample.clip].name, "SquatDown00_oe")
        XCTAssertFalse(player.request(10, catalog: catalog))
        for _ in 0..<12 { player.advance(catalog: catalog); player.finishStages(catalog: catalog) }
        XCTAssertEqual(player.stage, .main)
        XCTAssertEqual(catalog.clips[player.sample.clip].name, "Walk00_l")
        XCTAssertEqual(player.rate, 0.8)
    }
    func testSourceFrameClockAndFrozenOutgoingSample() throws {
        let catalog = try catalog()
        var player = OriginalLoungePlayback(catalog: catalog)
        player.advance(catalog: catalog)
        XCTAssertEqual(player.sample.frame, 0); XCTAssertEqual(player.frame, 1)
        player.advance(catalog: catalog, extraAdvance: 2)
        XCTAssertEqual(player.sample.frame, 3); XCTAssertEqual(player.frame, 4)
        XCTAssertTrue(player.request(112, catalog: catalog))
        XCTAssertEqual(player.sample.previousFrame, 3)
        for tick in 1...30 {
            player.advance(catalog: catalog)
            XCTAssertEqual(player.sample.previousFrame, 3)
            XCTAssertEqual(player.sample.blend, min(1, Float(tick)/30), accuracy: 1e-6)
        }
        XCTAssertTrue(player.request(111, catalog: catalog))
        player.advance(catalog: catalog)
        XCTAssertEqual(player.sample.blend, 1/40, accuracy: 1e-6, "Talk's outgoing minimum constrains the incoming bow blend")
        for _ in 0..<50 { player.advance(catalog: catalog) }
        XCTAssertTrue(player.complete(catalog)); XCTAssertEqual(player.frame, 12)
        XCTAssertFalse(player.sample.bridge.contains { !$0.isFinite })
    }
    func testIdlePortRunsDeterministicallyThroughBaselinesActionsAndSeatedRest() throws {
        let catalog = try catalog()
        func trace() -> [Int] {
            var random = OriginalLoungeRandom(seed: 1234)
            var player = OriginalLoungePlayback(catalog: catalog), idle = OriginalLoungeIdle()
            var result: [Int] = []
            for _ in 0..<100000 {
                player.finishStages(catalog: catalog)
                idle.step(playback: &player, catalog: catalog, random: &random, context: .init())
                player.advance(catalog: catalog)
                result.append(player.animation)
            }
            return result
        }
        let first = trace()
        XCTAssertEqual(first, trace())
        XCTAssertGreaterThan(Set(first).intersection(Set(10...25)).count, 10)
        XCTAssertTrue(first.contains { (34...45).contains($0) })
        XCTAssertTrue(first.contains { (50...70).contains($0) })
    }
    func testSchedulerCatchupWrapsTheVisibleLoopAndClampsOneShots() throws {
        let catalog = try catalog()
        var player = OriginalLoungePlayback(catalog: catalog)
        for _ in 0..<38 {player.advance(catalog: catalog)}
        player.advance(catalog: catalog, extraAdvance: 3)
        XCTAssertEqual(player.sample.frame, 1); XCTAssertEqual(player.frame, 2)
        XCTAssertTrue(player.request(111, catalog: catalog))
        for _ in 0..<20 {player.advance(catalog: catalog)}
        player.advance(catalog: catalog, extraAdvance: 4)
        XCTAssertEqual(player.sample.frame, 12); XCTAssertEqual(player.frame, 12)
    }
    func testCatalogRequiresEveryDescriptorAndKeepsResourceIndices() throws {
        XCTAssertNil(OriginalLoungeCatalog(clips: []))
        let catalog = try catalog()
        for id in 0..<128 {
            XCTAssertEqual(catalog.clips[try XCTUnwrap(catalog.clip(animation: id))].name, OriginalLounge.animations[id].name)
        }
        XCTAssertNil(catalog.clip(animation: 111, stage: .entrance))
        XCTAssertEqual(OriginalLounge.socialAnimation(action: 21), 124)
        XCTAssertNil(OriginalLounge.socialAnimation(action: 25))
    }
    func testSameAnimationRequestPreservesPairedPhaseRateAndWalkCanExplicitlyChangeRate() throws {
        let catalog = try catalog()
        var player = OriginalLoungePlayback(catalog:catalog)
        XCTAssertTrue(player.request(112,catalog:catalog))
        player.setRate(0.7)
        XCTAssertFalse(player.request(112,catalog:catalog,rate:1))
        XCTAssertEqual(player.rate,0.7)
        player.advance(catalog:catalog)
        XCTAssertEqual(player.frame,0.7)
        player.setRate(1)
        XCTAssertEqual(player.rate,1)
    }
    func testLocalAppReactionCanStartSourceEligibleOrbitDanceAndMoveRootsWithoutSnapping() throws {
        let catalog = try catalog()
        var found = false
        for seed in 0..<20 where !found {
            var crowd = CrowdSimulation(population:60,localCount:0,seed:UInt64(seed))
            crowd.enableOriginalControllers(catalog)
            for _ in 0..<180 {crowd.step(1.0/60)}
            for i in crowd.walkers.indices where !found {
                let p = crowd.walkers[i].position
                crowd.cheer(near:p)
                if let index = crowd.walkers.indices.first(where:{(11...20).contains(crowd.walkers[$0].originalSocialAction)}) {
                    found = true
                    let j = try XCTUnwrap(crowd.walkers[index].partner)
                    let before = crowd.walkers[index].position, other = crowd.walkers[j].position
                    XCTAssertGreaterThan(hypot(before.x-other.x,before.y-other.y)*960,7)
                    XCTAssertLessThan(hypot(before.x-other.x,before.y-other.y)*960,17)
                    var travel = 0.0, previous = before
                    for _ in 0..<240 {
                        crowd.step(1.0/60)
                        let current = crowd.walkers[index].position
                        let step = hypot(current.x-previous.x,current.y-previous.y)
                        XCTAssertLessThan(step,0.0001,"Original phase-weighted root correction must not teleport the body")
                        travel += step;previous = current
                    }
                    XCTAssertGreaterThan(travel,0.0001)
                    XCTAssertEqual(crowd.walkers[index].partner,j)
                }
            }
        }
        XCTAssertTrue(found,"A local app event should reach the original dance selector and root path")
    }
    func testAutomaticDancesAndCollisionImpulsesRunLocallyWithoutAppReaction() throws {
        let catalog = try catalog()
        var started=0,contacts=0
        for seed in 0..<4 {
            var a=CrowdSimulation(population:60,localCount:0,seed:UInt64(seed)),b=a
            a.groupsBelowIslands=true;a.minimumSpacing=0.012
            a.islands=[.init(0.3,0.15),.init(0.7,0.15)]
            a.enableOriginalControllers(catalog);b=a
            for frame in 0..<3600 {
                let previous=a.walkers
                a.step(1.0/30);b.step(1.0/60);b.step(1.0/60)
                for (i,w) in a.walkers.enumerated() {
                    XCTAssertTrue([w.position.x,w.position.y,w.speed,w.angle,Double(w.originalMotion.collision.impulse.x),Double(w.originalMotion.collision.speedScale)].allSatisfy(\.isFinite))
                    XCTAssertTrue((0.05...0.95).contains(w.position.x));XCTAssertTrue((0.20...0.95).contains(w.position.y))
                    if w.originalMotion.collision.impulse != .init(0,0) {contacts+=1}
                    if frame>0 {XCTAssertLessThan(hypot(w.position.x-previous[i].position.x,w.position.y-previous[i].position.y),0.03)}
                    if let j=w.partner {XCTAssertEqual(a.walkers[j].partner,i)}
                }
            }
            XCTAssertEqual(a.walkers,b.walkers)
            XCTAssertEqual(a.automaticDanceStarts,b.automaticDanceStarts)
            started+=a.automaticDanceStarts
        }
        XCTAssertGreaterThan(contacts,100,"Dense crowds should exercise stored collision impulses")
        print("Automatic group events: \(started) dances; \(contacts) impulse samples across four local deterministic crowds.")
    }
    func testAutomaticOrbitReachableFromSourceNodeNeighbors() throws {
        let catalog=try catalog()
        // Use a known source-eligible placement for reachability. A random
        // crowd need not contain a qualifying side-by-side pair in 120 seconds.
        var reachable=false
        for seed in 0..<20 where !reachable {
            let a=CrowdPoint(0.5,0.5),b=CrowdPoint(0.5+16.0/960,0.5)
            var first=CrowdWalker(position:a,target:a),second=CrowdWalker(position:b,target:b)
            first.wait=100;second.wait=100
            var crowd=CrowdSimulation(placement:[first,second],localCount:0,seed:UInt64(seed))
            // Adjacent source nodes in a single app database: center and (1,-1).
            // This replaces the former host proximity-sector fixture.
            crowd.islands=[.init(0.5,0.221)]
            crowd.enableOriginalControllers(catalog)
            crowd.setGatheringIslands([0:0,1:0])
            for _ in 0..<1800 where crowd.automaticDanceStarts==0 {crowd.step(1.0/60)}
            if crowd.automaticDanceStarts>0 {
                reachable=true
                XCTAssertEqual(crowd.walkers[0].partner,1);XCTAssertEqual(crowd.walkers[1].partner,0)
                XCTAssertTrue((11...20).contains(crowd.walkers[0].originalSocialAction))
            }
        }
        XCTAssertTrue(reachable,"Automatic source opportunities must reach the orbit selector without cheer/click input")
    }
    func testNativeHostRunsAtFixedTicksAndKeepsPairedActionsReciprocal() throws {
        let catalog = try catalog()
        func crowd() -> CrowdSimulation {
            var crowd = CrowdSimulation(population:60,localCount:3)
            crowd.worldAspect=1.25
            crowd.enableOriginalControllers(catalog)
            crowd.strideLength=1.456;crowd.nominalSpeed=1.456*60*0.8461539/40/24
            crowd.islands=[CrowdPoint(0.15,0.18),CrowdPoint(0.38,0.10),CrowdPoint(0.62,0.10),CrowdPoint(0.85,0.18),CrowdPoint(0.89,0.52),CrowdPoint(0.72,0.78),CrowdPoint(0.28,0.78),CrowdPoint(0.11,0.52)]
            return crowd
        }
        var a=crowd(),b=crowd(),actions=Set<Int>(),clips=Set<Int>(),moving=0,paired=0
        for _ in 0..<3600 {
            a.step(1.0/30);b.step(1.0/60);b.step(1.0/60)
            for (i,w) in a.walkers.enumerated() {
                let sample=try XCTUnwrap(a.originalSample(i))
                clips.insert(sample.clip)
                XCTAssertTrue(sample.bridge.allSatisfy(\.isFinite))
                XCTAssertTrue((0...1).contains(sample.blend))
                XCTAssertTrue((0.05...0.95).contains(w.position.x));XCTAssertTrue((0.20...0.95).contains(w.position.y))
                if w.speed>0.005 {moving+=1}
                if let j=w.partner {
                    paired+=1;actions.insert(w.originalSocialAction)
                    XCTAssertEqual(a.walkers[j].partner,i)
                    XCTAssertEqual(a.walkers[j].originalSocialDuration,w.originalSocialDuration)
                    XCTAssertEqual(a.walkers[j].originalSocialTicks,w.originalSocialTicks)
                    XCTAssertNotEqual(a.walkers[j].originalSocialLeader,w.originalSocialLeader)
                }
            }
        }
        XCTAssertEqual(a.walkers,b.walkers)
        XCTAssertEqual(a.originalSample(0),b.originalSample(0))
        XCTAssertGreaterThan(moving,100);XCTAssertGreaterThan(paired,100)
        XCTAssertTrue(actions.isSuperset(of:[0,1,2,21,22,23,24]))
        XCTAssertGreaterThan(clips.count,20)
        let before=a.walkers,pose=a.originalSample(0)
        a.step(0);a.step(.nan)
        XCTAssertEqual(before,a.walkers);XCTAssertEqual(pose,a.originalSample(0))
        print("Native host: \(clips.count) source clips, paired actions \(actions.sorted()), \(moving) moving samples.")
    }
}
